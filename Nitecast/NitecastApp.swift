import SwiftUI

@main
@MainActor
struct NitecastApp: App {
    init() { CastSetup.configure() }
    var body: some Scene {
        WindowGroup {
            FamilyServiceView()
                .preferredColorScheme(.dark)
                .tint(.nitecast)
        }
    }
}

extension Color {
    static let nitecast = Color(red:0.66, green:0.55, blue:1)
    static let cinema = Color(red:0.035, green:0.039, blue:0.063)
    static let cinemaPanel = Color(red:0.09, green:0.098, blue:0.137)
}
