import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

struct StoredDeskPet: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let width: Int
    let height: Int
    var workshop: WorkshopCredit? = nil
}

@MainActor
@Observable
final class DeskPetLibrary {
    static let shared = DeskPetLibrary()
    static let importTypes: [UTType] = [.png, .jpeg, .gif, .webP]
    private nonisolated static let maxBytes = 16 << 20
    private(set) var pets: [StoredDeskPet] = []
    private(set) var keyboard: WorkshopKeyboard?
    var preview: StoredDeskPet?
    private let root = URL.applicationSupportDirectory.appending(path: "DeskPets", directoryHint: .isDirectory)

    private init() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        pets = folders.compactMap { folder in
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  let data = try? Data(contentsOf: folder.appending(path: "pet.json")),
                  let pet = try? JSONDecoder().decode(StoredDeskPet.self, from: data),
                  pet.id == id, pet.width > 0, pet.height > 0,
                  FileManager.default.fileExists(atPath: imageURL(for: pet).path) else { return nil }
            return pet
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let data = try? Data(contentsOf: keyboardURL) {
            keyboard = try? JSONDecoder().decode(WorkshopKeyboard.self, from: data)
        }
    }

    private var keyboardURL: URL { root.appending(path: "keyboard.json") }

    func selectKeyboard(_ theme: WorkshopKeyboard?) throws {
        if let theme {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(theme).write(to: keyboardURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: keyboardURL.path) {
            try FileManager.default.removeItem(at: keyboardURL)
        }
        keyboard = theme
    }

    func installSkin(_ data: Data, credit: WorkshopCredit) async throws -> StoredDeskPet {
        if let existing = pets.first(where: { $0.workshop?.slug == credit.slug }) { return existing }
        guard let skin = String(data: data, encoding: .utf8) else { throw KuroWorkshop.AssetError.invalid }
        let thumbnail = try await KuroWorkshopPage().thumbnail(skin: skin)
        try Task.checkCancellation()
        if let existing = pets.first(where: { $0.workshop?.slug == credit.slug }) { return existing }
        return try add(thumbnail, name: credit.title, workshop: credit, skin: data)
    }

    func imageURL(for pet: StoredDeskPet) -> URL {
        folder(for: pet.id).appending(path: "image")
    }

    func skinJSON(for pet: StoredDeskPet) -> String? {
        try? String(contentsOf: folder(for: pet.id).appending(path: "skin.json"), encoding: .utf8)
    }

    private func folder(for id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    func rename(_ pet: StoredDeskPet, to name: String) throws {
        guard let index = pets.firstIndex(where: { $0.id == pet.id }) else { return }
        var updated = pets[index]
        updated.name = Self.displayName(name)
        try JSONEncoder().encode(updated).write(to: folder(for: pet.id).appending(path: "pet.json"), options: .atomic)
        pets[index] = updated
        sortPets()
    }

    func remove(_ pet: StoredDeskPet) throws {
        guard pets.contains(where: { $0.id == pet.id }) else { return }
        try FileManager.default.removeItem(at: folder(for: pet.id))
        pets.removeAll { $0.id == pet.id }
        if UserDefaults.standard.string(forKey: PetDefaults.style) == pet.id.uuidString {
            UserDefaults.standard.set("rabbit", forKey: PetDefaults.style)
        }
    }

    func export(_ pet: StoredDeskPet) throws -> (Data, UTType) {
        guard pet.workshop == nil else { throw CocoaError(.fileReadNoPermission) }
        let data = try Data(contentsOf: imageURL(for: pet))
        guard let source = Self.source(data), let id = CGImageSourceGetType(source) as String?,
              let type = UTType(id) else { throw InvalidPetImage() }
        return (data, type)
    }

    func importFile(_ url: URL) async throws {
        let data = try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            return try file.read(upToCount: Self.maxBytes + 1) ?? Data()
        }.value
        try add(data, name: url.deletingPathExtension().lastPathComponent)
    }

    @discardableResult
    func add(_ data: Data, name: String, id: UUID = UUID(), workshop: WorkshopCredit? = nil, skin: Data? = nil) throws -> StoredDeskPet {
        if let existing = pets.first(where: { $0.id == id }) { return existing }
        guard let image = Self.source(data),
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height),
              CGImageSourceCreateThumbnailAtIndex(image, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
              ] as CFDictionary) != nil else { throw InvalidPetImage() }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        let pet = StoredDeskPet(id: id, name: Self.displayName(name),
                                width: rotated ? height : width, height: rotated ? width : height, workshop: workshop)
        let fm = FileManager.default
        let staging = root.appending(path: ".\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try data.write(to: staging.appending(path: "image"))
        if let skin { try skin.write(to: staging.appending(path: "skin.json")) }
        try JSONEncoder().encode(pet).write(to: staging.appending(path: "pet.json"))
        try fm.moveItem(at: staging, to: folder(for: id))
        pets.append(pet)
        sortPets()
        return pet
    }

    private func sortPets() {
        pets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func displayName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "桌宠") : String(trimmed.prefix(80))
    }

    private nonisolated static func source(_ data: Data) -> CGImageSource? {
        guard !data.isEmpty, data.count <= maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              let contentType = UTType(type), [.png, .jpeg, .gif, .webP].contains(contentType) else { return nil }
        return source
    }

    nonisolated static func picture(at url: URL, thumbnail: Bool = false) -> UIImage? {
        guard let data = try? Data(contentsOf: url), let source = source(data) else { return nil }
        if !thumbnail, let animated = AnimatedPicture.decode(data, longEdge: 600) { return animated }
        guard let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnail ? 160 : 600,
        ] as CFDictionary) else { return nil }
        return UIImage(cgImage: frame)
    }
}

private struct InvalidPetImage: LocalizedError {
    var errorDescription: String? { String(localized: "请选择 16 MB 以内、边长不超过 4096 像素的 PNG、JPEG、GIF 或 WebP 图片。") }
}
