import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var client: NitecastClient
    @State private var tab = 0
    var body: some View {
        Group {
            if client.isPaired {
                TabView(selection:$tab) {
                    NavigationStack { HomeView(tab:$tab) }.tabItem { Label("Home",systemImage:"house.fill") }.tag(0)
                    NavigationStack { LibraryView(tab:$tab) }.tabItem { Label("Library",systemImage:"rectangle.stack.fill") }.tag(1)
                    NavigationStack { RemoteView() }.tabItem { Label("Remote",systemImage:"appletvremote.gen4.fill") }.tag(2)
                    NavigationStack { SettingsView() }.tabItem { Label("Settings",systemImage:"gearshape.fill") }.tag(3)
                }
                .safeAreaInset(edge:.top, spacing:0) {
                    if !client.isOnline {
                        Text("Reconnecting to your PC… Keep Nitecast running on the same network.")
                            .font(.caption).frame(maxWidth:.infinity).padding(10).background(.orange.opacity(0.2))
                    }
                }
                .safeAreaInset(edge:.bottom) {
                    if client.currentCollection != nil && tab != 2 {
                        HStack {
                            Button { tab = 2 } label: {
                                VStack(alignment:.leading,spacing:4) {
                                    Text(client.currentItem?.title ?? "Now playing").font(.subheadline.bold()).lineLimit(1)
                                    Text(client.state?.device ?? "Playback screen").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }.buttonStyle(.plain)
                            Button { Task { await client.command("ctl",["action":"toggle"]) } } label: {
                                Image(systemName:client.state?.now.state == "PLAYING" ? "pause.fill" : "play.fill").padding(12)
                            }.accessibilityLabel("Play or pause")
                        }.padding(12).background(Color.cinemaPanel,in:RoundedRectangle(cornerRadius:16)).padding(.horizontal)
                    }
                }
            } else { PairView() }
        }
        .sheet(isPresented:$client.showScreens) { ScreenPicker() }
        .alert("Nitecast",isPresented:Binding(get:{ client.error != nil },set:{ if !$0 { client.error = nil } })) {
            Button("OK",role:.cancel) { client.error = nil }
        } message: { Text(client.error ?? "") }
    }
}

struct Brand: View {
    var body: some View {
        HStack(spacing:5) {
            Image("Brand").resizable().scaledToFit().frame(width:35,height:35)
            Text("Nitecast").font(.title2.weight(.heavy)).tracking(-1)
        }
    }
}

struct PairView: View {
    @EnvironmentObject private var client: NitecastClient
    @State private var address = ""
    @State private var pin = ""
    @State private var scanner = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Image("Brand").resizable().scaledToFit().frame(width:100,height:100)
                    Text("Your collection.\nAny screen.").font(.system(size:38,weight:.bold)).tracking(-1.5)
                    Text("Open Nitecast on your PC, then choose Phone remote. Connect your iPhone to the same home Wi-Fi.")
                        .foregroundStyle(.secondary)
                    Button { scanner = true } label: { Label("Scan PC’s QR code",systemImage:"qrcode.viewfinder").frame(maxWidth:.infinity).padding(8) }
                        .buttonStyle(.borderedProminent)
                    VStack(alignment:.leading,spacing:10) {
                        Text("PC address").font(.caption).foregroundStyle(.secondary)
                        TextField("192.168.1.20:8765",text:$address).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL).padding().background(Color.cinemaPanel,in:RoundedRectangle(cornerRadius:12))
                        Text("Pairing code shown on your PC").font(.caption).foregroundStyle(.secondary)
                        TextField("6-digit code",text:$pin).keyboardType(.numberPad).textContentType(.oneTimeCode)
                            .font(.title2.monospacedDigit()).padding().background(Color.cinemaPanel,in:RoundedRectangle(cornerRadius:12))
                            .onChange(of:pin) { _,new in pin = String(new.filter { $0.isASCII && $0.isNumber }.prefix(6)) }
                    }
                    Button { Task { await client.pair(address:address,pin:pin); pin = "" } } label: {
                        HStack { if client.isBusy { ProgressView().tint(.black) }; Text(client.isBusy ? "Connecting…" : "Connect to my PC") }
                            .frame(maxWidth:.infinity).padding(10)
                    }.buttonStyle(.borderedProminent).disabled(client.isBusy || pin.count != 6 || address.isEmpty)
                    Text("Allow Camera to scan the QR code and Local Network to connect to your PC. Your pairing is remembered securely on this iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(28)
            }.background(Color.cinema).scrollDismissesKeyboard(.interactively)
                .onAppear { if address.isEmpty { address = client.server?.absoluteString ?? "" } }
                .sheet(isPresented:$scanner) {
                    QRScanner { value in
                        do { address = try ServerAddress.normalize(value).absoluteString; scanner = false }
                        catch { client.error = error.localizedDescription; scanner = false }
                    }
                }
        }
    }
}

