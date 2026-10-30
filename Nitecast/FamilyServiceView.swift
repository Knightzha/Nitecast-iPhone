import SwiftUI
import WebKit
import UIKit
import GoogleCast

// The PC serves one responsive interface; native Cast remains available on iPhone.
struct FamilyServiceView: View {
    @AppStorage("nitecast.familyServer") private var savedAddress = ""
    @State private var enteredAddress = "nitecast.duckdns.org"
    @State private var changingHost = false
    @State private var addressError = ""
    @State private var scanning = false
    @State private var hostOffline = false
    @State private var playerPresented = false
    @State private var scannedURL: URL?
    var body: some View {
        NavigationStack {
            Group {
                if !savedAddress.isEmpty, let url = URL(string:savedAddress), !changingHost {
                    VStack(spacing:0) {
                        if hostOffline { Text("Host offline—reconnecting").font(.caption).frame(maxWidth:.infinity).padding(10).background(.orange.opacity(0.2)) }
                        FamilyWebView(server:url,signInURL:scannedURL,offline:$hostOffline,playerPresented:$playerPresented)
                    }
                        .ignoresSafeArea(edges:playerPresented ? .all : .bottom)
                } else {
                    VStack(alignment:.leading,spacing:22) {
                        Brand()
                        Text("Your night starts here.").font(.largeTitle.bold())
                        Text("Connect to your family’s Nitecast host, then sign in. Your login stays saved on this iPhone.")
                            .foregroundStyle(.secondary)
                        TextField("Host address",text:$enteredAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                            .textFieldStyle(.roundedBorder)
                        Button("Open Nitecast") {
                            do {
                                let url = try ServerAddress.normalize(enteredAddress)
                                savedAddress = url.absoluteString
                                changingHost = false; addressError = ""
                            } catch { addressError = error.localizedDescription }
                        }.buttonStyle(.borderedProminent)
                        if !addressError.isEmpty { Text(addressError).foregroundStyle(.orange) }
                        Spacer()
                    }.padding(28)
                }
            }.background(Color.cinema)
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        if !savedAddress.isEmpty {
                            Button(changingHost ? "Back" : "Host") {
                                enteredAddress = savedAddress
                                changingHost.toggle()
                            }.font(.caption)
                        }
                    }
                    ToolbarItem(placement:.principal) { Text("Nitecast").font(.caption.bold()) }
                    ToolbarItem(placement:.topBarTrailing) { HStack { Button { scanning = true } label: { Image(systemName:"qrcode.viewfinder") }.accessibilityLabel("Scan sign-in QR") } }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(playerPresented ? .hidden : .visible,for:.navigationBar)
                .statusBarHidden(playerPresented)
        }.sheet(isPresented:$scanning) {
            QRScanner { code in
                guard let url = URL(string:code), let parts = URLComponents(url:url,resolvingAgainstBaseURL:false),
                      let scheme = url.scheme, ["https","http"].contains(scheme),
                      let fragment = parts.fragment, fragment.hasPrefix("signin="),
                      url.host != nil else { addressError = "Scan a Nitecast account sign-in QR."; scanning = false; return }
                if !savedAddress.isEmpty, let existing = URL(string:savedAddress), !ServerAddress.sameOrigin(existing,url) {
                    addressError = "That code belongs to a different host. Change your host address first."
                    scanning = false; return
                }
                var base = parts; base.path = ""; base.query = nil; base.fragment = nil
                guard let address = base.url, (try? ServerAddress.normalize(address.absoluteString)) != nil else { scanning = false; return }
                savedAddress = address.absoluteString; scannedURL = url
                changingHost = false; scanning = false
            }
        }.preferredColorScheme(.dark)
    }
}

