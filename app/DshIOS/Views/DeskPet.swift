import SwiftUI
import UniformTypeIdentifiers

enum PetActivity: Int, CaseIterable {
    case resting, thinking, playing, coding, searching, celebrating

    var workshopName: String {
        switch self {
        case .resting: "resting"
        case .thinking: "thinking"
        case .playing: "playing"
        case .coding: "coding"
        case .searching: "searching"
        case .celebrating: "celebrating"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .resting: "休闲"
        case .thinking: "思考"
        case .celebrating: "完成"
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

enum DeskPetStyle: Equatable {
    case rabbit, kuroCat, custom(StoredDeskPet)

    static let builtIn: [Self] = [.rabbit, .kuroCat]

    var id: String {
        switch self {
        case .rabbit: "rabbit"
        case .kuroCat: "kuroCat"
        case .custom(let pet): pet.id.uuidString
        }
    }

    @MainActor
    init(id: String, library: DeskPetLibrary) {
        if id == Self.kuroCat.id { self = .kuroCat }
        else if let pet = library.pets.first(where: { $0.id.uuidString == id }) { self = .custom(pet) }
        else { self = .rabbit }
    }

    func dimensions(for side: CGFloat) -> CGSize {
        guard case .custom(let pet) = self else { return CGSize(width: side, height: side) }
        let edge = CGFloat(max(pet.width, pet.height))
        return CGSize(width: side * CGFloat(pet.width) / edge, height: side * CGFloat(pet.height) / edge)
    }

    var title: Text {
        switch self {
        case .rabbit: Text("软耳兔")
        case .kuroCat: Text("KuroCat 小黑猫")
        case .custom(let pet): Text(verbatim: pet.name)
        }
    }

    @MainActor @ViewBuilder
    var thumbnail: some View {
        switch self {
        case .rabbit:
            Image("DeskRabbit-rest").resizable().scaledToFit()
        case .kuroCat:
            Image("DeskKuroCat-rest").resizable().scaledToFit()
        case .custom(let pet):
            CustomDeskPet(pet: pet, thumbnail: true).id(pet.id)
        }
    }

    @MainActor @ViewBuilder
    func sprite(activity: PetActivity, stroke: KuroCatStroke = KuroCatStroke(),
                dragPosition: CGPoint? = nil, supportsDrag: Bool = false) -> some View {
        switch self {
        case .rabbit:
            PetSprite(activity: activity).transition(.identity)
        case .kuroCat:
            if supportsDrag || DeskPetLibrary.shared.keyboard != nil {
                DraggableKuroCat(keyboard: DeskPetLibrary.shared.keyboard, activity: activity, stroke: stroke,
                                 dragPosition: dragPosition)
                    .transition(.identity)
            } else {
                KuroCatSprite(activity: activity, stroke: stroke).transition(.identity)
            }
        case .custom(let pet):
            if pet.workshop != nil, let skin = DeskPetLibrary.shared.skinJSON(for: pet) {
                KuroWorkshopScene(skin: skin, keyboard: DeskPetLibrary.shared.keyboard,
                                  activity: activity.workshopName, stroke: stroke, dragPosition: dragPosition)
                    .id(pet.id).transition(.identity)
            } else {
                CustomDeskPet(pet: pet).id(pet.id).transition(.identity)
            }
        }
    }
}

/// Keep the drag renderer loaded so the first movement can lift the cat immediately.
private struct DraggableKuroCat: View {
    let keyboard: WorkshopKeyboard?
    let activity: PetActivity
    let stroke: KuroCatStroke
    let dragPosition: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ready = false
    @State private var settling = false

    var body: some View {
        let dragging = dragPosition != nil
        let showScene = ready && (keyboard != nil || dragging || settling)
        ZStack {
            if !showScene {
                KuroCatSprite(activity: activity, stroke: stroke)
            }
            KuroWorkshopScene(skin: nil, keyboard: keyboard, activity: activity.workshopName, stroke: stroke,
                              animate: keyboard != nil || dragging || settling, dragPosition: dragPosition,
                              onReady: { ready = $0 })
                .opacity(showScene ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task(id: dragging) {
            if dragging {
                settling = !reduceMotion
            } else if settling {
                do { try await Task.sleep(for: .milliseconds(450)) }
                catch { return }
                settling = false
            }
        }
    }
}

enum PetDefaults {
    static let style = "dsh.deskPet.style"
    static let enabled = "dsh.deskPet.enabled"
    @MainActor
    static var kuroCatSelected: Bool {
        let selected = UserDefaults.standard.string(forKey: style)
        return selected == "kuroCat" || DeskPetLibrary.shared.pets.contains {
            $0.workshop != nil && $0.id.uuidString == selected
        }
    }

    @MainActor
    static var kuroCatEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabled) && kuroCatSelected
    }
    static let size = "dsh.deskPet.size"
    static let x = "dsh.deskPet.x"
    static let y = "dsh.deskPet.y"
    static let sizes = 44.0...176.0
    static let initialSize = 56.0
}

struct DeskPetObstacles: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func deskPetObstacle() -> some View {
        anchorPreference(key: DeskPetObstacles.self, value: .bounds) { [$0] }
    }
}

/// Persist a fraction of the travel, and project it onto the nearest clear spot.
private struct PetBounds {
    let area: CGSize
    let dimensions: CGSize
    let obstacles: [CGRect]
    let footprint: CGRect
    private let inset: CGFloat = 8
    private var left: CGFloat { inset + dimensions.width / 2 }
    private var top: CGFloat { inset + dimensions.height / 2 }
    private var dx: CGFloat { max(0, area.width - 2 * left) }
    private var dy: CGFloat { max(0, area.height - 2 * top) }

    var fits: Bool { area.width >= 2 * left && area.height >= 2 * top }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(left + dx, max(left, point.x)), y: min(top + dy, max(top, point.y)))
    }

