# Nitecast 11 — family streaming update

## Start the update

1. Close the old Nitecast app first. Keep only one host instance running.
2. Open `Nitecast.exe` in the Nitecast-v11-phone-fit folder (or use the updated Start Nitecast launcher).
3. Create your owner account on the PC. Existing movies, folders, settings and HTTPS hosting are retained. The owner's first account inherits the old shared watch progress and My List.
4. Anyone can select **Create account** on the login page and register as a viewer without an invitation. Create the owner account on the host PC first. Optional invitation links still work once and expire after 24 hours.
5. Family members use the existing public HTTPS address and their own account. No additional router configuration or paid service is introduced.

The new Home page is the normal browsing interface. **Profile → Library & host tools** opens the existing PC library/hosting tools. Administration is restricted to localhost on the host PC, including when the owner signs in remotely.

## Accounts and profiles

- Normal login uses username and password. Anyone can create a viewer account from the login page.
- Profile names are unique ignoring case and Unicode compatibility differences. Usernames are also unique. Names support 2–32 characters.
- Upload, replace or remove a profile picture. Images are resized to 384×384 JPEG and their original metadata is removed.
- Continue Watching, watched status and My List belong to the account and synchronize across devices. A different account starts with its own history.
- Sessions last up to 180 days and are stored in HttpOnly, SameSite cookies; internet sessions also require Secure cookies. Passwords use salted PBKDF2-HMAC-SHA256 with 600,000 iterations. Password derivation happens at sign-in/password changes, not while streaming.
- Device revocation signs that device out and invalidates its playback links. It can sign into the same existing account again with valid credentials. Disabling an account prevents new sign-ins too.
- Password changes/reset invalidate previous device sessions. The PC admin can issue a single-use 15-minute reset link without seeing the password. Owner recovery is available on the PC login screen.

## Approved QR sign-in

In **Profile → Sign in another device**, create a temporary QR code. A recent password check is required. The code lasts two minutes.

Scanning only creates a pending request. The original device shows the requesting browser and IP address and must explicitly approve it. Only then can the requesting device claim a new account session. Requests are single-use and expire; canceling/signing out/revoking the original device removes its pending requests. QR links use fragments, which are removed from browser history before the sign-in request. No external location lookup is performed.

Legacy pairing codes are no longer accepted for public account login. Local legacy TV/browser-receiver connections remain available in host tools.

## Browsing and watching

- Responsive Home, Movies, Series, My List, search, genre/year filters, title pages, seasons and episode lists.
- Direct browser playback is the main action. Chromecast remains optional using Google's standard receiver; there is no paid custom receiver.
- Auto playback checks the actual source codecs. Compatible video is played directly; otherwise it copies video where possible and converts only required audio/video. Supported Apple devices can keep HEVC; casting uses the conservative compatible path.
- Preparation is shared between viewers requesting the same file, quality and audio choice. Finished results are reused across app restarts while the source fingerprint remains unchanged.
- New conversions expose temporary HLS segments so supported browsers/iPhones/Cast can start before the whole file is ready. Chrome uses the bundled hls.js component; Apple devices use native HLS. Resuming far into an unprepared file may still require waiting for that portion to be prepared.
- One conversion runs at a time, with bounded encoding threads. Intro analysis yields while preparation is active. No per-account stream quota has been added; the existing global eight-session safety cap remains.
- Prepared video storage defaults to 10 GB and is adjustable from 1–100 GB in Admin. Active playback files are preserved; unused prepared files are evicted first. Temporary HLS copies are removed after their last viewer stops; orphaned temporary output is cleaned at next startup. Originals are never changed.
- Embedded text subtitles and matching `.srt`/`.vtt` files beside a video are available automatically. Existing audio tracks can be selected. Preferred subtitle/audio language and quality are saved per account. Image-based subtitles require a separate OCR workflow and are not converted automatically.
- Subtitle downloading, generated subtitles/dubbing, offline downloads and adaptive bitrate switching remain future optional work.

## Manual playback buttons

**Skip intro** and **Next episode** never run automatically. No autoplay countdown is enabled.

Intro timings are per source episode. The background detector reads appropriately named chapters and looks for long, highly similar recurring audio near the beginning of related episodes. It deliberately leaves uncertain episodes without a button. It cannot guarantee detection for every series, short intro, changed theme, or unusual edit. Admin can inspect/correct/clear timings per episode and rerun detection.

Credits use labeled chapter metadata or admin-provided timings. There is no general visual end-credit detector in this release. If a credits marker is unavailable, the manual Next episode button still appears when the episode finishes. No next episode means no button.

The phone's buttons follow Cast playback position and send manual seek/load commands to the TV. Buttons do not appear as a custom Chromecast overlay. The new web player also displays them locally. TV/network loss shows a controlled reconnect state; it does not replay old commands or automatically advance.

## Admin and backups

The dashboard provides accounts, invitations/reset links, device revocation, active streams/stop controls, blocked IP addresses, recent security events, storage controls and marker corrections.

