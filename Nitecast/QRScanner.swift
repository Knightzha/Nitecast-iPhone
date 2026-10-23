import SwiftUI
import AVFoundation

struct QRScanner: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let failure {
                    ContentUnavailableView("Camera unavailable",systemImage:"camera.fill",description:Text(failure))
                } else {
                    CameraRepresentable(onCode:onCode,onFailure:{ failure = $0 }).ignoresSafeArea(edges:.bottom)
                    VStack {
                        Text("Point at the QR code in Nitecast → Phone remote on your PC.")
                            .font(.subheadline).multilineTextAlignment(.center).padding().background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:12))
                        Spacer()
                        RoundedRectangle(cornerRadius:24).stroke(Color.nitecast,lineWidth:3).frame(width:250,height:250)
                        Spacer()
                        Text("You can also enter the PC address manually.").font(.caption).padding().background(.black.opacity(0.65),in:Capsule())
                    }.padding(24)
                }
            }.navigationTitle("Scan your PC").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct CameraRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onFailure: (String) -> Void
    func makeUIViewController(context: Context) -> CameraController {
        CameraController(onCode:onCode,onFailure:onFailure)
    }
    func updateUIViewController(_ controller: CameraController,context: Context) {}
    static func dismantleUIViewController(_ controller: CameraController,coordinator: ()) { controller.stop() }
}

private final class CameraController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label:"app.nitecast.camera")
    private let onCode: (String) -> Void
    private let onFailure: (String) -> Void
    private var preview: AVCaptureVideoPreviewLayer?
    private var handled = false
    private var closing = false

    init(onCode:@escaping (String) -> Void,onFailure:@escaping (String) -> Void) {
        self.onCode = onCode; self.onFailure = onFailure
        super.init(nibName:nil,bundle:nil)
    }
    required init?(coder: NSCoder) { fatalError("Not available") }
    override func viewDidLoad() {
        super.viewDidLoad()
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, !self.closing else { return }
                    if allowed { self.configure() } else { self.onFailure("Allow Camera in iPhone Settings, or enter your PC address manually.") }
                }
            }
        default:onFailure("Allow Camera in iPhone Settings, or enter your PC address manually.")
        }
    }
    private func configure() {
        guard !closing, let camera = AVCaptureDevice.default(for:.video),
              let input = try? AVCaptureDeviceInput(device:camera),session.canAddInput(input) else {
            onFailure("No usable camera was found. Enter your PC address manually."); return
        }
        session.beginConfiguration()
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration();onFailure("Couldn’t start the QR scanner.");return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self,queue:.main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()
        let layer = AVCaptureVideoPreviewLayer(session:session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        captureQueue.async { [session] in session.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews();preview?.frame = view.bounds }
    func stop() {
        closing = true
        captureQueue.async { [session] in if session.isRunning { session.stopRunning() } }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput,didOutput metadataObjects:[AVMetadataObject],from connection:AVCaptureConnection) {
        guard !handled, let code = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        handled = true;stop();onCode(code)
    }
}
