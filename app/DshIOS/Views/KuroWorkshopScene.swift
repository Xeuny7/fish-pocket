import SwiftUI
import WebKit

@MainActor
final class KuroWorkshopPage: NSObject, WKNavigationDelegate {
    let view: WKWebView
    private var ready: Bool?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        view.navigationDelegate = self
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "KuroWorkshopRenderer") else {
            ready = false
            return
        }
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { ready = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { ready = false }

    func configure(skin: String?, keyboard: WorkshopKeyboard?) async throws {
        for _ in 0..<100 where ready == nil { try await Task.sleep(for: .milliseconds(50)) }
        guard ready == true else { throw KuroWorkshop.AssetError.invalid }
        let status = try await view.callAsyncJavaScript("return await configurePet(skin, keyboard)", arguments: [
            "skin": skin ?? "", "keyboard": keyboard?.json ?? "",
        ], contentWorld: .page) as? String
        if status == "artwork" { throw KuroWorkshop.AssetError.artwork }
        guard status == "ok" else { throw KuroWorkshop.AssetError.invalid }
    }

    func update(activity: String, keys: [String], animate: Bool, dragPosition: CGPoint?) async throws {
        let drag: Any
        if let dragPosition {
            drag = ["x": Double(dragPosition.x), "y": Double(dragPosition.y)]
        } else {
            drag = NSNull()
        }
        _ = try await view.callAsyncJavaScript("updatePet(activity, keys, animate, drag)", arguments: [
            "activity": activity, "keys": keys, "animate": animate, "drag": drag,
        ], contentWorld: .page)
    }

    func thumbnail(skin: String) async throws -> Data {
        try await configure(skin: skin, keyboard: nil)
        let encoded = try await view.callAsyncJavaScript("return petThumbnail()", arguments: [:], contentWorld: .page) as? String
        guard let encoded, let data = Data(base64Encoded: encoded), !data.isEmpty else {
            throw KuroWorkshop.AssetError.invalid
        }
        return data
    }
}

struct KuroWorkshopScene: UIViewRepresentable {
    let skin: String?
    let keyboard: WorkshopKeyboard?
    var activity = "resting"
    var stroke = KuroCatStroke()
    var animate = true
    var dragPosition: CGPoint?
    var onReady: ((Bool) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView { context.coordinator.page.view }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.update(skin: skin, keyboard: keyboard, activity: activity, stroke: stroke,
                                   animate: animate && !reduceMotion && scenePhase == .active,
                                   dragPosition: dragPosition, onReady: onReady)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        view.stopLoading()
    }

    @MainActor
    final class Coordinator {
        let page = KuroWorkshopPage()
        private var configured = false
        private var skin: String?
        private var keyboard: WorkshopKeyboard?
        private var activity = "resting"
        private var animate = false
        private var dragPosition: CGPoint?
        private var onReady: ((Bool) -> Void)?
        private var reportedReady = false
        private var revision: Int?
        private var keys: [String] = []
        private var needsUpdate = false
        var task: Task<Void, Never>?

        func update(skin: String?, keyboard: WorkshopKeyboard?, activity: String, stroke: KuroCatStroke,
                    animate: Bool, dragPosition: CGPoint?, onReady: ((Bool) -> Void)?) {
            if self.skin != skin || self.keyboard != keyboard { configured = false }
            self.skin = skin
            self.keyboard = keyboard
            self.activity = activity
            self.animate = animate
            self.dragPosition = dragPosition
            self.onReady = onReady
            if dragPosition != nil || !animate {
                keys.removeAll()
            } else if let revision {
                let count = min(64, max(0, stroke.revision &- revision))
                keys = Array((keys + stroke.keys.suffix(count).map(\.label)).suffix(64))
            }
            revision = stroke.revision
            needsUpdate = true
            guard task == nil else { return }
            task = Task { [weak self] in await self?.drain() }
        }

        private func drain() async {
            defer { task = nil }
            do {
                while needsUpdate && !Task.isCancelled {
                    needsUpdate = false
                    if !configured {
                        let requestedSkin = skin, requestedKeyboard = keyboard
                        try await page.configure(skin: requestedSkin, keyboard: requestedKeyboard)
                        configured = skin == requestedSkin && keyboard == requestedKeyboard
                        if !configured { continue }
                    }
                    let pending = keys
                    keys.removeAll()
                    try await page.update(activity: activity, keys: pending, animate: animate, dragPosition: dragPosition)
                    if !Task.isCancelled && !reportedReady {
                        reportedReady = true
                        onReady?(true)
                    }
                }
            } catch {
                configured = false
                if !Task.isCancelled && reportedReady {
                    reportedReady = false
                    onReady?(false)
                }
            }
        }
    }
}
