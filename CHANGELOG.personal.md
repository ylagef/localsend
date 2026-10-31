# LocalSend Personal

## 1.19.0 (2026-11-01)

### Android background reception

- Receive incoming requests as notifications with Receive and Decline actions.
- Keep receiving after removing LocalSend from recent apps, with a persistent local-network listening notification.
- Preserve the networking engine and sessions when reopening the screen. Stop receiving closes the taskless service and network listeners.
- Preserve existing encryption, PIN and explicit acceptance preferences; background reception does not enable automatic acceptance.
- Document LocalSend as the delivery channel for files sent to the owner's Pixel, including APKs.

### Downloads and verification

- `LocalSend-Personal-android-arm64.apk`: the verified retained Android APK, runtime **1.18.3**, versionCode **202610393**, signed with the retained personal key. It can update earlier personal APKs without uninstalling them.
- Fork publication version **1.19.0** is separate from the retained APK runtime version; the tested APK was not rebuilt or renumbered for publication.
- Exact committed source, sanitized release provenance and SHA-256 checksums are included. This release adds Android assets; the macOS binary remains in release 1.18.3.
- 151 Flutter tests passed with 6 platform-specific skips. Android 17 API 37 release-emulator tests verified task removal, notification receipt and saved file hash, explicit stop and reopening. Retained APK signing and identity were verified again before packaging.
- Force stop, Android Active apps Stop, process eviction and reboot can end reception; reopen the app afterwards. Physical Pixel hardware, real Wi-Fi Doze and official desktop-sender interoperability were not verified in this audit.

Enable **Settings → General → Receive in background** and allow notifications and local-network access. For screen-off reception, set battery use to Unrestricted.

## 1.18.3 (2026-10-31)

First public release of the personal macOS fork, based on upstream commit `92e133aa43869e94d394fd04fa70c50a0f796a64`.

### Features

- Copy received image content directly from completed transfers and receive history.
- Custom floating receive cards with Receive/Decline and Copy image/Open quick actions.
- Image thumbnails, copy confirmation, error feedback and retry, with light/dark appearance.
- Separate LocalSend Personal app identity and preferences; standard LocalSend discovery compatibility.

### Downloads and verification

- `LocalSend-Personal-macos-arm64.zip`: the exact locally built and user-tested app, runtime **1.18.2**, build **2026103103**. The fork release/package version **1.18.3** is independent of that runtime version; the accepted app was not rebuilt or renumbered.
- Apple Silicon, macOS 12 or later. Ad-hoc signed, **not notarized**. No Intel, Windows, Linux, Android, iOS or store binaries are included.
- Source archive, sanitized release provenance and SHA-256 checksums are included.
- 123 application tests and native clipboard/card smoke tests passed. Release integrity tests cover source drift, bundle tampering, symlinks and ZIP permissions. The installed image-copy and floating-alert flows were confirmed by the user.

Enable **Settings → General → Floating receive alerts**. Closing the window keeps the app in the menu bar; quitting stops receipt. Custom cards do not enter Notification Center or inherit Focus suppression. Quit official LocalSend before opening Personal because both use the standard discovery port.

### Development history

- Build 2026103101 introduced received-image clipboard actions.
- Build 2026103102 added the intermediate system-notification backend.
- Build 2026103103 replaced it with custom floating cards and quick actions.

Upstream release notes remain in `app/assets/CHANGELOG.md`.