    func center(x: Double, y: Double) -> CGPoint? {
        nearest(CGPoint(x: left + dx * CGFloat(x.isFinite ? x : 0),
                        y: top + dy * CGFloat(y.isFinite ? y : 1)))
    }

    func nearest(_ point: CGPoint) -> CGPoint? {
        let desired = clamp(point)
        let blocked = obstacles.filter { !$0.isEmpty }.map { obstacle in
            let gap: CGFloat = 2
            return CGRect(x: obstacle.minX - footprint.maxX * dimensions.width - gap,
                          y: obstacle.minY - footprint.maxY * dimensions.height - gap,
                          width: obstacle.width + footprint.width * dimensions.width + 2 * gap,
                          height: obstacle.height + footprint.height * dimensions.height + 2 * gap)
        }
        func isClear(_ point: CGPoint) -> Bool {
            !blocked.contains { point.x > $0.minX && point.x < $0.maxX && point.y > $0.minY && point.y < $0.maxY }
        }
        if isClear(desired) { return desired }
        let xs = [desired.x, left, left + dx] + blocked.flatMap { [$0.minX, $0.maxX] }
        let ys = [desired.y, top, top + dy] + blocked.flatMap { [$0.minY, $0.maxY] }
        func distance(_ point: CGPoint) -> CGFloat {
            let x = point.x - desired.x
            let y = point.y - desired.y
            return x * x + y * y
        }
        return xs.flatMap { x in ys.map { y in clamp(CGPoint(x: x, y: y)) } }
            .filter(isClear).min { distance($0) < distance($1) }
    }

    func fractions(at center: CGPoint, x: Double, y: Double) -> (Double, Double) {
        (dx > 0 ? Double((center.x - left) / dx) : x,
         dy > 0 ? Double((center.y - top) / dy) : y)
    }
}

private struct PetHitArea: Shape {
    let footprint: CGRect

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.midX + footprint.minX * rect.width,
                    y: rect.midY + footprint.minY * rect.height,
                    width: footprint.width * rect.width,
                    height: footprint.height * rect.height))
    }
}

