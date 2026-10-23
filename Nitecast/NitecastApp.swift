import SwiftUI

@main
struct NitecastApp: App {
    @StateObject private var client = NitecastClient()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
                .preferredColorScheme(.dark)
                .tint(.nitecast)
                .task(id:scenePhase == .active) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await client.refresh()
                        do { try await Task.sleep(nanoseconds:2_000_000_000) } catch { break }
                    }
                }
        }
    }
}

extension Color {
    static let nitecast = Color(red:0.66, green:0.55, blue:1)
    static let cinema = Color(red:0.035, green:0.039, blue:0.063)
    static let cinemaPanel = Color(red:0.09, green:0.098, blue:0.137)
}
