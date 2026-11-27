import UIKit

/// Watches only new local conversations explicitly opened from the pet picker.
@MainActor
final class DeskPetCreation {
    private struct Request {
        let id = UUID()
        var lastTurn: Int?
        var following = false
        var saving = false
    }

    private var requests: [String: Request] = [:]

    func register(_ sessionId: String) {
        requests[sessionId] = Request()
    }

    func follow(_ session: SessionModel, in app: AppModel) {
        let sessionId = session.sessionId
        guard requests[sessionId]?.following == false,
              requests[sessionId]?.saving == false else { return }
        requests[sessionId]?.following = true
        _ = app.localSessions.acquire(sessionId) { session }
    }

    func inspect(_ session: SessionModel, in app: AppModel) {
        if session.deskPetWorking { follow(session, in: app) }
        let sessionId = session.sessionId
        guard var request = requests[sessionId], !request.saving else { return }
        guard
              let turn = session.turnInfo.filter({ $0.value.closedKind != nil }).keys.max(),
              request.lastTurn.map({ turn > $0 }) ?? true else { return }
        request.lastTurn = turn
        guard session.turnInfo[turn]?.closedKind == "completed" else {
            requests[sessionId] = request
            stopFollowing(sessionId, in: app)
            return
        }
        request.saving = true
        requests[sessionId] = request
        let blocks = session.items.flatMap { item -> [AssistantBlock] in
            guard case .assistant(let number, let blocks, _, _) = item, number == turn else { return [] }
            return blocks
        }
        Task { [weak app] in
            guard let app else { return }
            let saved = await collect(blocks, from: session, id: request.id)
            stopFollowing(sessionId, in: app)
            if saved {
                requests[sessionId] = nil
                app.showToast(String(localized: "宠物已加入桌宠外观"))
            } else {
                requests[sessionId]?.saving = false
                app.showToast(String(localized: "未收到可用的宠物素材。可在此会话重试。"), tone: .warning)
                inspect(session, in: app)
            }
        }
    }

    private func stopFollowing(_ sessionId: String, in app: AppModel) {
        guard requests[sessionId]?.following == true else { return }
        requests[sessionId]?.following = false
        app.localSessions.release(sessionId)
    }

    private func collect(_ blocks: [AssistantBlock], from session: SessionModel, id: UUID) async -> Bool {
        for block in blocks.reversed() {
            let images: [Attachment]
            switch block {
            case .image(_, let image): images = [image]
            case .tool(let call) where !call.isError && ImageGenCard.tools.contains(call.displayName):
                images = call.resultImages
            default: continue
            }
            for image in images where image.ref != nil && (image.bytes ?? 0) <= 16 << 20 {
                guard let data = await session.loadAttachment(image) else { continue }
                if save(data, name: image.name.map { ($0 as NSString).deletingPathExtension }, id: id) { return true }
            }
        }
        for block in blocks.reversed() {
            guard case .text(_, let text) = block, let result = DeskPetPixels.decode(text) else { continue }
            if save(result.image, name: result.name, id: id) { return true }
        }
        return false
    }

    private func save(_ data: Data, name: String?, id: UUID) -> Bool {
        do {
            try DeskPetLibrary.shared.add(data, name: name ?? String(localized: "AI 桌宠"), id: id)
            return true
        } catch {
            return false
        }
    }

    static let draft = String(localized: "请为我创建一只原创桌宠。优先使用可用的生图工具，生成一张主体居中、背景透明的图片。如果没有生图工具，请在最终回复中用一个 dsh-pet 代码块提供像素画 JSON：name 为宠物名称，palette 为单个 ASCII 字符到 #RRGGBB 颜色的字典，rows 为等宽字符串数组。用 . 表示透明，宽和高各为 8 至 32 像素。")
}

/// Plain data fallback for models without an image tool.
private struct DeskPetPixels: Decodable {
    let name: String
    let palette: [String: String]
    let rows: [String]

    @MainActor
    static func decode(_ text: String) -> (name: String, image: Data)? {
        guard let start = text.range(of: "```dsh-pet\n"),
              let end = text.range(of: "```", range: start.upperBound..<text.endIndex),
              let data = text[start.upperBound..<end.lowerBound].data(using: .utf8), data.count <= 8192,
              let pet = try? JSONDecoder().decode(Self.self, from: data),
              (8...32).contains(pet.rows.count), let width = pet.rows.first?.utf8.count,
              (8...32).contains(width), pet.rows.allSatisfy({ $0.utf8.count == width }),
              (1...32).contains(pet.palette.count) else { return nil }
        var colors: [UInt8: UIColor] = [:]
        for (key, color) in pet.palette {
            guard key.utf8.count == 1, let byte = key.utf8.first, (33...126).contains(byte), byte != 46,
                  color.utf8.count == 7, color.first == "#", let rgb = UInt32(color.dropFirst(), radix: 16),
                  color.dropFirst().utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
            else { return nil }
            colors[byte] = UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                                   blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
        let pixels = pet.rows.map { Array($0.utf8) }
        guard pixels.joined().allSatisfy({ $0 == 46 || colors[$0] != nil }),
              pixels.joined().contains(where: { $0 != 46 }) else { return nil }
        let unit: CGFloat = 16
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width) * unit, height: CGFloat(pixels.count) * unit), format: format)
        let image = renderer.pngData { context in
            for (y, row) in pixels.enumerated() {
                for (x, pixel) in row.enumerated() {
                    guard let color = colors[pixel] else { continue }
                    context.cgContext.setFillColor(color.cgColor)
                    context.fill(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit))
                }
            }
        }
        return (pet.name, image)
    }
}