struct DeskPetLayer: View {
    let model: SessionModel
    let obstacles: [Anchor<CGRect>]
    let covered: Bool
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PetDefaults.enabled) private var enabled = false
    @AppStorage(PetDefaults.style) private var style = "rabbit"

    var body: some View {
        if enabled && scenePhase == .active && !covered {
            ActiveDeskPet(model: model, obstacles: obstacles, style: DeskPetStyle(id: style, library: .shared))
        }
    }
}

private struct ActiveDeskPet: View {
    let model: SessionModel
    let obstacles: [Anchor<CGRect>]
    let style: DeskPetStyle
    @Environment(AppModel.self) private var app
    @Environment(\.botTimeline) private var bot
    @AppStorage(PetDefaults.size) private var size = PetDefaults.initialSize
    @AppStorage(PetDefaults.x) private var x = 0.0
    @AppStorage(PetDefaults.y) private var y = 1.0
    @Environment(\.layoutDirection) private var layoutDirection
    @Namespace private var canvas
    @GestureState private var drag: DragGesture.Value? = nil
    @State private var celebrating: Int?

    private var roomRelays: [RoomRelay] {
        guard bot?.room == true else { return [] }
        return model.items.compactMap { item in
            guard case .assistant(let turn, let blocks, _, _) = item,
                  let relay = RoomRelay(blocks: blocks) else { return nil }
            if let end = model.forkBoundary(turn: turn), end <= model.deskPetLiveAfter {
                // A round can still be speaking when its enclosing session is reopened.
                guard app.botTeam.relayRows[relay.call.id]?["active"].bool == true ||
                      app.botTeam.round(relay.call.id) != nil else { return nil }
            }
            return relay
        }
    }

    private var pendingRoomRelays: [RoomRelay] {
        roomRelays.filter { relay in
            guard relay.range != nil, !relay.call.isError else { return false }
            let book = app.botTeam.relayRows[relay.call.id]
            return book == nil || book?["active"].bool == true
        }
    }

    private var working: Bool {
        model.deskPetWorking || !pendingRoomRelays.isEmpty || roomRelays.contains { relay in
            !relay.settled && app.botTeam.round(relay.call.id) != nil
        }
    }

    private var completion: Int? {
        guard !working, let seq = model.deskPetCompletion else { return nil }
        guard bot?.room == true else { return seq }
        guard let last = roomRelays.last, last.settled, !last.call.isError, !last.broken else { return nil }
        let replies = app.botTeam.replies(of: last)
        let incomplete = ["failed", "stopped", "missed", "cut"]
        guard replies.contains(where: { $0["kind"].isNull }),
              !replies.contains(where: { incomplete.contains($0["kind"].string ?? "") }) else { return nil }
        return seq
    }

    private var activity: PetActivity {
        guard working else { return celebrating == completion && celebrating != nil ? .celebrating : .resting }
        var calls: [AssistantBlock] = []
        if case .assistant(_, let blocks, _, nil)? = model.items.last(where: {
            if case .assistant = $0 { return true }
            return false
        }) { calls = blocks }
        return (calls + model.live).reduce(.thinking) { state, block in
            guard case .tool(let call) = block, !call.finished else { return state }
            let activity = PetActivity(call: call)
            return activity.rawValue > state.rawValue ? activity : state
        }
    }

    private func placement(in geometry: GeometryProxy, x: Double) -> (PetBounds, CGPoint)? {
        let unit = style.dimensions(for: 1)
        let available = min((geometry.size.width - 16) / unit.width, (geometry.size.height - 16) / unit.height)
        let preferred = size.isFinite ? min(max(size, PetDefaults.sizes.lowerBound), PetDefaults.sizes.upperBound) : PetDefaults.initialSize
        let side = min(available, CGFloat(preferred))
        let minimumSide: CGFloat = 28
        guard side >= minimumSide else { return nil }
        let blocked = obstacles.map { geometry[$0] }

        // The padded atlas is larger than its visible cat and keyboard across all poses.
        let footprint = style == .kuroCat
            ? CGRect(x: -0.34, y: -0.29, width: 0.68, height: 0.70)
            : CGRect(x: -0.5, y: -0.5, width: 1, height: 1)
        let candidates = [side] + Array(stride(from: (side / 4).rounded(.down) * 4, through: minimumSide, by: -4))
        for candidate in candidates {
            let bounds = PetBounds(area: geometry.size, dimensions: style.dimensions(for: candidate), obstacles: blocked, footprint: footprint)
            if bounds.fits, let center = bounds.center(x: x, y: y) {
                return (bounds, center)
            }
        }
        return nil
    }