struct Artwork: View {
    @EnvironmentObject private var client: NitecastClient
    let path: String
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors:[.nitecast.opacity(0.3),.cinemaPanel],startPoint:.topLeading,endPoint:.bottomTrailing)
                if let image { Image(uiImage:image).resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.height).clipped() }
                else { Image(systemName:"film").font(.largeTitle).foregroundStyle(.white.opacity(0.3)) }
            }
        }.clipped().task(id:(client.server?.absoluteString ?? "")+path) { image = await client.image(path:path) }
    }
}

struct PosterCard: View {
    @EnvironmentObject private var client: NitecastClient
    let collection: MediaCollection
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Artwork(path:client.artworkPath(collection)).aspectRatio(2/3,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:12))
            Text(collection.name).font(.subheadline.bold()).lineLimit(1)
            Text(collection.subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var client: NitecastClient
    @Binding var tab: Int
    private var continuing: [MediaCollection] { (client.state?.playlists ?? []).filter(\.hasProgress) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("TONIGHT IS YOURS").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Color.nitecast)
                if let featured = continuing.first ?? client.state?.playlists.last {
                    ZStack(alignment:.bottomLeading) {
                        Artwork(path:client.artworkPath(featured,banner:true))
                        LinearGradient(colors:[.clear,.black.opacity(0.95)],startPoint:.top,endPoint:.bottom)
                        VStack(alignment:.leading,spacing:12) {
                            Text(featured.name).font(.largeTitle.bold()).lineLimit(3)
                            Text(featured.hasProgress ? "Pick up where you left off" : featured.subtitle).font(.subheadline).foregroundStyle(.secondary)
                            HStack {
                                Button { Task { if await client.play(featured,index:featured.resumeIndex) { tab = 2 } } } label: {
                                    Label(featured.hasProgress ? "Continue" : "Watch",systemImage:"play.fill")
                                }.buttonStyle(.borderedProminent).disabled(featured.items.isEmpty)
                                NavigationLink { CollectionView(id:featured.id,tab:$tab) } label: { Text("Details") }.buttonStyle(.bordered)
                            }
                        }.padding(22)
                    }.frame(height:360).clipShape(RoundedRectangle(cornerRadius:22))
                    shelf("Continue watching",continuing)
                    shelf("Recently added",Array((client.state?.playlists ?? []).reversed()))
                    shelf("My list",(client.state?.playlists ?? []).filter { $0.favorite ?? false })
                } else {
                    ContentUnavailableView("Your library starts on your PC",systemImage:"film.stack",description:Text("Add your movie and show folders in Nitecast on the computer."))
                }
            }.padding(20)
        }.background(Color.cinema).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarLeading) { Brand() }; ToolbarItem(placement:.topBarTrailing) { screenButton } }
            .refreshable { await client.refresh() }
    }
    private var screenButton: some View {
        Button { client.showScreens = true } label: { Image(systemName:"tv") }.accessibilityLabel("Choose playback screen")
    }
    @ViewBuilder private func shelf(_ name: String,_ list: [MediaCollection]) -> some View {
        if !list.isEmpty {
            VStack(alignment:.leading,spacing:12) {
                Text(name).font(.title3.bold())
                ScrollView(.horizontal,showsIndicators:false) {
                    LazyHStack(alignment:.top,spacing:14) {
                        ForEach(list) { p in NavigationLink { CollectionView(id:p.id,tab:$tab) } label: { PosterCard(collection:p).frame(width:135) }.buttonStyle(.plain) }
                    }
                }
            }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var client: NitecastClient
    @Binding var tab: Int
    @State private var query = ""
    @State private var filter = "All"
    private var filtered: [MediaCollection] {
        (client.state?.playlists ?? []).filter { p in
            (filter == "All" || filter == "Movies" && !p.isSeries || filter == "Series" && p.isSeries || filter == "My list" && (p.favorite ?? false)) &&
            (query.isEmpty || (p.name+" "+(p.genres ?? []).joined(separator:" ")+" "+p.items.map(\.title).joined(separator:" ")).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        ScrollView {
            Picker("Filter",selection:$filter) { ForEach(["All","Movies","Series","My list"],id:\.self) { Text($0) } }.pickerStyle(.segmented).padding(.bottom,18)
            if filtered.isEmpty { ContentUnavailableView.search(text:query) }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:135),spacing:16)],alignment:.leading,spacing:24) {
                ForEach(filtered) { p in NavigationLink { CollectionView(id:p.id,tab:$tab) } label: { PosterCard(collection:p) }.buttonStyle(.plain) }
            }
        }.padding(.horizontal,20).background(Color.cinema).navigationTitle("Your library")
            .searchable(text:$query,prompt:"Find a movie or show").refreshable { await client.refresh() }
    }
}

