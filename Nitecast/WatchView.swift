import SwiftUI
import AVKit
import GoogleCast

struct WatchSelection: Identifiable {
    let id = UUID()
    let collection: MediaCollection
    let index: Int
    let restart: Bool
}
struct ViewerSession: Decodable {
    let id: String
    let title: String
    let status: String
    let percent: Double
    let message: String
    let media: String
    let mime: String?
    let start: Double
}

@MainActor
final class PhonePlayback: NSObject, ObservableObject, GCKRequestDelegate {
    @Published var casting = false
    private var castLoadedID: String?
    @Published var player: AVPlayer?
    @Published var session: ViewerSession?
    @Published var message = "Connecting…"
    @Published var index: Int
    @Published var mode = "auto"
    @Published var retryAvailable = false
    @Published private(set) var transitioning = false
    private var client: NitecastClient?
    private var sessionID: String?
    private var revision = 0
    private var position = 0.0
    private var lastReport = Date.distantPast
    private let selection: WatchSelection
    init(selection: WatchSelection) { self.selection = selection; self.index = selection.index; super.init() }
    var title: String { selection.collection.items.indices.contains(index) ? selection.collection.items[index].title : selection.collection.name }
    var canPrevious: Bool { index > 0 }
    var canNext: Bool { index + 1 < selection.collection.items.count }

    func start(client: NitecastClient, restart: Bool = false) async {
        self.client = client
        revision += 1
        let captured = revision
        transitioning = true
        defer { if captured == revision { transitioning = false } }
        castLoadedID = nil
        let old = sessionID
        player?.pause(); player = nil; session = nil
        message = "Connecting…"; retryAvailable = false
        do {
            let data = try await client.viewerRequest("/api/watch/start",body:["id":selection.collection.id,"index":index,"resume":!restart,"mode":mode,"replace":old ?? ""])
            let value = try JSONDecoder().decode(ViewerSession.self,from:data)
            guard captured == revision else {
                _ = try? await client.viewerRequest("/api/watch/stop",body:["session":value.id])
                return
            }
            sessionID = value.id; session = value; position = value.start
        } catch { message = error.localizedDescription; retryAvailable = true }
    }
    func tick() async {
        guard let client, let sessionID else { return }
        let captured = revision
        do {
            let data = try await client.viewerRequest("/api/watch/session?id="+sessionID)
            let value = try JSONDecoder().decode(ViewerSession.self,from:data)
            guard captured == revision else { return }
            session = value
            if value.status == "ready" {
                if let remote = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient {
                    casting = true
                    player?.pause()
                    if castLoadedID != value.id {
                        let info = GCKMediaInformationBuilder(contentURL:try client.mediaURL(value.media))
                        info.streamType = .buffered
                        info.contentType = value.mime ?? "video/mp4"
                        let metadata = GCKMediaMetadata()
                        metadata.setString(title,forKey:kGCKMetadataKeyTitle)
                        info.metadata = metadata
                        let load = GCKMediaLoadRequestDataBuilder()
                        load.mediaInformation = info.build()
                        load.startTime = position
                        remote.loadMedia(with:load.build()).delegate = self
                        castLoadedID = value.id
                    }
                    let expectedURL = try client.mediaURL(value.media)
                    guard remote.mediaStatus?.mediaInformation?.contentURL?.absoluteString == expectedURL.absoluteString else {
                        if !retryAvailable { message = "Connecting to TV…" }
                        return
                    }
                    let current = remote.approximateStreamPosition()
                    let duration = remote.mediaStatus?.mediaInformation?.streamDuration ?? 0
                    if current.isFinite && current >= 0 { position = current }
                    if duration > 0 && Date().timeIntervalSince(lastReport) >= 10 {
                        _ = try await client.viewerRequest("/api/watch/progress",body:["session":sessionID,"position":position,"duration":duration])
                        lastReport = Date()
                    }
                    if remote.mediaStatus?.playerState == .playing || remote.mediaStatus?.playerState == .paused { message = "" }
                    return
                }
                if casting { casting = false; castLoadedID = nil; message = "TV disconnected. Choose a screen or press play on your iPhone." }
                if player == nil || player?.status == .failed {
                    let new = AVPlayer(url:try client.mediaURL(value.media))
                    new.allowsExternalPlayback = true
                    player = new
                    if position > 0 { await new.seek(to:CMTime(seconds:position,preferredTimescale:600)) }
                    guard captured == revision else { new.pause(); return }
                    new.play()
                }
                if let player {
                    let current = player.currentTime().seconds
                    if current.isFinite && current > 0 { position = current }
                    if player.status == .failed {
                        message = "Playback interrupted. Reconnecting… Try Compatible if this file cannot play."
                        retryAvailable = true
                    } else { message = ""; retryAvailable = false }
                    if Date().timeIntervalSince(lastReport) >= 10 {
                        let duration = player.currentItem?.duration.seconds ?? 0
                        if duration.isFinite && duration > 0 {
                            _ = try await client.viewerRequest("/api/watch/progress",body:["session":sessionID,"position":position,"duration":duration])
                            lastReport = Date()
                        }
                    }
                }
            } else {
                message = value.message
                retryAvailable = value.status == "error" || value.status == "stopped"
            }
        } catch {
            guard captured == revision else { return }
            if Task.isCancelled { return }
            if let issue = error as? NitecastError, case .viewerExpired = issue {
                await start(client:client)
                return
            }
            message = "Host offline—reconnecting. Keep the PC awake and Nitecast running."
        }
    }
    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        message = "TV couldn’t start playback. Check the connection or try Compatible quality."
        retryAvailable = true
    }
    func changeEpisode(_ delta: Int) async {
        guard let client, !transitioning else { return }
        let captured = revision
        let next = index + delta
        guard selection.collection.items.indices.contains(next) else { return }
        await report()
        guard captured == revision else { return }
        index = next
        await start(client:client)
    }
    func retry() async {
        guard let client, !transitioning else { return }
        let captured = revision
        await report()
        guard captured == revision else { return }
        await start(client:client)
    }
    func report() async {
        guard let client, let sessionID else { return }
        if casting, let remote = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient {
            let duration = remote.mediaStatus?.mediaInformation?.streamDuration ?? 0
            if duration > 0 { _ = try? await client.viewerRequest("/api/watch/progress",body:["session":sessionID,"position":remote.approximateStreamPosition(),"duration":duration]) }
            return
        }
        guard let player else { return }
        let duration = player.currentItem?.duration.seconds ?? 0
        let current = player.currentTime().seconds
        guard current.isFinite, duration.isFinite, duration > 0 else { return }
        _ = try? await client.viewerRequest("/api/watch/progress",body:["session":sessionID,"position":current,"duration":duration])
    }
    func stop() async {
        revision += 1
        player?.pause()
        await report()
        if casting { GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient?.stop() }
        let old = sessionID
        sessionID = nil; player = nil
        if let old, let client { _ = try? await client.viewerRequest("/api/watch/stop",body:["session":old]) }
    }
}

