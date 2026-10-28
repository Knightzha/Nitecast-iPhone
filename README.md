## Graceful disconnection update 1.0.2 / PC v9

Use the full Nitecast-iPhone-Source.zip for this update. Upload the contents of its Nitecast-iPhone folder to your existing repository root, preserving the .github/workflows/build-iphone.yml workflow. Do not upload the outer folder. Run Build iPhone App and reinstall the resulting IPA with iLoader using the same Apple Account.

The desktop no longer opens blocking alerts for failed requests. It retains the library, shows one host/TV connection banner, rejects unavailable controls, and recovers on a successful status refresh. TV status checks for DLNA run in the background; an unreachable TV cannot block library polling. Controls pressed while offline are not replayed. A browser receiver re-registers after a host restart while authorized. The iPhone keeps its current library on connection loss, uses a single connection banner, and restores controls on recovery. Playback is not automatically restarted after a TV power loss; choose an episode/resume when ready.

Remote internet access and QR-only pairing are separate upcoming work, not included in this disconnection update.

## Connection update 1.0.1

Use this with Nitecast PC v8. Temporary refresh failures no longer immediately show offline. Cancelled background refreshes are ignored, status GETs retry once, artwork uses a separate connection pool, and phone commands run in order. Failed playback requests no longer navigate as if successful. Screen/settings dialogs stay open when saving fails.

The PC keeps the latest episode selection while preparing another video. Stop invalidates waiting selections and prevents a cancelled preparation from starting playback afterwards. Conversion already in progress finishes before a queued selection can prepare; this update does not forcibly terminate FFmpeg.

Update the existing GitHub repository with the contents of Nitecast-iPhone-Connection-Update.zip at the repository root. Keep Nitecast/ and NitecastTests/ as folders. Commit, run Actions > Build iPhone App, download Nitecast-iPhone-Sideloadly, and install the resulting Nitecast.ipa through iLoader using the same Apple Account. Keep the old phone app installed during the update to preserve its local settings where signing permits.

Validation: five PC playback regression tests and five existing phone HTTP API tests pass. Swift syntax and packaging checks pass. The new XCTest and the updated app still require the GitHub Mac build; a real iPhone/TV connection test has not been run here.

# Nitecast for iPhone

A native SwiftUI companion for Nitecast on Windows. Includes library posters and banners, search and My list, show seasons and episodes, resume/watched controls, TV selection, pause/seek/volume/stop, sleep timer, TV + PC settings, QR-code pairing and secure pairing storage in iPhone Keychain.

This is **source code and a cloud build workflow**, not an installable IPA yet. Windows cannot run Apple's iOS compiler. The included GitHub Actions workflow builds and tests on a Mac runner, then produces **Nitecast.ipa** for Sideloadly. No Apple signing certificate or Apple account credentials are needed in GitHub. Sideloadly signs the downloaded IPA on your Windows PC.

Minimum iOS: **17.0**. Works with Nitecast PC v7. The app connects directly to the PC over your home network; it contains no browser wrapper. The PC handles TV discovery and video delivery.

## 1. Upload this project to GitHub

1. Sign in at https://github.com.
2. Choose **New repository**. Name it **Nitecast-iPhone**. Choose **Private** and enable **Add a README file**, then create it.
3. Extract the downloaded **Nitecast-iPhone-Source.zip** on your PC.
4. On the repository page, choose **Add file → Upload files**.
5. Open the extracted **Nitecast-iPhone** folder. Drag its **contents** into GitHub: `.github`, `Nitecast`, `NitecastTests`, `project.yml`, `.gitignore` and `README.md`. Do not upload the outer folder or ZIP as one file. Replace the initial README with the supplied one.
6. Choose **Commit changes**. If GitHub proposes a branch choice, commit to the default branch.

The workflow must be located at **.github/workflows/build-iphone.yml** at the repository root. `project.yml` must also be at the root. If you do not see the workflow under Actions, check that you uploaded the folder contents rather than the outer project folder. You can use GitHub's **Add file → Create new file** with the exact workflow path if the browser missed the `.github` directory.

## 2. Build the IPA

1. Open the repository's **Actions** tab.
2. Choose **Build iPhone App**.
3. Choose **Run workflow → Run workflow**.
4. Open that run and wait for it to finish successfully. It generates the Xcode project, builds/tests on an iPhone simulator, then builds the device app.
5. Under **Artifacts**, download **Nitecast-iPhone-Sideloadly**.
6. Extract that download. It contains **Nitecast.ipa**.

The workflow runs only when you start it. Check your GitHub account's Actions allowance/billing before running Mac jobs; free capacity depends on the account and repository. Do not add payment details or signing secrets merely to follow this guide. If GitHub says the run cannot start because of allowance or billing, share that message so another build route can be considered.

If the build fails, open the failed step and copy its error text. **Do not try to install this source ZIP with Sideloadly.** Only the resulting `.ipa` can be installed.

## 3. Install with Sideloadly on Windows

1. Connect/unlock the iPhone and trust the PC if prompted.
2. Open Sideloadly and select your iPhone.
3. Drag **Nitecast.ipa** onto the IPA icon.
4. Enter your Apple Account email and choose **Start**. Enter your password and verification code directly into Sideloadly when requested.
5. If iOS asks, trust the developer under **Settings → General → VPN & Device Management**, and enable **Settings → Privacy & Security → Developer Mode** if required. Follow the device's prompts.

Free Apple ID sideloads typically require periodic refresh; use Sideloadly's documented refresh flow. Do not post your password, verification codes or signing credentials in chat or GitHub.

## 4. Pair with your Nitecast PC

1. Leave Nitecast v7 running on the Windows PC. Keep the PC awake and use the same home network on the iPhone.
2. In the PC app, open **Phone remote**.
3. Open Nitecast on the iPhone and choose **Scan PC's QR code**. Alternatively, type the PC address shown in that panel.
4. Allow **Camera** if scanning, and **Local Network** when asked.
5. Enter the six-digit pairing code shown on the PC, then choose **Connect to my PC**.
6. Choose your TV from the screen picker, browse your library and press Watch.

The QR is used to obtain the PC address, not the pairing secret. A persistent pairing token is stored in iPhone Keychain. The address is saved in local preferences. Media images are kept in a bounded memory cache. Forgetting the PC removes its saved token and revokes it on the server if the PC is reachable.

If `.local` doesn't resolve, use the numeric LAN address from the PC. The app accepts local-network addresses only. Check Local Network access in iPhone Settings if it cannot connect. New Nitecast folders and artwork appear automatically from the existing PC library.

## Current scope

- Native iPhone/iPad interface, local network pairing and remote controls.
- Videos play on a TV or another PC-managed screen. This first version does **not** play movies on the iPhone, download movies offline, wake/shut down the PC, or add background/lock-screen controls.
- TV + PC synchronization follows the PC app's existing implementation and limits.
- No personal library data, PC addresses, pairing codes or tokens are included in this project.

## Validation status

Swift syntax, project/workflow structure and the native client's HTTP contract are checked from Windows. **Xcode compilation, XCTest execution, simulator rendering and real iPhone installation still require the cloud Mac build and device testing.** Do not interpret a prepared project ZIP as a successfully compiled or signed app.

## References

- GitHub artifacts: https://docs.github.com/en/actions/tutorials/store-and-share-data
- Sideloadly: https://sideloadly.io/
- Apple local network access: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
