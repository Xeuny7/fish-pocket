import SwiftUI

private enum PetActivity: Int, CaseIterable {
    case resting, playing, coding, searching

    var title: LocalizedStringKey {
        switch self {
        case .resting: "休闲"
        case .playing: "娱乐"
        case .coding: "敲代码"
        case .searching: "搜索"
        }
    }

    init(call: ToolCall) {
        if ImageGenCard.tools.contains(call.displayName) || call.displayName == "send_voice_message" {
            self = .playing
            return
        }
        switch StepKind(tool: call.name) {
        case .webSearch, .webFetch, .search: self = .searching
        case .commands, .code, .edit, .write: self = .coding
        default: self = .resting
        }
    }
}

private enum PetDefaults {
    static let enabled = "dsh.deskPet.enabled"
    static let size = "dsh.deskPet.size"
    static let x = "dsh.deskPet.x"
    static let y = "dsh.deskPet.y"
    static let sizes = 44.0...88.0
    static let initialSize = 56.0
}

/// Bottom-leading by default. Persist the fraction of available travel rather than pixels.
private struct PetBounds {
    let area: CGSize
    let side: CGFloat
    private let inset: CGFloat = 8
    private var dx: CGFloat { max(0, area.width - side - 2 * inset) }
    private var dy: CGFloat { max(0, area.height - side - 2 * inset) }

    var fits: Bool { area.width >= side + 2 * inset && area.height >= side + 2 * inset }

    func center(x: Double, y: Double, drag: CGSize) -> CGPoint {
        let minPoint = inset + side / 2
        return CGPoint(x: minPoint + min(dx, max(0, dx * CGFloat(x) + drag.width)),
                       y: minPoint + min(dy, max(0, dy * CGFloat(y) + drag.height)))
    }

    func fractions(at center: CGPoint, x: Double, y: Double) -> (Double, Double) {
        let minPoint = inset + side / 2
        return (dx > 0 ? Double((center.x - minPoint) / dx) : x,
                dy > 0 ? Double((center.y - minPoint) / dy) : y)
    }
}

struct DeskPetLayer: View {
    let model: SessionModel
    var reserveActivityCorner: Bool
    var reserveScrollCorner: Bool
    var keyboardUp: Bool
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PetDefaults.enabled) private var enabled = false

    var body: some View {
        if enabled && scenePhase == .active && !keyboardUp {
            ActiveDeskPet(model: model)
                .padding(.leading, reserveActivityCorner ? 60 : 0)
                .padding(.trailing, reserveScrollCorner ? 60 : 0)
        }
    }
}

private struct ActiveDeskPet: View {
    let model: SessionModel
    @AppStorage(PetDefaults.size) private var size = PetDefaults.initialSize
    @AppStorage(PetDefaults.x) private var x = 0.0
    @AppStorage(PetDefaults.y) private var y = 1.0
    @Environment(\.layoutDirection) private var layoutDirection
    @Namespace private var canvas
    @GestureState private var drag: CGSize = .zero

    private var activity: PetActivity {
        guard model.running else { return .resting }
        var calls: [AssistantBlock] = []
        if case .assistant(_, let blocks, _, nil)? = model.items.last(where: {
            if case .assistant = $0 { return true }
            return false
        }) { calls = blocks }
        return (calls + model.live).reduce(.resting) { state, block in
            guard case .tool(let call) = block, !call.finished else { return state }
            let activity = PetActivity(call: call)
            return activity.rawValue > state.rawValue ? activity : state
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let available = min(geometry.size.width, geometry.size.height) - 16
            let preferred = size.isFinite ? min(max(size, PetDefaults.sizes.lowerBound), PetDefaults.sizes.upperBound) : PetDefaults.initialSize
            let bounds = PetBounds(area: geometry.size, side: max(44, min(available, CGFloat(preferred))))
            if bounds.fits {
                let physicalX = layoutDirection == .rightToLeft ? 1 - x : x
                let current = activity
                PetSprite(activity: current)
                    .frame(width: bounds.side, height: bounds.side)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named(canvas))
                        .updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            let end = bounds.center(x: physicalX, y: y, drag: value.translation)
                            let (nextX, nextY) = bounds.fractions(at: end, x: physicalX, y: y)
                            x = layoutDirection == .rightToLeft ? 1 - nextX : nextX
                            y = nextY
                        })
                    .accessibilityLabel(Text("桌宠"))
                    .accessibilityValue(Text(current.title))
                    .position(bounds.center(x: physicalX, y: y, drag: drag))
            }
        }
        .coordinateSpace(name: canvas)
    }
}

struct DeskPetSettingsPage: View {
    @AppStorage(PetDefaults.enabled) private var enabled = false
    @AppStorage(PetDefaults.size) private var size = PetDefaults.initialSize
    @AppStorage(PetDefaults.x) private var x = 0.0
    @AppStorage(PetDefaults.y) private var y = 1.0