struct CollectionView: View {
    @EnvironmentObject private var client: NitecastClient
    let id: String
    @Binding var tab: Int
    @State private var season = 1
    private var collection: MediaCollection? { client.state?.playlists.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let p = collection {
                VStack(alignment:.leading,spacing:20) {
                    Artwork(path:client.artworkPath(p,banner:true)).frame(height:220).clipShape(RoundedRectangle(cornerRadius:18))
                    Text(p.name).font(.largeTitle.bold())
                    Text(p.isSeries ? "Series · \(p.items.count) episodes" : "Movie · \(p.items.count) file\(p.items.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                    HStack {
                        Button { Task { if await client.play(p,index:p.resumeIndex) { tab = 2 } } } label: { Label(p.hasProgress ? "Continue" : "Watch",systemImage:"play.fill") }
                            .buttonStyle(.borderedProminent).disabled(p.items.isEmpty)
                        Button { Task { await client.command("library",["id":p.id,"favorite":!(p.favorite ?? false)]) } } label: {
                            Label("My list",systemImage:(p.favorite ?? false) ? "checkmark" : "plus")
                        }.buttonStyle(.bordered)
                    }
                    if let description = p.description, !description.isEmpty { Text(description).font(.subheadline).foregroundStyle(.secondary) }
                    if p.isSeries {
                        Picker("Season",selection:$season) {
                            ForEach(p.seasons,id:\.self) { n in Text(n == 0 ? "Specials" : "Season \(n)").tag(n) }
                        }.pickerStyle(.menu).tint(.nitecast)
                    }
                    ForEach(p.items.indices.filter { !p.isSeries || (p.items[$0].season ?? 1) == season },id:\.self) { index in
                        let item = p.items[index]
                        VStack(alignment:.leading,spacing:12) {
                            Button { Task { if await client.play(p,index:index) { tab = 2 } } } label: {
                                HStack {
                                    VStack(alignment:.leading,spacing:6) {
                                        Text(item.title).font(.headline)
                                        Text(item.missing ?? false ? "Source unavailable" : item.watched ?? false ? "Watched" : (item.position ?? 0) > 10 ? "Resume at \(playbackTime(item.position ?? 0))" : "Not watched")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                    Image(systemName:"play.circle.fill").font(.title).foregroundStyle(Color.nitecast)
                                }
                            }.buttonStyle(.plain).disabled(item.missing ?? false)
                            if let duration = item.duration, duration > 0 { ProgressView(value:item.watched ?? false ? duration : min(item.position ?? 0,duration),total:duration) }
                            HStack {
                                Button("Start over") { Task { if await client.play(p,index:index,restart:true) { tab = 2 } } }
                                Spacer()
                                Button(item.watched ?? false ? "Mark unwatched" : "Mark watched") {
                                    Task { await client.command("watched",["id":p.id,"i":index,"watched":!(item.watched ?? false)]) }
                                }
                            }.font(.caption).buttonStyle(.bordered)
                        }.padding(16).background(Color.cinemaPanel,in:RoundedRectangle(cornerRadius:15))
                    }
                }.padding(20)
                    .onAppear { season = p.items.indices.contains(p.resumeIndex) ? p.items[p.resumeIndex].season ?? 1 : 1 }
            }
        }.background(Color.cinema).navigationBarTitleDisplayMode(.inline)
    }
}