struct FamilyWebView: UIViewRepresentable {
    let server: URL
    let signInURL: URL?
    @Binding var offline: Bool
    @Binding var playerPresented: Bool
    func makeCoordinator() -> Coordinator { Coordinator(server:server,offline:$offline,playerPresented:$playerPresented) }
    func makeUIView(context:Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Persistent, system-managed cookie storage remembers account sessions.
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.userContentController.add(context.coordinator,name:"nitecast")
        configuration.userContentController.addUserScript(WKUserScript(source:"window.nitecastNativeFeatures={castPicker:1};",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        configuration.userContentController.addUserScript(WKUserScript(source:"var style=document.createElement('style');style.textContent='#playerDialog .volume-control{display:none}';document.head.appendChild(style);var viewport=document.querySelector('meta[name=viewport]');if(viewport)viewport.content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover';",injectionTime:.atDocumentEnd,forMainFrameOnly:true))
        let view = WKWebView(frame:.zero,configuration:configuration)
        view.isOpaque = false; view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.bouncesZoom = false
        view.scrollView.pinchGestureRecognizer?.isEnabled = false
        view.navigationDelegate = context.coordinator
        context.coordinator.webView = view
        context.coordinator.lastSignInURL = signInURL
        view.load(URLRequest(url:signInURL ?? server.appendingPathComponent("phone")))
        context.coordinator.startTimer()
        return view
    }
    func updateUIView(_ view:WKWebView,context:Context) {
        if let signInURL, signInURL != context.coordinator.lastSignInURL {
            context.coordinator.lastSignInURL = signInURL
            view.load(URLRequest(url:signInURL)); return
        }
        guard context.coordinator.server != server else { return }
        context.coordinator.server = server
        view.load(URLRequest(url:server.appendingPathComponent("phone")))
    }
    static func dismantleUIView(_ view:WKWebView,coordinator:Coordinator) {
        coordinator.timer?.invalidate()
        if let observer = coordinator.castDialogObserver { NotificationCenter.default.removeObserver(observer) }
        view.configuration.userContentController.removeScriptMessageHandler(forName:"nitecast")
        view.navigationDelegate = nil
    }
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, GCKRequestDelegate {
        var server: URL
        weak var webView: WKWebView?
        var timer: Timer?
        var navigationFailed = false
        var lastSignInURL: URL?
        var pendingLoad: [String:Any]?
        var pendingSince = Date.distantPast
        var loadedID: String?
        var expectedContentURL: URL?
        var offline: Binding<Bool>
        var playerPresented: Binding<Bool>
        var pendingChoiceID: String?
        var choiceSince = Date.distantPast
        var dialogClosedAt: Date?
        var castDialogObserver: NSObjectProtocol?
        init(server:URL,offline:Binding<Bool>,playerPresented:Binding<Bool>) { self.server = server; self.offline = offline; self.playerPresented = playerPresented }
        func sameOrigin(_ url:URL) -> Bool {
            ServerAddress.sameOrigin(url,server)
        }
        func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy)->Void) {
            if action.targetFrame?.isMainFrame == false { decisionHandler(.cancel); return }
            guard let url = action.request.url, sameOrigin(url) || url.absoluteString == "about:blank" else {
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
            navigationFailed = false; offline.wrappedValue = false; playerPresented.wrappedValue = false
            webView.scrollView.minimumZoomScale = 1; webView.scrollView.maximumZoomScale = 1
            webView.scrollView.setZoomScale(1,animated:false)
            webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        }
        func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {
            if (error as NSError).code != NSURLErrorCancelled { navigationFailed = true; offline.wrappedValue = true }
        }
        func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {
            if (error as NSError).code != NSURLErrorCancelled { navigationFailed = true; offline.wrappedValue = true }
        }
        func notify(_ text:String) {
            guard let bytes = try? JSONSerialization.data(withJSONObject:[text]), let value = String(data:bytes,encoding:.utf8) else { return }
            webView?.evaluateJavaScript("note((\(value))[0])",completionHandler:nil)
        }
        func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  let frameURL = message.frameInfo.request.url, sameOrigin(frameURL),
                  let body = message.body as? [String:Any], let action = body["action"] as? String else { return }
            let manager = GCKCastContext.sharedInstance().sessionManager
            if action == "playerState", let open = body["open"] as? Bool {
                playerPresented.wrappedValue = open
            } else if action == "chooseCast", let id = body["id"] as? String {
                pendingChoiceID = id; choiceSince = Date(); dialogClosedAt = nil
                if manager.currentCastSession?.connectionState == .connected { finishChoice(true) }
                else { presentTVPicker() }
            } else if action == "cancelCastChoice" {
                pendingChoiceID = nil
            } else if action == "load" {
                guard let raw = body["url"] as? String, let url = URL(string:raw), sameOrigin(url), (url.path.hasPrefix("/watch-media/") || url.path.hasPrefix("/watch-hls/")) else { return }
                pendingLoad = body; pendingSince = Date()
                if manager.currentCastSession == nil { presentTVPicker() }
                else { loadPending() }
            } else if action == "seek", let time = body["time"] as? Double, time.isFinite, time >= 0 {
                let options = GCKMediaSeekOptions(); options.interval = time
                manager.currentCastSession?.remoteMediaClient?.seek(with:options).delegate = self
            } else if action == "subtitles", let ids = body["ids"] as? [Int] {
                manager.currentCastSession?.remoteMediaClient?.setActiveTrackIDs(ids.map { NSNumber(value:$0) }).delegate = self
            } else if action == "stop" {
                manager.currentCastSession?.remoteMediaClient?.stop()
                pendingLoad = nil; loadedID = nil; expectedContentURL = nil
            } else if action == "controls" { GCKCastContext.sharedInstance().presentDefaultExpandedMediaControls() }
        }
        func finishChoice(_ accepted:Bool) {
            guard let id = pendingChoiceID else { return }
            pendingChoiceID = nil; dialogClosedAt = nil
            guard let data = try? JSONSerialization.data(withJSONObject:[id,accepted] as [Any]), let json = String(data:data,encoding:.utf8) else { return }
            webView?.evaluateJavaScript("window.nitecastCastChoice && window.nitecastCastChoice(...\(json))",completionHandler:nil)
        }
        func presentTVPicker() {
            let show = {
                let context = GCKCastContext.sharedInstance()
                context.discoveryManager.startDiscovery()
                context.presentCastDialog()
            }
            guard !UserDefaults.standard.bool(forKey:"nitecast.castDiscoveryExplained") else { show(); return }
            let alert = UIAlertController(title:"Find your TV",message:"Nitecast uses your local network to find Chromecasts. Allow Local Network access when iOS asks. Your iPhone and TV need to be on the same Wi-Fi.",preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"Continue",style:.default) { _ in
                UserDefaults.standard.set(true,forKey:"nitecast.castDiscoveryExplained")
                DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { show() }
            })
            alert.addAction(UIAlertAction(title:"Cancel",style:.cancel) { [weak self] _ in self?.finishChoice(false) })
            guard var controller = webView?.window?.rootViewController else { finishChoice(false); return }
            while let presented = controller.presentedViewController { controller = presented }
            controller.present(alert,animated:true)
        }
        func loadPending() {
            guard let body = pendingLoad,
                  let raw = body["url"] as? String, let url = URL(string:raw), sameOrigin(url),
                  let remote = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient else { return }
            let info = GCKMediaInformationBuilder(contentURL:url)
            info.streamType = .buffered
            info.contentType = body["mime"] as? String ?? "video/mp4"
            let metadata = GCKMediaMetadata()
            metadata.setString(body["title"] as? String ?? "Nitecast",forKey:kGCKMetadataKeyTitle)
            info.metadata = metadata
            let tracks = (body["tracks"] as? [[String:Any]] ?? []).compactMap { item -> GCKMediaTrack? in
                guard let raw = item["url"] as? String, let trackURL = URL(string:raw), sameOrigin(trackURL),
                      trackURL.path.hasPrefix("/watch-text/"), let id = item["id"] as? Int else { return nil }
                return GCKMediaTrack(identifier:id+1,contentIdentifier:trackURL.absoluteString,contentType:"text/vtt",type:.text,textSubtype:.captions,name:item["label"] as? String,languageCode:item["language"] as? String,customData:nil)
            }
            info.mediaTracks = tracks
            let request = GCKMediaLoadRequestDataBuilder()
            request.mediaInformation = info.build()
            request.startTime = body["start"] as? Double ?? 0
            request.activeTrackIDs = (body["activeTracks"] as? [Int] ?? []).map { NSNumber(value:$0) }
            remote.loadMedia(with:request.build()).delegate = self
            loadedID = body["id"] as? String; expectedContentURL = url; pendingLoad = nil
        }
        func startTimer() {
            castDialogObserver = NotificationCenter.default.addObserver(forName:kGCKUICastDialogDidHideNotification,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.dialogClosedAt = Date() }
            }
            timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
        }
        func tick() {
            if navigationFailed { webView?.reload() }
            if pendingChoiceID != nil {
                let manager = GCKCastContext.sharedInstance().sessionManager
                if manager.currentCastSession?.connectionState == .connected { finishChoice(true) }
                else if Date().timeIntervalSince(choiceSince) > 45 { finishChoice(false) }
                else if let closed = dialogClosedAt, Date().timeIntervalSince(closed) > 1, manager.currentSession == nil { finishChoice(false) }
            }
            if pendingLoad != nil {
                if Date().timeIntervalSince(pendingSince) > 45 {
                    pendingLoad = nil
                    webView?.evaluateJavaScript("window.nitecastCastError('TV connection timed out. Retry to watch on this device.')",completionHandler:nil)
                } else { loadPending() }
            }
            if let id = loadedID, GCKCastContext.sharedInstance().sessionManager.currentCastSession == nil {
                if let bytes = try? JSONSerialization.data(withJSONObject:["id":id,"offline":true]), let json = String(data:bytes,encoding:.utf8) {
                    webView?.evaluateJavaScript("window.nitecastCastState(\(json))",completionHandler:nil)
                }
            }
            guard let id = loadedID,
                  let remote = GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient,
                  remote.mediaStatus?.mediaInformation?.contentURL == expectedContentURL else { return }
            let position = remote.approximateStreamPosition()
            let duration = remote.mediaStatus?.mediaInformation?.streamDuration ?? 0
            guard position.isFinite, duration.isFinite else { return }
            let data: [String:Any] = ["id":id,"casting":true,"position":position,"duration":duration]
            if let bytes = try? JSONSerialization.data(withJSONObject:data), let json = String(data:bytes,encoding:.utf8) {
                webView?.evaluateJavaScript("window.nitecastCastState(\(json))",completionHandler:nil)
            }
        }
        func request(_ request:GCKRequest,didFailWithError error:GCKError) {
            notify(error.localizedDescription)
            webView?.evaluateJavaScript("window.nitecastCastError('The TV could not play this video. Retry playback or reconnect Cast.')",completionHandler:nil)
        }
    }
}
