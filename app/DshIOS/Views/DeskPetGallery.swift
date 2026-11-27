import SwiftUI
import UniformTypeIdentifiers

struct DeskPetGallery: View {
    @Binding var style: String
    @Binding var enabled: Bool
    @Environment(AppModel.self) private var app
    @State private var renameTarget: StoredDeskPet?
    @State private var deleteTarget: StoredDeskPet?
    @State private var name = ""
    @State private var exporting = false
    @State private var document: PetExport?
    @State private var filename = ""
    private var library: DeskPetLibrary { .shared }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 12) {
            ForEach(DeskPetStyle.builtIn, id: \.id) { option in tile(option) }
            ForEach(library.pets) { pet in
                tile(.custom(pet))
                    .contextMenu { actions(pet) }
                    .accessibilityAction(named: Text("重命名")) { beginRename(pet) }
                    .accessibilityAction(named: Text("删除")) { deleteTarget = pet }
            }
        }
        .padding(.vertical, 8)
        .alert("重命名", isPresented: presented($renameTarget), presenting: renameTarget) { pet in
            TextField("名称", text: $name)
            Button("取消", role: .cancel) {}
            Button("保存") {
                do { try library.rename(pet, to: name) }
                catch { report(error) }
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog("删除宠物？", isPresented: presented($deleteTarget), titleVisibility: .visible, presenting: deleteTarget) { pet in
            Button("删除", role: .destructive) {
                do {
                    try library.remove(pet)
                    if style == pet.id.uuidString { style = "rabbit" }
                } catch { report(error) }
            }
        } message: { pet in
            Text(verbatim: pet.name)
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: document?.type ?? .png, defaultFilename: filename) { result in
            if case .failure(let error) = result { report(error) }
            document = nil
        }
    }

    private func tile(_ option: DeskPetStyle) -> some View {
        let selected = option.id == style
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                style = option.id
                enabled = true
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        option.thumbnail
                            .frame(height: 66)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.link)
                                .accessibilityHidden(true)
                        }
                    }
                    option.title.font(.subheadline.weight(selected ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Palette.ink)
                .background(selected ? Palette.bubble : Palette.field, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Palette.link : Palette.stroke) }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            if case .custom(let pet) = option {
                HStack(spacing: 4) {
                    if let credit = pet.workshop { WorkshopAuthor(credit: credit) }
                    Spacer(minLength: 0)
                    Menu { actions(pet) } label: {
                        Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(Text("管理宠物"))
                }
            }
        }
    }

    @ViewBuilder private func actions(_ pet: StoredDeskPet) -> some View {
        Button { beginRename(pet) } label: { Label("重命名", systemImage: "pencil") }
        if pet.workshop == nil {
            Button {
                do {
                    let (data, type) = try library.export(pet)
                    document = PetExport(data: data, type: type)
                    filename = pet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
                    exporting = true
                } catch { report(error) }
            } label: { Label("导出宠物", systemImage: "square.and.arrow.up") }
        }
        Button(role: .destructive) { deleteTarget = pet } label: { Label("删除", systemImage: "trash") }
    }

    private func beginRename(_ pet: StoredDeskPet) { name = pet.name; renameTarget = pet }

    private func presented(_ target: Binding<StoredDeskPet?>) -> Binding<Bool> {
        Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })
    }

    private func report(_ error: Error) {
        if (error as NSError).code != NSUserCancelledError { app.showToast(error.localizedDescription, tone: .warning) }
    }
}

private struct PetExport: FileDocument {
    static let readableContentTypes: [UTType] = [.png, .jpeg, .gif, .webP]
    let data: Data
    let type: UTType

    init(data: Data, type: UTType) { self.data = data; self.type = type }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
        type = configuration.contentType
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DeskPetPreview: View {
    let pet: StoredDeskPet
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PetDefaults.style) private var style = "rabbit"
    @AppStorage(PetDefaults.enabled) private var enabled = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DeskPetStyle.custom(pet).sprite(activity: .resting)
                    .frame(maxWidth: 240).frame(height: 200)
                    .accessibilityHidden(true)
                Text(verbatim: pet.name).font(.headline)
                Button("立即使用") {
                    guard DeskPetLibrary.shared.pets.contains(where: { $0.id == pet.id }) else { dismiss(); return }
                    style = pet.id.uuidString
                    enabled = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .featurePage()
        .navigationTitle("预览宠物")
        .navigationBarTitleDisplayMode(.inline)
    }
}
