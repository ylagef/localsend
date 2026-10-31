# Image clipboard delivery: 2026-10-31

Historical delivery: superseded by background-notification build `2026103102`; the accepted build and original receipt are retained under `artifacts/deliveries/2026103101`.

## Delivered

- Fork: `https://github.com/ylagef/localsend`, default branch `main`, parent `localsend/localsend`.
- Durable checkout: `/Users/yeray/dev/personal/localsend`, branch `feat/copy-received-image`.
- Source baseline: `92e133aa43869e94d394fd04fa70c50a0f796a64`, plus the retained uncommitted patch. No source commit, push, tag, public release or upstream PR was created.
- Installed app: `/Applications/LocalSend Personal.app`, app version `1.18.2`, build `2026103101`, Apple Silicon, macOS 12+, ad-hoc signed.
- Installed bundle ID: `dev.ylagef.localsendPersonal`. Official 1.18.0 and 1.18.2 installations and their data were preserved.
- 163 installed file hashes and 81 symlink targets match the built artifact; deep strict signature verification passes.
- Main executable SHA-256: `9be42d08e3d36f8affe325ea0bbe33f881f7a197cabb862f30f2e787d056b007`.

## Validation

| Check | Observed result |
| --- | --- |
| Flutter analyze | Passed, no issues. |
| App test suite | 101 tests passed. |
| Additional completed-transfer page tests | 3 tests passed. |
| Isolate test suite | 18 passed; 4 initially skipped because the test loader expected a debug dylib. |
| Those 4 native bridge integration tests | Passed against the compiled release dylib through an owned temporary loader symlink, removed afterwards. This includes real cancellation/retry and running-instance protocol behavior. |
| Native AppKit image clipboard smoke | Passed for PNG, JPEG, image content rather than file URLs, transparency, source deletion, invalid/missing file preservation. Used only a private pasteboard. |
| Final widget/evidence subset | 7 tests passed, including captures in light/dark at 900 and 400 pixels, with Material icons loaded. |
| Local release configuration | `check --config-only` passed; no clean source release attempted from dirty work. |
| macOS build, artifact signature and installed-copy verification | Passed. |

Logs are in `artifacts/validation`. Build source, binary inventories and installation receipt are in `artifacts/provenance`. The original build snapshot remains unchanged; `verification-source.tar.gz` additionally preserves final test and documentation changes. No product Dart/Swift/platform source changed after the delivered compilation.

The first build was blocked by this Xcode SDK rejecting upstream's macOS 11 deployment target; the personal adapter explicitly targets macOS 12. An initial signature verification also caught the dependency's embedded login helper after its plist rewrite; the signer now signs nested helper apps before the parent. Both failures were corrected and the final build reverified.

## Independent review

- **Claude Sonnet 5.5 Medium:** technical review and one follow-up. Confirmed discovery-port and installer/provenance findings were fixed. No remaining high or medium findings. Source archives explicitly separate development snapshots from clean releases.
- Minor static limits: source provenance currently supports ordinary files and file symlinks, plus the pinned clean Flutter submodule. Broken/directory source symlinks are not present in this checkout. A failed future post-copy installation verification deliberately leaves its unique destination for inspection rather than deleting it automatically.
- **Claude Opus 5.5 Medium, Fast disabled:** approved the interaction specification and final eight widget renderings. No confirmed UI defect remained after loading the Material icon font in the capture harness.
- Fork naming and isolated identifiers were retained intentionally as part of the authorized side-by-side installation, rather than treated as an unrelated UX redesign.

## Remaining acceptance

The installed app was not launched or driven. This session had no dedicated approval mechanism for shared-desktop computer use. There are no native before/after desktop captures; evidence uses the actual Flutter widgets with synthetic Pixel/session fixtures. Native launch, Pixel-to-Mac transfer, pasting into the user's destination apps, VoiceOver and keyboard navigation still need interactive acceptance. Other OS builds and the unchanged Rust core's full clippy/unit suite were not run.

Quit the official LocalSend app before opening Personal, then send an image from the Pixel and use the copy icon beside the completed file, or **History → Copy image**. Paste into the target app as the real acceptance check.

Temporary test resources and the Rust loader symlink were cleaned up. Port 40901 has no remaining listener. No task-created browser, native app window, server, container or device remains running. The installed app, build artifacts and toolchains are deliberately retained for ongoing personal patches.
