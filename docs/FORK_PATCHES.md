# Personal patch series

Upstream: https://github.com/localsend/localsend

Personal fork: https://github.com/ylagef/localsend

Baseline: `92e133aa43869e94d394fd04fa70c50a0f796a64` (upstream main after 1.18.2).
Current branch: `feat/copy-received-image`. Work is local and uncommitted; no patch has been pushed or submitted upstream.

## Image clipboard on macOS

- Completed incoming image transfers expose an accessible copy button.
- Receive history offers **Copy image** for image entries with a local path.
- Copying is explicit. Transfers, saving, quick-save and auto-finish behavior are unchanged.
- The macOS implementation validates an `NSImage`, writes image content instead of a file URL, and propagates errors before showing success.
- Invalid or deleted images preserve existing clipboard content. Concurrent clicks are blocked and disposed widgets are not updated.
- English and Spanish labels are included; other locales inherit the English fallback through upstream's translation generator.
- Related upstream issue: https://github.com/localsend/localsend/issues/3105
- Related open proposal: https://github.com/localsend/localsend/pull/3159 (not incorporated; its automatic acceptance behavior is outside this patch).

## Local packaging

The app is installed as **LocalSend Personal**, with bundle ID `dev.ylagef.localsendPersonal` and its own app group/preferences. Existing official apps and data remain untouched. Keep the standard port 53317 and quit the official app before launching Personal so the Pixel retains ordinary discovery compatibility.

The local adapter targets Apple Silicon and macOS 12+, with ad-hoc signing. There is no notarization, store distribution or automatic updater for this personal build. See `RELEASING.md` for toolchains, installation verification and the distinction between a dirty development build and a clean source release.

## Maintaining patches

Preserve the origin/upstream remote split. Before any upstream integration, inspect and preserve uncommitted work, fetch upstream, and review the incoming commits. Do not reset this checkout or auto-update the installed app from upstream binaries. Make source commits, push changes or create upstream pull requests only when authorized. Keep functional patches separate from personal packaging changes when preparing a future commit series.

See `USE_CASE_COVERAGE.md` and `IMAGE_CLIPBOARD_VALIDATION.md` for tested behavior and remaining native acceptance.


## Background receive notifications (macOS)

Build `2026103102` adds an opt-in setting under General, immediately after minimize-to-tray: **Notify when receiving in the background**. Enable it and allow macOS notifications. Granting permission also enables the existing close-to-tray preference; quitting the application still stops receipt. Starting at login remains independently controlled by the existing setting and is not enabled by this patch.

Pending manual requests produce a banner instead of forcing the window forward when notifications can be scheduled. A click only reveals the existing UI. Failed or denied scheduling keeps the original foreground fallback. Successful Quick Save sessions can produce a completion notification; clicking it opens history only when no receive session is active. Auto-accept, PIN and favorites policies are unchanged. Notification errors cannot fail receipt, and scheduling is bounded by a three-second timeout. Pending alerts are removed on acceptance, decline and close. This uses local UserNotifications APIs, without a new Dart package or push-notification service.

The previous user-accepted clipboard build and installed bundle are retained under `artifacts/deliveries/2026103101`. See `BACKGROUND_NOTIFICATIONS_VALIDATION.md`.

### Custom macOS receive card

Build 2026103103 replaces the system-notification backend with a custom AppKit panel. It reuses the existing opt-in preference and close-to-tray behavior, with no OS notification permission request. Pending actions validate the current session and owned route; completed actions use a bounded trusted file registry that survives automatic session closure. Dismissal is not a transfer decision. This panel does not enter Notification Center or inherit Focus suppression. Native focus/Spaces behavior and real Pixel transfer acceptance remain separate from offscreen rendering and mocked channel tests.
