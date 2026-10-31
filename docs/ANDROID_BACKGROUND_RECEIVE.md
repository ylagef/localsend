# Android background receiving

This personal build adds **Settings → General → Receive in background**. Enable it while the app is visible and allow notifications and, on Android 17, local network access. The app continues receiving after its task is removed from recent apps. Force stop, Android’s Active apps Stop, reboot or process eviction can end reception; reopen the app afterwards. The saved preference is restored only after a successful service start.

A silent foreground-service notification keeps the process available. Incoming requests use a separate notification channel with Accept and Reject. Accept requires authentication on a locked Android 12+ device. Notification content is private on the lock screen. Existing PIN, encryption and quick-save preferences still apply; this feature does not enable auto-accept. The current receive destination must remain accessible.

Foreground service work uses `connectedDevice`, including LAN transfers, with the required multicast permission. A service alone does not bypass Doze network restrictions. For screen-off reception, configure unrestricted battery use for this app in Android settings and verify the result on your phone. Reception is limited to reachable devices on the local network; it is not cloud push.

Turning the mode off declines a waiting request and prevents new background requests. A taskless engine is released after its final foreground-service owner stops. Already accepted transfers finish before the service stops. The foreground UI remains usable. The Stop receiving notification button also disables the mode.

## Installing the personal APK

The release package is `org.localsend.localsend_app`, matching the official app. A different signing certificate cannot update the installed official package. Before replacing it, preserve any settings/history you need and confirm where received files are stored. The first installation normally requires uninstalling the official app; this removes its private preferences, history and device identity. Do not uninstall anything until you have the verified APK and have accepted that loss. Existing received files outside app-private storage should be checked separately.

Subsequent personal APKs must use the same retained signing key and a suitable increasing versionCode. The key stays outside the source tree on GEEKOM at `~/.local/share/localsend-personal/android/`. Do not delete it or commit its configuration. Store a protected backup through your usual credential backup process.

## Sending files to the Pixel

Use LocalSend to send files to the owner's Pixel 9 Pro, including new APKs. Enable Receive in background on the Pixel and verify its live alias and current IP or fingerprint before choosing a receiver. Stale discovery or favorite entries can refer to a previous installation and must not be treated as a second confirmed phone. Keep the sender and Pixel reachable on the local network.

The desktop LocalSend app is a valid sender. For automation, use this repository's `localsend-cli send --to <alias-or-IP> <file>` interface after verifying the exact destination. Choose a separate sender listening port when the desktop app already occupies 53317. Retain the transfer result and artifact SHA-256; receipt of an APK and successful installation are separate outcomes. Do not substitute an HTTP/QR download channel unless the user explicitly requests it. Existing public release downloads are distribution artifacts, not evidence of a transfer to the phone.

## Building

Use `scripts/build-android-personal.sh` through `heavy`'s `gradle` class on GEEKOM. It refuses macOS, checks the pinned Flutter version and Android versionCode range, consumes host-local signing configuration, builds arm64 release, and verifies the APK signature. Set `FLUTTER_ROOT`, `LOCALSEND_ANDROID_BUILD_NUMBER`, and optionally `LOCALSEND_ANDROID_KEY_PROPERTIES`. SDK, Java, NDK and Rust must be available on GEEKOM. Run repository checks before delivery.

The Android runtime version name follows `fork-version.json` via Flutter build flags. Shared upstream version files are unchanged. The ABI versionCode is the supplied build number multiplied by ten plus three. Preserve old artifacts before creating a new delivery. `.release-local.json` exposes an Android build target with no publication adapter. A local working-copy candidate can be built by the script without implying a commit, tag or published release; retain its base revision and exact source hashes/diff.

## Focused coverage inventory

