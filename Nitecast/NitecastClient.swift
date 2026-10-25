import Foundation
import SwiftUI
import Security
import UIKit

enum PairingKeychain {
    static let service = "app.nitecast.companion.pairing"
    static func token(for server: URL) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: server.absoluteString,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let bytes = result as? Data else { return nil }
        return String(data: bytes, encoding: .utf8)
    }
    static func store(_ token: String?, for server: URL) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: server.absoluteString]
        SecItemDelete(query as CFDictionary)
        guard let token else { return }
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw NitecastError.message("Couldn’t securely save this pairing. Please try again.")
        }
    }
}

final class LocalRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let next = request.url,
              original.host == next.host, original.port == next.port, original.scheme == next.scheme else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }
}

@MainActor
final class NitecastClient: ObservableObject {
    @Published var state: LibraryState?
    @Published var server: URL?
    @Published var isPaired = false
    @Published var isOnline = false
    @Published var isBusy = false
    @Published var error: String?
    @Published var showScreens = false
    private var polling = false
    private var connectionHealth = ConnectionHealth()
    private var commandTail: Task<Bool, Never>?
    private var commandRevision = 0
    private let redirects = LocalRedirectGuard()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
    }()
    // Artwork must not occupy the connections used by controls and state polling.
    private lazy var artworkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config, delegate: redirects, delegateQueue: nil)
    }()
    private let imageCache = NSCache<NSString, UIImage>()
    private var generation = 0

    init() {
        imageCache.totalCostLimit = 60 * 1024 * 1024
        imageCache.countLimit = 100
        if let stored = UserDefaults.standard.string(forKey: "nitecast.server"), let url = try? ServerAddress.normalize(stored) {
            server = url
            isPaired = PairingKeychain.token(for: url) != nil
        }
    }

    var currentCollection: MediaCollection? { state?.playlists.first { $0.id == state?.now.pid } }
    var currentItem: MediaItem? {
        guard let p = currentCollection, let index = state?.now.index, p.items.indices.contains(index) else { return nil }
        return p.items[index]
    }

    func configure(address: String) throws {
        let value = try ServerAddress.normalize(address)
        if value != server {
            generation += 1
            connectionHealth = ConnectionHealth()
            state = nil
            imageCache.removeAllObjects()
            isOnline = false
        }
        server = value
        isPaired = PairingKeychain.token(for: value) != nil
        UserDefaults.standard.set(value.absoluteString, forKey: "nitecast.server")
    }

    private func request(_ path: String, body: [String: Any]? = nil, timeout: TimeInterval = 10, artwork: Bool = false) async throws -> (Data, HTTPURLResponse) {
        guard let server, let url = URL(string: path, relativeTo: server)?.absoluteURL,
              url.host == server.host, url.port == server.port, url.scheme == server.scheme else {
            throw NitecastError.message("Connect this iPhone to your PC first.")
        }
        let captured = generation
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        if let token = PairingKeychain.token(for: server) { request.setValue("nitecast_phone=\(token)", forHTTPHeaderField: "Cookie") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await (artwork ? artworkSession : session).data(for: request)
        guard captured == generation else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw NitecastError.message("Your PC sent an invalid response.") }
        if http.statusCode == 401 {
            isPaired = false
            isOnline = false
            throw NitecastError.message("Pair this iPhone again using the code on your PC.")
        }
        guard 200..<300 ~= http.statusCode else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw NitecastError.message(message ?? "Your PC couldn’t complete that request (\(http.statusCode)).")
        }
        return (data, http)
    }

    func pair(address: String, pin: String) async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            guard pin.count == 6, pin.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                throw NitecastError.message("Enter the six-digit code shown in Nitecast → Phone remote.")
            }
            try configure(address: address)
            let (_, response) = try await request("/api/companion/pair", body: ["pin":pin, "name":UIDevice.current.name])
            guard let server else { return }
            let headers = response.allHeaderFields.reduce(into: [String:String]()) { result, entry in
                result[String(describing: entry.key)] = String(describing: entry.value)
            }
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: server)
            guard let cookie = cookies.first(where: { $0.name == "nitecast_phone" && !$0.value.isEmpty }) else {
                throw NitecastError.message("Your PC didn’t return a pairing token. Update Nitecast on the PC and retry.")
            }
            try PairingKeychain.store(cookie.value, for: server)
            isPaired = true
            await refresh()
        } catch { self.error = friendlyError(error) }
    }

    func refresh() async {
        guard server != nil, isPaired, !polling else { return }
        polling = true
        let captured = generation
        let revision = commandRevision
        defer { polling = false }
        do {
            let data: Data
            do { data = try await request("/api/state").0 }
            catch let network as URLError where network.code != .cancelled {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds:500_000_000)
                data = try await request("/api/state").0
            }
            let value = try JSONDecoder().decode(LibraryState.self, from: data)
            guard captured == generation, revision == commandRevision else { return }
            connectionHealth.succeeded()
            state = value; isOnline = true
        } catch {
            guard captured == generation else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            if !isPaired { isOnline = false; return }
            connectionHealth.failed()
            if connectionHealth.isDisconnected { isOnline = false }
        }
    }

    @discardableResult
    func command(_ path: String, _ body: [String: Any]) async -> Bool {
        let previous = commandTail
        let captured = generation
        let operation = Task { @MainActor [weak self] () -> Bool in
            _ = await previous?.value
            guard let self, captured == self.generation, self.isPaired else { return false }
            self.commandRevision += 1
            do {
                // Never retry POST controls: a timeout may still have applied a toggle/next.
                let (data, _) = try await self.request("/api/" + path, body: body, timeout:30)
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let message = obj["error"] as? String {
                    throw NitecastError.message(message)
                }
                self.commandRevision += 1
                self.connectionHealth.succeeded()
                self.isOnline = true
                return true
            } catch {
                self.commandRevision += 1
                guard captured == self.generation else { return false }
                if !(error is CancellationError) { self.error = self.friendlyError(error) }
                return false
            }
        }
        commandTail = operation
        let succeeded = await operation.value
        if succeeded { Task { await self.refresh() } }
        return succeeded
    }

    func play(_ collection: MediaCollection, index: Int, restart: Bool = false) async -> Bool {
        guard collection.items.indices.contains(index), !collection.items[index].missing.orFalse else {
            error = "This video’s drive or file is unavailable."; return false
        }
        guard let state, let device = state.device, state.devices.contains(device) else {
            showScreens = true; return false
        }
        return await command("play", ["id":collection.id, "index":index, "resume":!restart])
    }

    func artworkPath(_ collection: MediaCollection, banner: Bool = false) -> String {
        if !banner, let icon = collection.icon { return "/icon/" + icon }
        var parts = URLComponents()
        parts.path = "/art"
        parts.queryItems = [URLQueryItem(name:"id", value:collection.id), URLQueryItem(name:banner ? "banner" : "poster", value:"1")]
        return parts.string ?? "/brand.png"
    }

    func image(path: String) async -> UIImage? {
        guard let server else { return nil }
        let key = (server.absoluteString + path) as NSString
        if let cached = imageCache.object(forKey:key) { return cached }
        do {
            let (data, _) = try await request(path, artwork:true)
            guard data.count < 15 * 1024 * 1024, let image = UIImage(data:data) else { return nil }
            let decodedCost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
            imageCache.setObject(image, forKey:key, cost:decodedCost)
            return image
        } catch { return nil }
    }

    func forget() async {
        if isOnline { _ = try? await request("/api/companion/disconnect", body:[:]) }
        if let server { try? PairingKeychain.store(nil, for:server) }
        generation += 1
        connectionHealth = ConnectionHealth()
        isPaired = false; isOnline = false; state = nil; error = nil
        imageCache.removeAllObjects()
    }

    private func friendlyError(_ error: Error) -> String {
        if let issue = error as? NitecastError { return issue.localizedDescription }
        if error is DecodingError { return "This PC’s Nitecast version returned unfamiliar data. Update the PC app and reconnect." }
        if let network = error as? URLError {
            if network.code == .cancelled { return "Connection cancelled. Try again." }
            return "Couldn’t reach your PC. Keep Nitecast running, use the same home Wi-Fi, and allow Local Network access in iPhone Settings."
        }
        return error.localizedDescription
    }
}

private extension Optional where Wrapped == Bool { var orFalse: Bool { self ?? false } }

// An interrupted foreground poll is not a lost pairing. Three complete failed polls
// (each including one safe GET retry) are required before showing offline.
struct ConnectionHealth {
    private(set) var failures = 0
    var isDisconnected: Bool { failures >= 3 }
    mutating func succeeded() { failures = 0 }
    mutating func failed() { failures += 1 }
}