    private func dragTarget(_ value: DragGesture.Value, origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height)
    }

    var body: some View {
        GeometryReader { geometry in
            let physicalX = layoutDirection == .rightToLeft ? 1 - x : x
            if let (bounds, origin) = placement(in: geometry, x: physicalX) {
                let current = activity
                let center = drag.flatMap { bounds.nearest(dragTarget($0, origin: origin)) } ?? origin
                let dragPosition = drag.map { value in
                    CGPoint(x: value.translation.width / bounds.dimensions.width,
                            y: value.translation.height / bounds.dimensions.height)
                }
                style.sprite(activity: current, stroke: model.composer.kuroCatStroke,
                             dragPosition: dragPosition, supportsDrag: true)
                    .frame(width: bounds.dimensions.width, height: bounds.dimensions.height)
                    .contentShape(PetHitArea(footprint: bounds.footprint))
                    .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named(canvas))
                        .updating($drag) { value, state, _ in state = value }
                        .onEnded { value in
                            guard let end = bounds.nearest(dragTarget(value, origin: origin)) else { return }
                            let (nextX, nextY) = bounds.fractions(at: end, x: physicalX, y: y)
                            x = layoutDirection == .rightToLeft ? 1 - nextX : nextX
                            y = nextY
                        })
                    .accessibilityLabel(Text("桌宠"))
                    .accessibilityValue(Text(current.title))
                    .position(center)
            }
        }
        .coordinateSpace(name: canvas)
        .task(id: pendingRoomRelays.map { $0.call.id }) {
            while !Task.isCancelled {
                let pending = pendingRoomRelays
                guard !pending.isEmpty else { return }
                for relay in pending {
                    guard !Task.isCancelled else { return }
                    await app.botTeam.loadRows(of: relay, roomId: model.sessionId)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .task(id: completion) {
            celebrating = nil
            guard !Task.isCancelled, let seq = completion, model.consumeDeskPetCompletion(seq) else { return }
            celebrating = seq
            do {
                try await Task.sleep(for: .seconds(RabbitMotion.hop.duration))
                celebrating = nil
            } catch { }
        }
    }
}

struct DeskPetSettingsPage: View {
    private let onCreate: (() -> Void)?
    @Environment(AppModel.self) private var app

    init(onCreate: (() -> Void)? = nil) {
        self.onCreate = onCreate
    }
    @State private var choosingFile = false
    @State private var importing = false
    @AppStorage(PetDefaults.enabled) private var enabled = false
    @AppStorage(PetDefaults.style) private var style = "rabbit"
    @AppStorage(PetDefaults.size) private var size = PetDefaults.initialSize
    @AppStorage(PetDefaults.x) private var x = 0.0
    @AppStorage(PetDefaults.y) private var y = 1.0

    var body: some View {
        List {
            Section {
                Toggle("显示桌宠", isOn: $enabled)
            }
            .groupedRow()
            Section("桌宠外观") {
                DeskPetGallery(style: $style, enabled: $enabled)
            }
            .groupedRow()
            Section {
                NavigationLink {
                    KuroWorkshopView()
                } label: {
                    Label("KuroCat 工坊", systemImage: "paintpalette")
                }
                Button { choosingFile = true } label: {
                    Label("导入宠物", systemImage: "square.and.arrow.down")
                }
                .disabled(importing)
                Button {
                    onCreate?()
                    app.newSessionRequest = NewSessionRequest(draft: DeskPetCreation.draft, createsDeskPet: true)
                } label: {
                    Label("用 AI 创建宠物", systemImage: "sparkles")
                }
                .disabled(app.workspaces.isEmpty)
            }
            .groupedRow()
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("大小")
                    Slider(value: $size, in: PetDefaults.sizes, step: 4) { Text("大小") }
                        .tint(Palette.link)
                }
                Button("重置位置") { x = 0; y = 1 }
            } footer: {
                Text("桌宠显示在本机会话和 Bot 聊天中。拖动它可改变位置。")
            }
            .groupedRow()
            if enabled {
                Section {
                    HStack {
                        Spacer(minLength: 0)
                        DeskPetStyle(id: style, library: .shared).sprite(activity: .resting)
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
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: DeskPetLibrary.importTypes) { result in
            importing = true
            Task {
                defer { importing = false }
                do {
                    try await DeskPetLibrary.shared.importFile(result.get())
                    app.showToast(String(localized: "宠物已加入桌宠外观"))
                } catch {
                    if (error as NSError).code != NSUserCancelledError {
                        app.showToast(error.localizedDescription, tone: .warning)
                    }
                }
            }
        }
    }
}

private struct CustomDeskPet: View {
    let pet: StoredDeskPet
    var thumbnail = false
    @State private var image: UIImage?

    var body: some View {
        Color.clear.overlay {
            if let image { Picture(image: image, contentMode: .fit) }
        }
        .task(id: pet.id) {
            let url = DeskPetLibrary.shared.imageURL(for: pet)
            let preview = thumbnail
            let picture = await Task.detached(priority: .userInitiated) {
                DeskPetLibrary.picture(at: url, thumbnail: preview)
            }.value
            if !Task.isCancelled { image = picture }
        }
    }
}

private enum RabbitMotion: String {
    case blink, look, hop, code, search

    var frameCount: Int {
        switch self {
        case .blink: 9
        case .look: 39
        case .hop: 25
        case .code: 37
        case .search: 49
        }
    }

    var duration: TimeInterval { Double(frameCount) / PetAtlas.framesPerSecond }
}

private struct PetSprite: View {
    let activity: PetActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var activeMotion: RabbitMotion? {
        switch activity {
        case .resting: nil
        case .thinking: .look
        case .playing, .celebrating: .hop
        case .coding: .code
        case .searching: .search
        }
    }

    var body: some View {
        Group {
            if reduceMotion || scenePhase != .active {
                StillRabbit(pose: activity == .thinking ? "right" : (activeMotion?.rawValue ?? "rest"))
            } else {
                ZStack {
                    Group {
                        if activity == .celebrating {
                            CelebratingRabbit()
                        } else if let activeMotion {
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

private struct CelebratingRabbit: View {
    @State private var start = Date()

    var body: some View {
        RabbitPlayback(motion: .hop, start: start, repeats: false)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.link)
                    .accessibilityHidden(true)
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
        PetAtlas(asset: "DeskRabbit-motion-\(motion.rawValue)", frameCount: motion.frameCount,
                 start: start, repeats: repeats)
    }
}

private struct PetAtlas: View {
    static let framesPerSecond = 24.0
    let asset: String
    let frameCount: Int
    let start: Date
    let repeats: Bool
    var key: KuroCatKey? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / Self.framesPerSecond)) { tick in
            let elapsed = max(0, tick.date.timeIntervalSince(start)) * Self.framesPerSecond
            let phase = repeats ? elapsed.truncatingRemainder(dividingBy: Double(frameCount)) : elapsed
            let frame = Int(min(Double(frameCount - 1), phase))
            Canvas { context, size in
                let side = min(size.width, size.height)
                let viewport = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                                      width: side, height: side)
                let columns = key.map { KuroCatKey.rows[$0.row].count } ?? Int(ceil(sqrt(Double(frameCount))))
                let rows = key == nil ? (frameCount + columns - 1) / columns : frameCount
                let column = key?.slot ?? frame % columns
                let row = key == nil ? frame / columns : frame
                let atlas = CGRect(x: viewport.minX - CGFloat(column) * side,
                                   y: viewport.minY - CGFloat(row) * side,
                                   width: CGFloat(columns) * side,
                                   height: CGFloat(rows) * side)
                var clipped = context
                clipped.clip(to: Path(viewport))
                let spriteSheet = clipped.resolve(Image(asset).interpolation(.high))
                clipped.draw(spriteSheet, in: atlas)
            }
        }
    }
}

struct DraftDeskPet: View {
    let stroke: KuroCatStroke
    @AppStorage(PetDefaults.enabled) private var enabled = false
    @AppStorage(PetDefaults.style) private var style = "rabbit"
    @AppStorage(PetDefaults.size) private var size = PetDefaults.initialSize

    var body: some View {
        if enabled {
            DeskPetStyle(id: style, library: .shared).sprite(activity: .resting, stroke: stroke)
                .frame(width: CGFloat(min(size, 72)), height: CGFloat(min(size, 72)))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 12)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

private enum KuroMotion: String {
    case idle, left, right, think, search, hop

    var frameCount: Int {
        switch self {
        case .left, .right: 10
        case .idle, .think, .search: 36
        case .hop: 25
        }
    }
}

private struct KuroCatSprite: View {
    let activity: PetActivity
    let stroke: KuroCatStroke
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var tap: KuroCatKey?
    @State private var keyLabel: String?
    @State private var tapStart = Date()
    @State private var pendingKeys: [KuroCatKey] = []

    var body: some View {
        Group {
            if reduceMotion || scenePhase != .active {
                Image("DeskKuroCat-rest").resizable().interpolation(.high).scaledToFit()
            } else if let tap {
                PetAtlas(asset: "DeskKuroCat-keys-\(tap.row)", frameCount: KuroCatKey.frames,
                         start: tapStart, repeats: false, key: tap)
            } else {
                KuroCatActivity(activity: activity).id(activity)
            }
        }
        .overlay {
            GeometryReader { geometry in
                if scenePhase == .active, let keyLabel {
                    let side = min(geometry.size.width, geometry.size.height)
                    Text(verbatim: keyLabel)
                        .font(.system(size: min(10, side * 0.22), weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(Palette.ink)
                        .frame(width: side * 0.34, height: side * 0.24)
                        .background(Palette.field, in: RoundedRectangle(cornerRadius: 4))
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.stroke) }
                        .position(x: geometry.size.width / 2 + side * 0.17, y: geometry.size.height / 2 - side * 0.17)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
        .onChange(of: stroke.revision) { previous, revision in
            guard scenePhase == .active else { return }
            pendingKeys.append(contentsOf: stroke.keys.suffix(revision &- previous))
            if pendingKeys.count > 64 { pendingKeys.removeFirst(pendingKeys.count - 64) }
            if tap == nil || Date().timeIntervalSince(tapStart) >= 0.085 { playNextKey() }
        }
        .task(id: tapStart) {
            guard keyLabel != nil else { return }
            do {
                try await Task.sleep(for: .milliseconds(85))
                try Task.checkCancellation()
                if !pendingKeys.isEmpty {
                    playNextKey()
                    return
                }
                try await Task.sleep(for: .milliseconds(165))
                try Task.checkCancellation()
                tap = nil
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                keyLabel = nil
            } catch { }
        }
    }

    private func playNextKey() {
        guard !pendingKeys.isEmpty else { return }
        let key = pendingKeys.removeFirst()
        tapStart = Date()
        tap = key
        keyLabel = key.label
    }
}

private struct KuroCatActivity: View {
    let activity: PetActivity
    @State private var start = Date()

    private var motion: KuroMotion {
        switch activity {
        case .resting: .idle
        case .thinking: .think
        case .coding: .left
        case .searching: .search
        case .playing, .celebrating: .hop
        }
    }

    var body: some View {
        PetAtlas(asset: "DeskKuroCat-\(motion.rawValue)", frameCount: motion.frameCount,
                 start: start, repeats: activity != .celebrating)
            .overlay(alignment: .topTrailing) {
                if activity == .celebrating {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.link)
                        .accessibilityHidden(true)
                }
            }
    }
}