| Case | Automated coverage | Native acceptance |
| --- | --- | --- |
| Preference differs from running service | `test/unit/provider_android_receive_mode_test.dart` | Check restored mode after reopening |
| Startup/permission failure | Same unit suite; injected startup failure | Verify notification and LAN permission denial on Pixel |
| Persistence failure rolls back service | Same unit suite | Not normally reproducible on phone |
| Disable queued during startup | Same unit suite | Verify rapid toggles |
| Disable preserves accepted transfers | `localsend_isolates/test/util/transfer_notification_test.dart` | Transfer plus Stop receiving |
| Service uses connectedDevice and ends only after last owner | Same isolate suite with mocked native service | Inspect real foreground service |
| Setting interaction | `test/widget/android_receive_mode_test.dart` | Android settings screen |
| Session-bound actions, duplicate suppression and invalid actions | Existing `receive_alert_actions_test.dart`; controller session guards | Request, remote cancel, stale action, accept/reject |
| Native request delivery, authentication, Doze and file integrity | Native APK integration required | Pixel 9 Pro, Android 17 build DP11.261016.003 |
| Signing and package identity | Build script uses apksigner and aapt2 | Clean install, then same-key update |

Mocked platform/unit tests do not establish Android lifecycle, lock-screen or battery reliability. Record executed checks and native evidence separately in each delivery report. No physical Pixel was connected at implementation start.

