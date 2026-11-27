import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

struct StoredDeskPet: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let width: Int
    let height: Int
}

@MainActor
@Observable
final class DeskPetLibrary {
    static let shared = DeskPetLibrary()
    static let importTypes: [UTType] = [.png, .jpeg, .gif, .webP]
    private nonisolated static let maxBytes = 16 << 20
    private(set) var pets: [StoredDeskPet] = []
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
    }

    func imageURL(for pet: StoredDeskPet) -> URL {
        root.appending(path: pet.id.uuidString).appending(path: "image")
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

    func add(_ data: Data, name: String, id: UUID = UUID()) throws {
        if pets.contains(where: { $0.id == id }) { return }
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pet = StoredDeskPet(id: id, name: trimmed.isEmpty ? String(localized: "桌宠") : String(trimmed.prefix(80)),
                                width: rotated ? height : width, height: rotated ? width : height)
        let fm = FileManager.default
        let staging = root.appending(path: ".\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try data.write(to: staging.appending(path: "image"))
        try JSONEncoder().encode(pet).write(to: staging.appending(path: "pet.json"))
        try fm.moveItem(at: staging, to: root.appending(path: id.uuidString, directoryHint: .isDirectory))
        pets.append(pet)
        pets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private nonisolated static func source(_ data: Data) -> CGImageSource? {
        guard !data.isEmpty, data.count <= maxBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              let contentType = UTType(type), [.png, .jpeg, .gif, .webP].contains(contentType) else { return nil }
        return source
    }

    nonisolated static func picture(at url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url), let source = source(data) else { return nil }
        if let animated = AnimatedPicture.decode(data, longEdge: 600) { return animated }
        guard let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
        ] as CFDictionary) else { return nil }
        return UIImage(cgImage: frame)
    }
}

private struct InvalidPetImage: LocalizedError {
    var errorDescription: String? { String(localized: "请选择 16 MB 以内、边长不超过 4096 像素的 PNG、JPEG、GIF 或 WebP 图片。") }
}