struct RemoteView: View {
    @EnvironmentObject private var client: NitecastClient
    @State private var position = 0.0
    @State private var volume = 0.5
    @State private var editingSeek = false
    @State private var editingVolume = false
    @State private var sleepSheet = false
    private var live: Bool { client.currentCollection != nil }
    var body: some View {
        ScrollView {
            VStack(spacing:24) {
                Button { client.showScreens = true } label: { Label(client.state?.device ?? "Choose playback screen",systemImage:"tv").lineLimit(1).frame(maxWidth:.infinity) }.buttonStyle(.bordered)
                VStack(spacing:22) {
                    Text(client.state?.now.state.isEmpty == false ? client.state!.now.state.capitalized : "Ready when you are")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.nitecast)
                    Text(client.currentItem?.title ?? "Nothing playing yet").font(.title.bold()).multilineTextAlignment(.center)
                    if let p = client.currentCollection { Text(p.name).font(.subheadline).foregroundStyle(.secondary) }
                    Slider(value:$position,in:0...max(1,client.state?.now.dur ?? 1),onEditingChanged:{ editing in
                        editingSeek = editing
                        if !editing { Task { await client.command("ctl",["action":"seek","value":position]) } }
                    }).disabled(!live)
                    HStack { Text(playbackTime(position)); Spacer(); Text(playbackTime(client.state?.now.dur ?? 0)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    HStack(spacing:35) {
                        control("backward.end.fill","Previous episode",action:"prev")
                        Button { Task { await client.command("ctl",["action":"toggle"]) } } label: {
                            Image(systemName:client.state?.now.state == "PLAYING" ? "pause.fill" : "play.fill")
                                .font(.system(size:30)).foregroundStyle(.black).frame(width:80,height:80).background(Color.nitecast,in:Circle())
                        }.disabled(!live).accessibilityLabel("Play or pause")
                        control("forward.end.fill","Next episode",action:"next")
                    }
                    HStack(spacing:35) {
                        Button { seek(-15) } label: { Label("15 sec",systemImage:"gobackward.15") }
                        Button { seek(15) } label: { Label("15 sec",systemImage:"goforward.15") }
                    }.buttonStyle(.bordered).disabled(!live)
                    HStack {
                        Image(systemName:"speaker.wave.2.fill")
                        Slider(value:$volume,in:0...1,onEditingChanged:{ editing in
                            editingVolume = editing
                            if !editing { Task { await client.command("ctl",["action":"vol","value":volume]) } }
                        }).disabled(!live || client.state?.now.vol == nil)
                    }
                    Text(client.state?.now.vol == nil ? "Use your playback screen’s own volume controls." : client.state?.dual?.enabled == true && client.state?.dual?.audio == "pc" ? "PC speakers / headphones · TV muted" : "Playback volume")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24).background(LinearGradient(colors:[.nitecast.opacity(0.18),.cinemaPanel],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:24))
                HStack {
                    Button { sleepSheet = true } label: { Label("Sleep timer",systemImage:"moon.zzz") }.buttonStyle(.bordered)
                    Button("Stop",role:.destructive) { Task { await client.command("ctl",["action":"stop"]) } }.buttonStyle(.bordered).disabled(!live)
                }
                if let remaining = client.state?.now.sleep, remaining > 0 { Text("Stops in \(Int(ceil(Double(remaining)/60))) minutes").font(.caption).foregroundStyle(.secondary) }
                if client.state?.now.eoe == true { Text("Stops after this episode").font(.caption).foregroundStyle(.secondary) }
                if let job = client.state?.job, job.active {
                    VStack(alignment:.leading,spacing:8) {
                        Text(job.title ?? "Preparing video").font(.headline)
                        Text(job.stage ?? "Preparing").font(.caption)
                        ProgressView(value:job.percent ?? 0,total:100)
                    }.padding().background(Color.cinemaPanel,in:RoundedRectangle(cornerRadius:15))
                }
                if let error = client.state?.now.error, !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.orange) }
            }.padding(20)
        }.background(Color.cinema).navigationTitle("The remote")
            .onAppear { syncSliders() }
            .onChange(of:client.state?.now.t) { _,_ in syncSliders() }
            .onChange(of:client.state?.now.vol) { _,_ in syncSliders() }
            .confirmationDialog("Sleep timer",isPresented:$sleepSheet,titleVisibility:.visible) {
                ForEach([0,15,30,60],id:\.self) { minutes in
                    Button(minutes == 0 ? "Off" : "\(minutes) minutes") { Task { await client.command("ctl",["action":"sleep","value":minutes]) } }
                }
                Button("End of episode") { Task { await client.command("ctl",["action":"sleep","value":"eoe"]) } }
            } message: { Text("Stops playback; your PC stays on.") }
    }
    private func syncSliders() {
        if !editingSeek { position = max(0,min(client.state?.now.t ?? 0,max(1,client.state?.now.dur ?? 1))) }
        if !editingVolume { volume = client.state?.now.vol ?? 0.5 }
    }
    private func seek(_ delta: Double) {
        Task { await client.command("ctl",["action":"seek","value":max(0,min((client.state?.now.t ?? 0)+delta,client.state?.now.dur ?? .greatestFiniteMagnitude))]) }
    }
    private func control(_ icon: String,_ label: String,action: String) -> some View {
        Button { Task { await client.command("ctl",["action":action]) } } label: { Image(systemName:icon).font(.title2) }.disabled(!live).accessibilityLabel(label)
    }
}

