# Background receive notifications: local delivery 2026-10-31

Historical record for build 2026103102. Its bundle and provenance are preserved in `artifacts/deliveries/2026103102`. Build 2026103103 replaces this system backend with custom floating alerts; see `CUSTOM_ALERT_VALIDATION.md`.

## Delivered

- Installed `/Applications/LocalSend Personal.app`, version `1.18.2`, build `2026103102`, bundle ID `dev.ylagef.localsendPersonal`.
- Executable SHA-256: `aaf3a278122caecea99725e309b64a76ac9488f831555c0371801f3adce6ae9d`.
- The installer verified 163 file hashes, 81 symlink targets and the deep strict code signature. It did not launch the application or modify sandbox preferences/data.
- The previous, user-accepted build remains at `artifacts/deliveries/2026103101/LocalSend Personal.app`. The exact previous installed bundle is retained at `artifacts/deliveries/2026103101/installed-app-before-upgrade.app`.
- Source remains local and uncommitted on `feat/copy-received-image`; no push, tag, source release or publication occurred. The clipboard feature and original official installations were preserved.

## Activate and test

Open Personal and go to Settings → General → **Notify when receiving in the background** (Spanish: **Avisar al recibir en segundo plano**). Turn it on and allow notifications in macOS. The setting starts off deliberately, so the permission prompt is caused by an explicit user action. Grant also enables the existing close-to-tray preference. Closing the window then keeps the app in the menu bar; quitting it still stops receipt. Launch-at-login remains independently controlled and was not enabled.

With manual acceptance, a background request shows a pending notification when macOS permits scheduling. Clicking only reveals LocalSend's existing UI; it never accepts anything. Failed/denied scheduling retains the old foreground fallback. Successful Quick Save transfers can show a completion notification, which opens history only if no incoming session is active. PIN, favorites, auto-accept and saving policies are unchanged.

## Validation

| Check | Result |
| --- | --- |
| Flutter analyze | Passed, no issues. |
| Full application regression | 111 tests passed, including the previously delivered image clipboard tests. |
| Final focused regression | 10 tests passed: 7 permission/channel/setting tests plus 3 stale-click navigation regressions. |
| Native notification payload smoke | Passed for pending/done metadata, per-session identifiers, invalid kinds and missing arguments. No OS notification was posted. |
| Setting widget renders | Passed in light/dark themes at widths 900 and 400; uses real production widgets and synthetic permission/state fixtures. |
| macOS release build and signature | Passed after the stale-click correction. |
| Upgrade preflight and installation | Passed against the retained prior manifest; previous app backed up and installed candidate verified. |
| Release configuration and Git diff whitespace | Passed. |

Logs: `artifacts/validation/notifications`. Source archive, hashes and installation receipt: `artifacts/provenance`. Evidence: `artifacts/evidence/notifications`. No product source changed after the final compilation.

## Independent review

- **Claude Sonnet 5.5 Medium** found a confirmed stale pending notification click that could replace an active transfer's navigation root. Corrected by removing root replacement: pending clicks only reveal existing UI; completion clicks preserve every active receive state. The follow-up found no remaining confirmed defects. Additional safeguards bound native scheduling to three seconds and distinguish permission errors from denial.
- **Claude Opus 5.5 Medium, Fast disabled** approved the setting's placement, explicit permission flow, menu-bar explanation, and four widget captures. No visual defect was found at either width/theme.
- No confirmed findings were rejected. Native OS acceptance remains separate from static and widget review.

## Limits and cleanup

The real macOS permission dialog, background banner, Focus/notification settings and click-to-restore behavior have not been driven. The computer-use approval mechanism is unavailable in this session. Native banner/desktop screenshots were therefore not captured; the supplied images show only the app's real setting widgets. The user must enable the setting, grant OS permission and try an actual Pixel transfer. A scheduled notification remains subject to macOS notification settings.

The installer refusal for running apps and the backup/rollback logic were independently reviewed; no deliberately failing live installation was injected. Notification response tests mock the native channel, and payload tests do not establish OS delivery. Unchanged Rust core, Android, iOS, Windows and Linux suites were not rerun for this macOS-only patch.

No task-created app window, server, container, browser or device remains active. Builds, previous deliveries, receipts and evidence are deliberately retained. User applications were not launched, quit or controlled.
