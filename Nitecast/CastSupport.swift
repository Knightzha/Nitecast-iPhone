import SwiftUI
import GoogleCast

@MainActor
enum CastSetup {
    private static var configured = false
    static func configure() {
        guard !configured else { return }
        let criteria = GCKDiscoveryCriteria(applicationID:kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria:criteria)
        GCKCastContext.setSharedInstanceWith(options)
        configured = true
    }
}
struct LocalCastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame:.zero)
        button.tintColor = .white
        return button
    }
    func updateUIView(_ view: GCKUICastButton,context: Context) {}
}