struct ScreenPicker: View {
    @EnvironmentObject private var client: NitecastClient
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Available playback screens") {
                    ForEach(client.state?.devices ?? [],id:\.self) { device in
                        Button { Task { await client.command("device",["name":device]); dismiss() } } label: {
                            HStack { Text(device); Spacer(); if device == client.state?.device { Image(systemName:"checkmark") } }
                        }
                    }
                    if client.state?.devices.isEmpty != false { Text("No screens found. Turn on your TV and scan again.").foregroundStyle(.secondary) }
                }
                Button { Task { await client.command("scan",[:]) } } label: { Label(client.state?.scanning == true ? "Scanning…" : "Scan for TVs",systemImage:"arrow.clockwise") }
                    .disabled(client.state?.scanning == true)
                Section { Text("Your PC discovers and streams to the TV. Keep the PC, iPhone and TV on the same home network.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Choose a screen").toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium,.large])
    }
}

struct SettingsView: View {
    @EnvironmentObject private var client: NitecastClient
    @State private var disconnect = false
    @State private var dual = false
    var body: some View {
        Form {
            Section("Connected PC") {
                Text(client.server?.absoluteString ?? "Not connected").font(.footnote).textSelection(.enabled)
                Label(client.isOnline ? "Connected" : "Reconnecting",systemImage:client.isOnline ? "checkmark.circle.fill" : "wifi.exclamationmark")
                    .foregroundStyle(client.isOnline ? .green : .orange)
                Button("Reconnect now") { Task { await client.refresh() } }
            }
            Section("Playback") {
                Button("Choose TV / playback screen") { client.showScreens = true }
                Button("TV + PC player") { dual = true }.disabled(client.state?.dual == nil)
            }
            Section("Pairing") {
                Text("Your pairing is stored in iPhone Keychain. Your PC must stay awake with Nitecast running.").font(.footnote).foregroundStyle(.secondary)
                Button("Forget this PC",role:.destructive) { disconnect = true }
            }
            Section("About") {
                Brand()
                Text("Native iPhone companion · Version 1.0").font(.footnote).foregroundStyle(.secondary)
                Text("Movies remain on your PC. This app controls playback on a TV or another connected screen. Phone video playback, offline downloads and PC shutdown are not included in this first version.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Settings")
            .confirmationDialog("Forget this PC?",isPresented:$disconnect,titleVisibility:.visible) {
                Button("Forget PC",role:.destructive) { Task { await client.forget() } }
            } message: { Text("You’ll need its pairing code to reconnect. Your library and watch progress stay on the PC.") }
            .sheet(isPresented:$dual) { DualScreenSettings() }
    }
}

struct DualScreenSettings: View {
    @EnvironmentObject private var client: NitecastClient
    @Environment(\.dismiss) private var dismiss
    @State private var enabled = false
    @State private var audio = "pc"
    @State private var offset = 0.0
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Play on TV and PC together",isOn:$enabled)
                Picker("Sound output",selection:$audio) { Text("PC speakers / headphones").tag("pc"); Text("TV").tag("tv") }
                Section("TV timing adjustment") {
                    Slider(value:$offset,in:-3000...3000,step:100)
                    Text("\(Int(offset)) milliseconds").monospacedDigit()
                    Text("Positive values move the TV ahead. This provides approximate synchronization.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("A separate Nitecast Player window opens on the PC for Discord sharing. The other sound output is muted. Saving during playback reloads the video from its saved position.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("TV + PC player")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) { Button("Save") { Task { await client.command("dual",["enabled":enabled,"audio":audio,"offset":offset]); dismiss() } } }
                }
                .onAppear { if let value = client.state?.dual { enabled = value.enabled; audio = value.audio; offset = value.offset } }
        }
    }
}
