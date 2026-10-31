# LocalSend Personal

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