Public requests are bounded, sign-in attempts are throttled, proxy client addresses are taken only from the dedicated loopback proxy connection, and desktop routes are denied over the public listener and LAN viewer interface. IP blocking applies to remote traffic, including subsequent media requests. It does not stop a person changing IPs or prevent an ISP-level flood. Security events are bounded to 100 in memory and clear on restart; passwords, QR secrets and invitation secrets are not recorded.

Metadata backups are refreshed locally every 15 minutes, keeping seven daily ZIP files in `%USERPROFILE%\.castlist\backups`. Download a fresh backup from Admin. Backups include account password hashes, profiles and library/watch metadata; they exclude active sign-in tokens and pending invitations, and do not copy movie files. Keep a backup on a separate drive to protect against disk failure. To restore, close Nitecast and restore the ZIP's `playlists.json` and `avatars` into `.castlist`.

## iPhone update 1.2.1, build 6

`Nitecast-iPhone-Full-Update.zip` contains the complete project with files at the ZIP root, including `.github/workflows/build-iphone.yml`.

Update the existing GitHub project with all files, keep the hidden workflow folder, and run **Actions → Build iPhone App**. Install the resulting IPA with your existing iLoader procedure. If Actions shows the starter templates instead, the workflow file is missing: create `.github/workflows/build-iphone.yml` with the supplied file's contents.

The updated iPhone app displays the same responsive interface from the host, uses persistent system-managed WebKit cookie storage for remembered login, provides a native approved-QR scanner, and retains native Google Cast and AirPlay support. Existing 1.0/1.1 device pairing does not substitute for a new account login. Changing the host stays available in the native header.

This workspace runs on Windows: Swift syntax/project/workflow checks passed, but Xcode compilation, physical iPhone persistence, AirPlay and Chromecast playback have not been verified here. The GitHub macOS workflow compiles and runs the included XCTest suite before producing the IPA.

## Validation

The release was checked with isolated test data. Checks cover account/password/session behavior, separate cross-device progress and lists, unique profiles/avatars, QR approval/replay restrictions, revoked movie links, IP/origin/admin restrictions, manual marker behavior, subtitle extraction, real audio conversion, shared conversion reuse, byte-range playback, progressive segments becoming available before encoding finishes, and graceful host/TV loss. Desktop and phone-sized browser layouts and direct/progressive browser playback were inspected.

The Windows executable is built and smoke-tested separately. These checks are not a penetration-test certification or a guarantee of compatibility with every media file or TV.


### Player refinement (29 October)

The app uses its own rounded playback controls with play/pause, 10-second jumps, volume, a full-duration timeline, fullscreen, keyboard shortcuts (Space/K, arrows, M, F), and a floating quality/audio/subtitle/speed panel. Controls fade while watching and remain visible while paused or navigating by keyboard. Skip Intro and Next Episode remain manual.

Converted playback uses fragmented MP4 HLS with stereo AAC at 48 kHz for browser compatibility. Original files and Original mode preserve the source audio. Previously prepared outputs use a different cache key so incompatible older conversions are not reused. If early playback fails, the same conversion continues and the player automatically resumes from its saved position using the completed MP4. This fallback may require waiting for conversion to finish. Seeking during preparation is limited to the portion already prepared. Cast/AirPlay still use the existing receiver and native controls; this change customizes the app player.


### Windows casting correction

On the host PC, open a movie, click Cast to TV, and choose a TV from the desktop device list. Scan for TVs if it is missing. The PC uses its existing native TV connection and shares the prepared viewer stream over its LAN address, rather than asking the embedded browser to run Google’s sender UI or sending the TV a localhost URL. Your PC video continues while connecting and pauses only when the TV confirms playback. Failed connections leave local playback available; a disconnected TV returns playback to the PC. The TV picker also provides Watch on this PC instead. The host-only Cast API is blocked from the public website and LAN clients. Browser and iPhone senders retain their respective Cast paths. Physical TV playback still needs verification on the user’s TV.

Only a failed network request marks the host offline. A TV failure, rejected playback, or display update error gets its own message.


### iPhone fit update — 1.2.1 (build 6)

Update the PC host and rebuild/install the iPhone project to receive the full fix. The host serves the new responsive controls; the native app removes its duplicate header Cast button, disables accidental page zoom, and hides its utility toolbar during playback. Safari/browser users retain normal browser zoom; the native app uses a fixed viewport. Form fields use phone-friendly text sizes to avoid focus zoom.

There is one Cast button inside the player. It opens the native TV picker and starts discovery explicitly after the user requests it. A one-time explanation precedes iOS Local Network permission. Cancelled TV selection leaves local playback running. AirPlay is available under the player’s settings button, in a separate full-width row. The settings panel scrolls in short landscape viewports, and controls respect safe areas. Phone volume uses the hardware buttons.

Layout checks covered 320×568, 390×844 and 844×390, including AirPlay-visible emulation. Native Cast and AirPlay still require physical iPhone/TV testing. Windows cannot compile the iPhone app; use the included GitHub macOS workflow for Xcode compilation, XCTest and the IPA. Swift syntax, project and package checks pass locally.
