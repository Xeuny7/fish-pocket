import SwiftUI

struct KuroWorkshopView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(PetDefaults.style) private var style = "rabbit"
    @AppStorage(PetDefaults.enabled) private var enabled = false
    @State private var kind: KuroWorkshop.Kind = .cats
    @State private var entries: [WorkshopEntry] = []
    @State private var loading = true
    @State private var failed = false
    @State private var reload = 0
    @State private var installing: String?
    @State private var pending: WorkshopEntry?
    private var library: DeskPetLibrary { .shared }

    var body: some View {
        List {
            Section {
                Picker("KuroCat 工坊", selection: $kind) {
                    Text("猫咪外观").tag(KuroWorkshop.Kind.cats)
                    Text("键盘主题").tag(KuroWorkshop.Kind.keyboards)
                }
                .pickerStyle(.segmented)
                .disabled(installing != nil)
                Link(destination: WorkshopCredit.site) {
                    Label("打开工坊原站", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("素材从 KuroCat 工坊下载，作者信息会保留在本机。工坊作品仅供个人使用。")
            }
            .groupedRow()

            if kind == .keyboards, let theme = library.keyboard {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: theme.credit.title).font(.headline)
                        WorkshopAuthor(credit: theme.credit)
                    }
                    Button("恢复默认键盘") {
                        do { try library.selectKeyboard(nil) }
                        catch { app.showToast(error.localizedDescription, tone: .warning) }
                    }
                    .disabled(installing != nil)
                }
                .groupedRow()
            }

            Section {
                if loading {
                    ProgressView()
                } else if failed {
                    Button("重试") { reload += 1 }
                } else if entries.isEmpty {
                    Text("暂无工坊作品").foregroundStyle(Palette.secondary)
                } else {
                    ForEach(entries) { entry in
                        Button { pending = entry } label: { row(entry) }
                            .buttonStyle(.plain)
                            .disabled(installing != nil)
                    }
                }
            }
            .groupedRow()
        }
        .groupedList()
        .inkTint()
        .navigationTitle("KuroCat 工坊")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(kind.rawValue):\(reload)") { await load(kind) }
        .confirmationDialog("下载并使用", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { entry in
            Button("下载并使用") {
                let selectedKind = kind
                installing = entry.slug
                Task { await install(entry, kind: selectedKind) }
            }
        } message: { entry in
            Text(verbatim: entry.title)
        }
    }

    private func row(_ entry: WorkshopEntry) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(Array(entry.swatches.enumerated()), id: \.offset) { _, value in
                    if WorkshopKeyboard.isColor(value), let rgb = UInt32(value.dropFirst(), radix: 16) {
                        Capsule().fill(Color(red: Double((rgb >> 16) & 255) / 255,
                                             green: Double((rgb >> 8) & 255) / 255,
                                             blue: Double(rgb & 255) / 255))
                            .frame(width: 7, height: 30)
                    }
                }
            }
            .frame(width: 38)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.title).font(.headline).foregroundStyle(Palette.ink)
                Text(verbatim: entry.author).font(.subheadline).foregroundStyle(Palette.secondary)
                if let description = entry.description, !description.isEmpty {
                    Text(verbatim: description).font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 4)
            if installing == entry.slug { ProgressView() }
            else if selected(entry) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.link) }
            else { Image(systemName: "arrow.down.circle").foregroundStyle(Palette.link) }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected(entry) ? .isSelected : [])
    }

    private func selected(_ entry: WorkshopEntry) -> Bool {
        if kind == .keyboards { return library.keyboard?.credit.slug == entry.slug }
        return library.pets.contains { $0.workshop?.slug == entry.slug && $0.id.uuidString == style }
    }

    private func load(_ requested: KuroWorkshop.Kind) async {
        loading = true
        failed = false
        entries = []
        do {
            let next = try await KuroWorkshop.catalog(requested)
            guard !Task.isCancelled, requested == kind else { return }
            entries = next
            loading = false
        } catch {
            guard !Task.isCancelled, requested == kind else { return }
            failed = true
            loading = false
        }
    }

    private func install(_ entry: WorkshopEntry, kind: KuroWorkshop.Kind) async {
        defer { installing = nil }
        do {
            if kind == .cats {
                let pet: StoredDeskPet
                if let existing = library.pets.first(where: { $0.workshop?.slug == entry.slug }) {
                    pet = existing
                } else {
                    let data = try await KuroWorkshop.asset(entry, kind: kind)
                    pet = try await library.installSkin(data, credit: entry.credit)
                }
                style = pet.id.uuidString
            } else {
                let data = try await KuroWorkshop.asset(entry, kind: kind)
                let theme = try WorkshopKeyboard(credit: entry.credit, data: data)
                try library.selectKeyboard(theme)
                if !PetDefaults.kuroCatSelected { style = "kuroCat" }
            }
            enabled = true
        } catch {
            app.showToast(error.localizedDescription, tone: .warning)
        }
    }
}

struct WorkshopAuthor: View {
    let credit: WorkshopCredit

    var body: some View {
        HStack(spacing: 8) {
            if let url = credit.authorURL { Link(destination: url) { Text(verbatim: credit.author) } }
            else { Text(verbatim: credit.author) }
            Link("KuroCat 工坊", destination: WorkshopCredit.site)
        }
        .font(.caption)
        .foregroundStyle(Palette.secondary)
    }
}
