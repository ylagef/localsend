# Personal patch coverage

| Case | Behavior | Evidence | State |
| --- | --- | --- | --- |
| IMG-01 | Copy is offered only for received, completed macOS image files with paths. | Eligibility unit tests, progress wiring and history widget tests. | Passed (2026-10-31). |
| IMG-02 | Explicit copy writes image content, not a file URL, with pixels and transparency intact. | Method-channel unit test and native private-pasteboard round-trip. | Passed (2026-10-31). |
| IMG-03 | Pending copy blocks repeat activation; success appears only after completion. | CopyImageButton widget test. | Passed (2026-10-31). |
| IMG-04 | Missing/invalid files fail without a success message and without replacing the existing pasteboard. | Native smoke test and widget failure/retry test. | Passed (2026-10-31). |
| IMG-05 | Navigating away during copy does not update a disposed widget. | CopyImageButton widget test. | Passed (2026-10-31). |
| IMG-06 | A previously persisted received image can be copied through history. | History widget fixture loaded through persistence; completed-transfer page fixture. | Passed (2026-10-31). |
| IMG-07 | Pixel sends to the installed Personal build, then image pastes into a destination app. | Physical-device and shared-desktop interactive acceptance. | Not run; desktop control permission is unavailable in this session. |

Scope is macOS only. Other platform clipboard behavior is unchanged and is not claimed as covered. Existing upstream tests remain authoritative for unrelated flows.

Evidence: `artifacts/validation/` and `artifacts/evidence/`. Fixtures use the actual Flutter widgets, synthetic Pixel data, and loaded system/Material icon fonts, in light/dark themes at 900 and 400 pixels. These are not native desktop captures.


## Background notifications (macOS)

| Case | Expected behavior | Evidence | State |
| --- | --- | --- | --- |
| NOTIF-01 | Opt-in defaults off; grant enables notifications and close-to-tray; denial/error preserves off state. | background_notifications_test.dart permission tests. | Passed. |
| NOTIF-02 | Pending permission disables repeat input; enabled state reloads from persistence; disabling preserves tray. | background_notifications_test.dart pending/restored-state and grant/disable tests. | Passed. |
| NOTIF-03 | A denied, failed or timed-out pending notification permits the original foreground fallback. | Native channel false/error tests and receive_controller review. | Passed at channel/policy layer; OS banner pending. |
| NOTIF-04 | Pending clicks never replace current navigation; done clicks preserve any incoming session. | receive_notification_navigation_test.dart enumerates every SessionStatus. | Passed. |
| NOTIF-05 | Native requests carry session/kind only for navigation and no acceptance action. | test-receive-notification.swift. | Passed; no OS notification posted by the smoke test. |
| NOTIF-06 | Setting remains readable in both themes at 900 and 400 pixels. | artifacts/evidence/notifications and Opus widget review. | Passed with synthetic fixtures. |
| NOTIF-07 | Native permission prompt, real background banner and click restore work on the user's Mac. | Installed build 2026103102. | Human acceptance pending; no desktop control used. |

## Custom floating receive alerts (macOS, build 2026103103)

The previous NOTIF cases above record build 2026103102. This build replaces system delivery with an app-owned panel; OS permission and Notification Center are no longer part of the flow.

| Case | Expected behavior | Evidence | State |
| --- | --- | --- | --- |
| ALERT-01 | Existing opt-in persists; enabling verifies native availability and keeps close-to-tray. Disabling hides the card. | background_notifications_test.dart, native channel integration. | Passed at mocked channel/provider layer; live Mac acceptance pending. |
| ALERT-02 | Pending accept/reject only targets the current waiting session and its owned receive route. Stale or concurrent decisions fail. | receive_alert_actions_test.dart plus controller integration review. | Registry and duplicate/stale-action tests passed; controller identity/route check reviewed separately. Real Pixel acceptance pending. |
| ALERT-03 | Completed image copies trusted image bytes or opens its saved file. Nonimages/multiple files cannot invoke image copy. | receive_alert_actions_test.dart, native private-pasteboard smoke. | Registry rules and real private-pasteboard image bytes passed; live Open and Pixel transfer pending. |
| ALERT-04 | Clipboard failure allows retry; completed snapshots are bounded; unknown actions/IDs fail. | receive_alert_actions_test.dart, test-receive-alert.swift. | Unit rules, local native button dispatch, stale-view callback and retry deadline passed. |
| ALERT-05 | Pending card stays until decision/dismissal; dismiss never rejects. Arrival does not activate the main app. | Native implementation review, offscreen view fixtures. | Live placement, focus, Spaces, hover and VoiceOver pending. |
| ALERT-06 | Light/dark cards fit long sender/file text and distinguish pending/receiving/done/error. | Actual native view fixtures in artifacts/evidence/custom-alerts, Opus visual acceptance. | Offscreen captures passed; Opus accepted localized cards and English setting in both themes. |

No shared desktop capture or control is authorized. Offscreen fixtures establish rendering, not actual panel delivery, pointer/keyboard behavior or transfer E2E. No Android/iOS/Windows/Linux behavior is intentionally changed.

Final automation: 123 application tests passed, analyze passed, native card and private clipboard smoke passed. Session guards and stopServer cleanup were independently reviewed; direct controller/stopServer integration tests and live Mac E2E are missing.
