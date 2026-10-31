# Custom receive alerts

Historical local build/install record. The subsequent public fork release is documented in `RELEASING.md`; the original build source was uncommitted at compilation time and is verified against the release commit during packaging.

This patch replaces build 2026103102 system banners with a custom macOS card, designed with Claude Opus 5.5 Medium (Fast disabled). The persisted opt-in remains the same. In Settings → General, enable **Floating receive alerts** / **Avisos flotantes al recibir**. Closing the window then keeps Personal running in the menu bar; quitting still stops receipt. The setting does not enable login startup.

A manual request offers Receive/Decline. Acceptance uses the selected files and existing server policies; the request must still be the same waiting session. Closing only the card leaves the request available in the main app. Completed single images offer Copy image/Open, and other completed transfers offer Open/View transfer. Paths are held in a bounded trusted completion registry independent of saved history. Stale request actions cannot decide a replacement session.

The card uses a nonactivating AppKit panel. It does not enter Notification Center, inherit Focus rules, or persist after the app quits. The system permission prompt is removed. These are intentional differences from Apple's system notifications. See `CUSTOM_ALERT_DESIGN.md` for the design and authoritative references.

## Verification boundary

Native view fixtures use synthetic data and actual production AppKit views rendered offscreen. They do not capture the user's desktop, display a panel, open received files, or modify the general clipboard. Native clipboard smoke tests use private pasteboards. Flutter tests use mocked native channels. Actual arrival, focus behavior, Spaces/fullscreen placement, timed dismissal/hover, VoiceOver, and a complete Pixel-to-Mac transfer require live human acceptance; no computer-use approval mechanism is available in this session.

Build/check/review/install evidence will be recorded below after completion. Previous binaries and exact installed bytes are retained for rollback. Source remains uncommitted; no publication is authorized.

## Build and checks

- Prepared version 1.18.2, build 2026103103, bundle `dev.ylagef.localsendPersonal`, ad-hoc signed (not notarized).
- Executable SHA-256: `94f473300c71c46c8164b74a83224c4697bf0615a0547cae2f09497ceb8bf259`.
- Source/artifact manifest: `artifacts/provenance/manifest.json` (163 files and 81 symlinks). Source hashes matched the working files immediately after final compilation.
- `flutter analyze`: passed, no issues. Full application suite: 123 passed after functional fixes; final subsequent edit adds braces only to satisfy the lint. The focused quick-action/setting/navigation suite also passed 19 tests.
- Native card smoke: payload validation, local target/action dispatch, duplicate prevention, failure/retry, stale view result, dismissal without decision, and nil/expired/future retry deadlines passed. No window was shown.
- Native private-pasteboard smoke: PNG/JPEG content, alpha/pixels, missing/invalid paths, and source deletion passed. No general pasteboard changes.
- Native fixtures: actual AppKit view renders; Opus accepted light/dark localized pending/done/copied cards, English error/long-name cards, and actual Flutter setting at wide/compact widths. Spanish error/long-name and setting captures were not part of visual acceptance.
- Release configuration and whitespace checks passed.

## Independent review

Claude Sonnet 5.5 High confirmed five issues: stale quicksave closure, orphan cards on server stop, stale receiving cards after foregrounding, short retry deadline after failures, and rejecting beneath an options page. All five were fixed and verified by the single follow-up; no confirmed finding was rejected. The follow-up's brace-style observation was fixed, followed by a clean analyze and a fresh build. Claude Opus 5.5 Medium (Fast disabled) designed the card and separately accepted final screenshots.

A complete Xcode build caught a main-actor isolation error in the initial lazy controller setup; corrected with main-actor controller storage/access and subsequent builds passed. An offscreen rendering attempt rejected an incorrect translation-dictionary cast; corrected and fixtures regenerated successfully. These failed attempts did not replace the installed application.

Automated coverage does not include direct Dart receive-controller/session lifecycle or stopServer integration tests, actual panel stacking/expiry/focus/Spaces behavior, opening files in another app, VoiceOver, or real Pixel transfers. Rust/network policy and other platforms were unchanged and not retested here.

## Installation status

Installed `/Applications/LocalSend Personal.app`, build 2026103103, after the user confirmed quitting Personal. Preflight and installation verified 163 file hashes, 81 symlink targets and the deep strict code signature against the retained manifests. The installer did not launch the app or modify preferences/data. The exact prior installation is backed up at `artifacts/deliveries/2026103102/installed-app-before-upgrade.app`; the prior delivered build and provenance are in the same directory. Receipt: `artifacts/provenance/install.json`.

Evidence and complete check/review logs: `artifacts/evidence/custom-alerts` and `artifacts/validation/custom-alerts`. Source is local/uncommitted; no commit, push, store upload or publication occurred. No task-created server, browser, device, app window or preview remains active; the installer waited for the user to quit Personal and did not stop or launch any application.

Human acceptance: the user confirmed the installed custom alerts work correctly. This confirms their exercised Pixel/Mac flow, without claiming exhaustive Focus, multi-screen or accessibility coverage.
