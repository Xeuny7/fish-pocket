import Foundation
import Observation

struct WorkshopCredit: Codable, Equatable, Sendable {
    let slug: String
    let title: String
    let author: String
    let authorURL: URL?

    static let site = URL(string: "https://workshop.kurocat.cc/")!
}

struct WorkshopEntry: Decodable, Identifiable, Sendable {
    let slug: String
    let title: String
    let author: String
    let authorUrl: String?
    let description: String?
    let paletteSummary: [String]?
    let colors: [String: StringOrBool]?
    var id: String { slug }

    enum StringOrBool: Decodable, Sendable {
        case string(String), bool(Bool)

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let string = try? value.decode(String.self) { self = .string(string) }
            else { self = .bool(try value.decode(Bool.self)) }
        }
    }

    var credit: WorkshopCredit {
        let url = authorUrl.flatMap { URL(string: $0) }.flatMap { candidate in
            candidate.scheme == "https" && candidate.host != nil ? candidate : nil
        }
        return WorkshopCredit(slug: slug, title: title, author: author, authorURL: url)
    }

    var swatches: [String] {
        if let paletteSummary { return Array(paletteSummary.prefix(3)) }
        return ["base", "deck", "key", "accent"].compactMap {
            guard case .string(let color)? = colors?[$0] else { return nil }
            return color
        }
    }
}

enum KuroWorkshop {
    enum Kind: String, CaseIterable, Identifiable {
        case cats = "community"
        case keyboards = "community-keyboards"
        var id: String { rawValue }
        var file: String { self == .cats ? "skin.kurocat" : "keyboard.json" }
    }

    enum AssetError: LocalizedError {
        case invalid, artwork

        var errorDescription: String? {
            switch self {
            case .invalid: String(localized: "无法读取工坊素材。")
            case .artwork: String(localized: "这款外观依赖独立插画，暂不支持安装。")
            }
        }
    }

    private struct Catalog: Decodable {
        let skins: [WorkshopEntry]?
        let keyboards: [WorkshopEntry]?
    }

    static func catalog(_ kind: Kind) async throws -> [WorkshopEntry] {
        let data = try await download([kind.rawValue, "index.json"], limit: 2 << 20)
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        return (kind == .cats ? catalog.skins : catalog.keyboards) ?? []
    }

    static func asset(_ entry: WorkshopEntry, kind: Kind) async throws -> Data {
        guard !entry.slug.isEmpty, entry.slug.utf8.count <= 100, entry.slug.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }) else { throw AssetError.invalid }
        return try await download([kind.rawValue, entry.slug, kind.file], limit: kind == .cats ? 8 << 20 : 64 << 10)
    }

    private static func download(_ path: [String], limit: Int) async throws -> Data {
        let url = path.reduce(WorkshopCredit.site) { $0.appending(path: $1) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: SameOrigin(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.expectedContentLength <= Int64(limit) else { throw AssetError.invalid }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw AssetError.invalid }
            data.append(byte)
        }
        return data
    }

    private final class SameOrigin: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}

struct WorkshopKeyboard: Codable, Equatable, Sendable {
    let credit: WorkshopCredit
    let json: String

    init(credit: WorkshopCredit, data: Data) throws {
        struct Theme: Decodable {
            let formatVersion: Int
            let colors: [String: WorkshopEntry.StringOrBool]
        }
        let theme = try JSONDecoder().decode(Theme.self, from: data)
        let keys = ["mouseBody", "mouseBorder", "wheel", "base", "deck", "key", "keyBorder", "accent"]
        guard theme.formatVersion == 1, keys.allSatisfy({ key in
            guard case .string(let value)? = theme.colors[key] else { return false }
            return Self.isColor(value)
        }) else { throw KuroWorkshop.AssetError.invalid }
        self.credit = credit
        self.json = String(decoding: data, as: UTF8.self)
    }

    static func isColor(_ value: String) -> Bool {
        value.utf8.count == 7 && value.first == "#" && value.dropFirst().utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }
}