References: [Android foreground-service types](https://developer.android.com/develop/background-work/services/fgs/service-types), [Doze restrictions](https://developer.android.com/training/monitoring-device-state/doze-standby), [application signing](https://developer.android.com/studio/publish/app-signing).

## Implementation validation (2026-10-31)

- Pinned Flutter 3.41.9 on GEEKOM: application and isolate analysis pass. Application suite: 125 passed, 5 platform-specific skips. Isolate suite after building the Linux Rust library: 22 passed, 1 skipped because the existing cancellation reproduction hardcodes a macOS `.dylib` filename. The three TLS instance-handover integration tests run successfully on Linux.
- Targeted final regression suite: 13 passed. Existing release-integrity fixtures: 8 passed. Android package/certificate identity fixtures: 5 passed. Changed Dart files pass format checks.
- Signed arm64 release compilation succeeds on GEEKOM. Native build confirms the existing compileSdk 36 / targetSdk 37 pair is accepted by the installed toolchain. APK assertions check package, version, ABI, signature validity and identity against the retained key.
- Widget screenshots cover the new setting in light and dark themes. Opus reviewed the wording/layout; Sonnet reviewed technical behavior and the fixes. These screenshots do not validate Android notification rendering.
- An isolated Android 16 emulator accepted installation of the debug x86_64 APK. Launch automation then failed with `DEVICE_IN_USE` because the reused serial had a stale claim from another workspace. That claim was left untouched. The owned emulator was shut down and deleted, and its lease was released.
- Native request delivery, action buttons, authentication, screen-off/Doze reception, battery behavior and the final release APK on the Pixel 9 Pro with Android 17 remain unverified. No official app was uninstalled, no user data was touched, and no release was committed or published.

### Settings visibility correction, build 202610343

The first APK's Android entry was mistakenly nested inside a desktop-only settings block. Build 202610343 moves it into General, immediately after Language, with its Android-only guard intact. The new `test/widget/android_receive_settings_screen_test.dart` renders the actual SettingsTab: the Android cases fail on the prior source and pass after the fix in light/dark themes; iOS continues to hide the control. It also activates the switch and verifies persistence. The full app suite now passes 129 tests with the same 5 macOS-only skips. The update uses the same retained personal signing key and a higher versionCode; it can update the first personal APK without uninstalling it.

### Native lifecycle correction

The Android 17 API 37 release-emulator audit reproduced the reported failure: enabling background reception created a foreground service, but pressing Home stopped it and the subsequent prepare-upload returned HTTP 403. The upstream `flutter_foreground_task` 9.2.2 Dart `stopWithTask: true` option installs `TrackVisibilityUtils`, which stops the service when the activity pauses. Leave that nullable option unset and retain `android:stopWithTask="true"` in the Android manifest instead. Disable automatic service restart explicitly. The platform-channel regression asserts the option is absent and automatic restart is false. Native results for Home, notification actions, screen-off and task removal are recorded separately; unit assertions alone do not establish these behaviors.

### Executed Android 17 release-emulator audit, build 202610363

An owned Pixel 9 Pro profile with Android 17 API 37, x86_64 release APK, ran on GEEKOM. The original Home failure was reproduced before the fix. After the lifecycle fix, Home and another foreground app both received real protocol-v2.2 mTLS requests; pressing Receive in the system notification saved the expected 47 bytes with SHA-256 `961d6d002d49b5bff956cf93bb9a7b89abe66c739654bd00060ce51f78d607b7`, and the foreground service remained active. Screen-off request delivery and acceptance after wake also passed. Decline returned HTTP403; remote cancellation returned200, ended the waiting request and removed its pending card.

The final release with the additional notification-throttle correction was installed as a same-key update without data reset: its device fingerprint and saved background preference survived. With a PIN configured, a new request arrived and the lock screen showed generic LocalSend content. PIN acceptance, the final idle-card rendering and task removal remain unverified because agent-device rejected SystemUI PIN presses with an app-focus error and could not launch the launcher even after its prescribed debug retry. No unsupported adb UI fallback was used. A forced deep-idle diagnostic still served info200 and posted a request via the forwarded TCP test connection; this does not validate real Wi-Fi behavior or unrestricted-battery effects.

The sender was a task-owned protocol client, not an official desktop GUI. No physical Pixel was connected. Full final checks: app analyzer passes, 129 app tests pass with 5 macOS-only skips; isolate analyzer passes, 22 isolate tests pass with the existing macOS-dylib-path reproduction skipped. The immediate-completion platform-channel regression asserts idle title/text and the absence of the nullable stopWithTask option. Sonnet 5.5 Medium completed independent review and one follow-up; its confirmed flag-override finding was corrected. The AVD was shut down and deleted, its lease released, and its port forwards removed. APK download is a separately retained, temporary LAN endpoint.

### Task removal support, build 202610393

The user now requires reception after removing LocalSend from recent apps. This supersedes the earlier intentional stop-on-task-removal policy. The foreground service no longer stops with the task. A process-owned cached FlutterEngine retains the main networking isolates while the service owns reception or transfers. Recreated Activities reattach to that engine and session. Channel handlers use application-scoped file access and weak Activity references. A stopped, taskless engine first awaits HTTP and discovery socket shutdown, then releases the engine; reopening during cleanup restores the listeners. A system-only service restart stops itself rather than claiming to receive without a main networking engine. Force stop, Android Active apps Stop, process eviction and reboot remain outside the continuous-reception promise.

Final release-emulator acceptance on Android 17 API 37, Pixel 9 Pro profile:

| Case | Observed result |
| --- | --- |
| Remove exact LocalSend task from Recents | No LocalSend ActivityRecords; same PID3489, foreground service and fingerprint; info200 |
| Receive with no task or Activity | System notification Receive, upload200; saved47bytes match SHA256961d6d002d49b5bff956cf93bb9a7b89abe66c739654bd00060ce51f78d607b7 |
| Completed transfer while taskless | Persistent notification returns to Escuchando en tu red local |
| Stop receiving while taskless | Foreground service disappears, log confirms Server stopped, info request fails |
| Open again after explicit Stop | Fresh Dart bootstrap in same process, info200, saved receive preference remains off |
| Crash owned taskless app process | System restart does not retain an empty service: new PID4753, no FGS, info fails; opening the app restores saved on preference and info200 |
| Runtime locale change | Setting observes translation changes; widget test changes locale without remounting or toggling |

Both analyzers and full Flutter suites pass: 129 app tests, 22 isolate tests; the existing5macOS-only app skips and1macOS-dylib-path isolate skip remain. Android identity fixtures5pass; format and diff checks pass. Sonnet5.5 High performed technical review and one follow-up; confirmed restart, ownership, Activity retention and native listener cleanup findings were corrected and the final shutdown/reopen flow was exercised natively. Opus5.5 Medium found no material visual issue in native light/dark settings and request/result notification captures. Physical Pixel hardware, real Wi-Fi Doze and official desktop-sender interoperability were not repeated in this audit. The owned emulator and its port forwards were removed; no official installation was changed.
