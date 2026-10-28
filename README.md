# Nitecast 10 / iPhone 1.1

This is the full update, not a patch. Keep the existing GitHub repository and workflow. Upload Nitecast/, NitecastTests/, project.yml and README.md from the extracted full project into the repository root, replacing matching files. Do not delete existing files first. The workflow at .github/workflows/build-iphone.yml is included if restoration is needed. Then run Actions > Build iPhone App, download the Sideloadly artifact, extract Nitecast.ipa, and install it with iLoader using the same Apple Account.

Close older Nitecast PC versions and run Nitecast-v10/Nitecast.exe. The window title says Nitecast 10. The iPhone Settings page says version 1.1. Both apps need updating for scan-to-connect.

## What changed

- Phone remote opens a single-use, three-minute pairing QR. Scanning inside the iPhone app connects immediately; there is no second PIN step. The PIN is a collapsed manual fallback. Pairings are stored in iPhone Keychain and reconnect without scanning again. QR images refresh while their PC dialog remains open.
- Remembered PC addresses can be selected in iPhone Settings. Local and HTTPS remote addresses are supported.
- Choosing a movie now offers Watch here / nearby TV or Control the home TV. The independent player does not change the shared home TV’s episode, pause state or volume.
- Native iPhone playback, AirPlay and local Google Cast controls. At a friend’s house, the phone discovers that house’s Cast receivers; the home PC supplies the movie over its configured HTTPS connection. The TV must be able to reach the movie address. A private home-LAN address cannot work from another house.
- Up to eight independent viewer sessions. Up to two compatibility preparations at once. Original quality bypasses conversion. Compatible mode copies supported video when possible and only remuxes/converts what is necessary; 720p/1080p modes are available. Unsupported original formats can still fail on a particular TV.
- Viewer history is stored separately per paired device. Devices controlling the shared home TV intentionally share that TV’s controls. Accounts and household profiles are not included.
- Preparing/queued progress, cancellation when a viewer closes playback, previous/next episode controls, retry and resume after host-session loss. The PC Remote access panel lists independent sessions and can stop them; Manage devices revokes pairings.
- One host/TV reconnection banner, retained interface, disabled unavailable controls and no replay of offline presses. The previous recovery fixes remain included.

## Remote access: one-time setup still required

No Tailscale or separately launched app is needed. The Windows executable includes Caddy, an internal HTTPS component. Remote hosting is disabled by default and has not been published on your network.

To enable direct hosting:

1. Confirm the internet provider supplies a publicly reachable address. A router model alone cannot confirm this; CGNAT can prevent incoming IPv4 traffic. Ask the provider for a public address if needed. Do not use DMZ.
2. Choose a public DNS hostname (a domain or a dynamic-DNS subdomain) and point it at the home internet address. Purchasing a server is unnecessary. Dynamic addresses require DNS updates, such as the router’s supported dynamic-DNS service.
3. Reserve a fixed LAN address for this PC in the router.
4. Forward TCP external 443 to that PC’s internal port 8782, and TCP external 80 to internal port 8781. Permit incoming traffic to these two ports through Windows Firewall. Do not forward desktop port 8765 or the loopback-only remote application port 8780.
5. In Nitecast 10 open Remote access, enter the hostname without https://, and enable HTTPS hosting. DNS and router rules must be correct before automatic certificate issuance can succeed.
6. Use Check HTTPS connection, then test the hostname from the iPhone on cellular data. A test from the same home Wi-Fi does not prove external reachability; the router may also require NAT loopback to use the public hostname while at home.
7. On the PC choose Phone remote > Remote QR. Scan that in the updated native iPhone app. It remembers the HTTPS host. At the friend’s house use that host and select Watch here / nearby TV.

Remote administration and folder scanning are not exposed by the public listener. Paired access is required for library/API requests; TV media uses revocable per-session capability links. Do not share a pairing QR or movie link publicly. Disabling remote access stops HTTPS hosting. Closing Nitecast stops its internal hosting component. The remote listener must not be placed behind an arbitrary proxy into the desktop port.

Router identified by the user: Icotera i4882-80. This model is supplied by Telenor; verify the actual internet provider before using provider-specific instructions. No router changes or public DNS configuration have been made by this update.

## Validation and remaining checks

Backend tests cover QR single use/expiry, concurrent claims, independent progress, cross-device control denial, media ranges and HEAD, revoked leases, remote loopback authorization and administration restrictions. Existing recovery, shared playback, device and pairing tests pass. Desktop/mobile JavaScript syntax and desktop reconnection simulation pass. Caddy configuration validates against the bundled executable. The final Windows executable is smoke-tested.

Swift syntax and project/plist packaging checks are local checks only. The native iPhone app and its added XCTest cases must still compile/run in GitHub’s Mac workflow. A physical iPhone, AirPlay, Chromecast and outside-home connection have not been tested here. Those are required before calling the remote setup verified.

References: https://caddyserver.com/docs/automatic-https and https://developers.google.com/cast/docs/ios_sender
