import Foundation

struct LibraryState: Decodable {
    let playlists: [MediaCollection]
    let devices: [String]
    let device: String?
    let now: PlaybackState
    let job: PreparationJob?
    let dual: DualScreenState?
    let scanning: Bool?
    let screen: ScreenConnection?
}

struct ScreenConnection: Decodable {
    let name: String?
    let connected: Bool
    let configured: Bool?
}

struct MediaCollection: Decodable, Identifiable {
    let id: String
    let name: String
    let items: [MediaItem]
    let kind: String?
    let pos: Int?
    let favorite: Bool?
    let icon: String?
    let description: String?
    let genres: [String]?
    let catalog_banner: String?

    var isSeries: Bool { kind.map { $0 == "series" } ?? (items.count != 1) }
    var seasons: [Int] { Array(Set(items.map { $0.season ?? 1 })).sorted() }
    var resumeIndex: Int {
        let continuing = items.indices.filter { !(items[$0].watched ?? false) && (items[$0].position ?? 0) > 10 }
        if let best = continuing.max(by: { (items[$0].last_played ?? 0) < (items[$1].last_played ?? 0) }) { return best }
        return min(max(pos ?? 0, 0), max(0, items.count - 1))
    }
    var hasProgress: Bool { items.contains { !($0.watched ?? false) && ($0.position ?? 0) > 10 } }
    var subtitle: String {
        isSeries ? "\(seasons.count) season\(seasons.count == 1 ? "" : "s")" : "Movie"
    }
}

struct MediaItem: Decodable {
    let title: String
    let season: Int?
    let episode: Int?
    let position: Double?
    let duration: Double?
    let watched: Bool?
    let missing: Bool?
    let last_played: Double?
}

struct PlaybackState: Decodable {
    let pid: String?
    let index: Int
    let state: String
    let t: Double
    let dur: Double
    let vol: Double?
    let error: String?
    let sleep: Int?
    let eoe: Bool?
}

struct PreparationJob: Decodable {
    let active: Bool
    let title: String?
    let stage: String?
    let percent: Double?
}

struct DualScreenState: Decodable {
    let enabled: Bool
    let audio: String
    let offset: Double
    let connected: Bool?
}

enum NitecastError: LocalizedError {
    case message(String)
    case screenOffline
    case viewerExpired
    var errorDescription: String? {
        switch self { case .message(let value): return value
        case .screenOffline: return "TV offline—reconnecting."
        case .viewerExpired: return "Reconnecting playback…" }
    }
}

enum ServerAddress {
    static func normalize(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw NitecastError.message("Enter your PC address or scan its QR code.") }
        let text = value.contains("://") ? value : "http://" + value
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let rawHost = parts.host,
              parts.user == nil, parts.password == nil else {
            throw NitecastError.message("Use the PC address shown in Nitecast → Phone remote.")
        }
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let numbers = host.split(separator: ".").compactMap { Int($0) }
        let ipv4 = numbers.count == 4 && host.split(separator: ".").count == 4 && numbers.allSatisfy { 0...255 ~= $0 }
        let localIPv4 = ipv4 && (numbers[0] == 10 || (numbers[0] == 192 && numbers[1] == 168) ||
                                     (numbers[0] == 172 && 16...31 ~= numbers[1]) || (numbers[0] == 169 && numbers[1] == 254))
        let localIPv6 = host.contains(":") && (host.hasPrefix("fd") || host.hasPrefix("fc") || host.hasPrefix("fe80:"))
        let localName = host.hasSuffix(".local") || (!host.contains(".") && !host.contains(":") && host != "localhost" && host.first?.isLetter == true &&
                       host.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil)
        let remoteHTTPS = scheme == "https" && host.contains(".") && !ipv4 && !host.contains(":") && !host.hasSuffix(".localhost") && host != "localhost"
        guard localIPv4 || localIPv6 || localName || remoteHTTPS else {
            throw NitecastError.message("Choose your PC’s local Wi-Fi address, such as 192.168.1.20:8765 or nitecast-xxxxxx.local:8765.")
        }
        if parts.port == nil { parts.port = remoteHTTPS ? 443 : 8765 }
        guard let port = parts.port, 1...65535 ~= port else { throw NitecastError.message("The port number is invalid.") }
        parts.scheme = scheme
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { throw NitecastError.message("That PC address is invalid.") }
        return url
    }
}

func playbackTime(_ value: Double) -> String {
    let seconds = Int(max(0, value.isFinite ? value : 0))
    if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

struct QRPairing {
    let server: URL
    let key: String
    static func parse(_ value: String) throws -> QRPairing {
        let server = try ServerAddress.normalize(value)
        guard let components = URLComponents(string:value),
              let fragment = components.fragment,
              let key = URLComponents(string:"http://pair/?" + fragment)?.queryItems?.first(where:{$0.name == "pair"})?.value,
              (30...100).contains(key.count), key.range(of:"^[A-Za-z0-9_-]+$",options:.regularExpression) != nil else {
            throw NitecastError.message("Open Phone remote in the updated PC app and scan its new QR code. No PIN is needed.")
        }
        return QRPairing(server:server,key:key)
    }
}