struct WatchView: View {
    @EnvironmentObject private var client: NitecastClient
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playback: PhonePlayback
    private let selection: WatchSelection
    init(selection: WatchSelection) {
        self.selection = selection
        _playback = StateObject(wrappedValue:PhonePlayback(selection:selection))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:16) {
                if playback.casting {
                    Spacer()
                    Image(systemName:"tv").font(.system(size:64)).foregroundStyle(Color.nitecast)
                    Text(playback.title).font(.headline)
                    Button("TV playback controls") { GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls() }.buttonStyle(.borderedProminent)
                    Spacer()
                } else if let player = playback.player {
                    NativeVideoPlayer(player:player).frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                    Spacer()
                    Image(systemName:"play.rectangle").font(.system(size:64)).foregroundStyle(Color.nitecast)
                    Text(playback.title).font(.headline).multilineTextAlignment(.center)
                    if !playback.retryAvailable { ProgressView(value:playback.session?.percent ?? 0,total:100).padding(.horizontal,35) }
                    Spacer()
                }
                if !playback.message.isEmpty { Text(playback.message).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal) }
                HStack {
                    Button("Previous") { Task { await playback.changeEpisode(-1) } }.disabled(!playback.canPrevious || playback.transitioning)
                    Spacer()
                    AirPlayRoutePicker().frame(width:44,height:44)
                    LocalCastButton().frame(width:44,height:44)
                    Spacer()
                    Button("Next") { Task { await playback.changeEpisode(1) } }.disabled(!playback.canNext || playback.transitioning)
                }.padding(.horizontal)
                Picker("Quality",selection:$playback.mode) {
                    Text("Compatible").tag("auto")
                    Text("Original").tag("original")
                    Text("720p").tag("720p")
                    Text("1080p").tag("1080p")
                }.pickerStyle(.segmented).padding(.horizontal)
                if playback.retryAvailable { Button("Retry playback") { Task { await playback.retry() } }.buttonStyle(.borderedProminent) }
                Text("This session is independent of the home TV. Choose AirPlay or Cast to watch on a TV on this Wi-Fi.")
                    .font(.caption2).foregroundStyle(.secondary).padding(.horizontal)
            }.background(Color.cinema).navigationTitle("Watch on iPhone").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { Button("Done") { playback.player?.pause(); dismiss() } } }
                .task { await playback.start(client:client,restart:selection.restart); while !Task.isCancelled { await playback.tick(); do { try await Task.sleep(nanoseconds:2_000_000_000) } catch { break } } }
                .onChange(of:playback.mode) { _,_ in Task { await playback.retry() } }
                .onDisappear { Task { await playback.stop() } }
        }
    }
}
struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController,context: Context) { if controller.player !== player { controller.player = player } }
}
struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.prioritizesVideoDevices = true; view.tintColor = .white; return view }
    func updateUIView(_ view: AVRoutePickerView,context: Context) {}
}