    var body: some View {
        List {
            Section {
                Toggle("显示桌宠", isOn: $enabled)
                VStack(alignment: .leading, spacing: 8) {
                    Text("大小")
                    Slider(value: $size, in: PetDefaults.sizes, step: 4) { Text("大小") }
                        .tint(Palette.link)
                }
                Button("重置位置") { x = 0; y = 1 }
            } footer: {
                Text("桌宠只在本机聊天画布内显示。拖动它可改变位置。")
            }
            .groupedRow()
            if enabled {
                Section {
                    HStack {
                        Spacer(minLength: 0)
                        PetSprite(activity: .resting)
                            .frame(width: CGFloat(size), height: CGFloat(size))
                            .accessibilityHidden(true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                }
                .groupedRow()
            }
        }
        .groupedList()
        .inkTint()
        .navigationTitle("桌宠")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum RabbitMotion: String {
    case blink, look, hop, code, search

    static let framesPerSecond = 24.0

    var frameCount: Int {
        switch self {
        case .blink: 9
        case .look: 39
        case .hop: 25
        case .code: 37
        case .search: 49
        }
    }

    var columns: Int { Int(ceil(sqrt(Double(frameCount)))) }
    var rows: Int { (frameCount + columns - 1) / columns }
    var duration: TimeInterval { Double(frameCount) / Self.framesPerSecond }

    func frame(at elapsed: TimeInterval, repeats: Bool) -> Int {
        let seconds = max(0, elapsed)
        let phase = repeats ? seconds.truncatingRemainder(dividingBy: duration) : min(seconds, duration)
        return min(frameCount - 1, Int(phase * Self.framesPerSecond))
    }
}

private struct PetSprite: View {
    let activity: PetActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var activeMotion: RabbitMotion? {
        switch activity {
        case .resting: nil
        case .playing: .hop
        case .coding: .code
        case .searching: .search
        }
    }

    var body: some View {
        Group {
            if reduceMotion || scenePhase != .active {
                StillRabbit(pose: activeMotion?.rawValue ?? "rest")
            } else {
                ZStack {
                    Group {
                        if let activeMotion {
                            RepeatingRabbit(motion: activeMotion)
                        } else {
                            IdleRabbit()
                        }
                    }
                    .id(activity)
                    .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.16), value: activity)
            }
        }
    }
}

private struct StillRabbit: View {
    var pose = "rest"

    var body: some View {
        Image("DeskRabbit-\(pose)")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
    }
}

private struct RepeatingRabbit: View {
    let motion: RabbitMotion
    @State private var start = Date()

    var body: some View {
        RabbitPlayback(motion: motion, start: start, repeats: true)
    }
}

/// Schedule occasional motion only while the sprite is visible.
private struct IdleRabbit: View {
    private struct Playback {
        let motion: RabbitMotion
        let start: Date
    }

    @State private var playback: Playback?

    var body: some View {
        Group {
            if let playback {
                RabbitPlayback(motion: playback.motion, start: playback.start, repeats: false)
            } else {
                StillRabbit()
            }
        }
        .task { await animate() }
    }

    @MainActor
    private func animate() async {
        guard !Task.isCancelled else { return }
        playback = nil
        let actions: [(RabbitMotion, ClosedRange<Double>)] = [
            (.blink, 2.2...3.5), (.look, 2.8...4.2), (.hop, 3.8...5.5)
        ]
        do {
            while !Task.isCancelled {
                for (motion, pause) in actions {
                    try await Task.sleep(for: .seconds(Double.random(in: pause)))
                    try Task.checkCancellation()
                    playback = Playback(motion: motion, start: Date())
                    try await Task.sleep(for: .seconds(motion.duration))
                    try Task.checkCancellation()
                    playback = nil
                }
            }
        } catch {
            // The view disappeared or another activity took its place.
        }
    }
}

private struct RabbitPlayback: View {
    let motion: RabbitMotion
    let start: Date
    let repeats: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / RabbitMotion.framesPerSecond)) { tick in
            let frame = motion.frame(at: tick.date.timeIntervalSince(start), repeats: repeats)
            Canvas { context, size in
                let side = min(size.width, size.height)
                let viewport = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                                      width: side, height: side)
                let column = frame % motion.columns
                let row = frame / motion.columns
                let atlas = CGRect(x: viewport.minX - CGFloat(column) * side,
                                   y: viewport.minY - CGFloat(row) * side,
                                   width: CGFloat(motion.columns) * side,
                                   height: CGFloat(motion.rows) * side)
                var clipped = context
                clipped.clip(to: Path(viewport))
                let spriteSheet = clipped.resolve(Image("DeskRabbit-motion-\(motion.rawValue)").interpolation(.high))
                clipped.draw(spriteSheet, in: atlas)
            }
        }
    }
}
