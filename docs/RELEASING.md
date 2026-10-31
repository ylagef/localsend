# LocalSend Personal delivery

This is a personal patch checkout of LocalSend. `origin` is `ylagef/localsend`; `upstream` is `localsend/localsend`.
Keep patches small and review upstream changes before integrating them. Personal patches are integrated on `main`; `feat/copy-received-image` retains the original implementation history.

## Toolchains and checks

Use the exact Flutter Git submodule revision and `.fvmrc` version. Initialize it with `git submodule update --init support/submodules/flutter` and fetch its matching version tag when using a shallow clone, so Flutter does not report an unknown SDK version. FVM users may use the same `.fvmrc` pin. Rust is pinned in `rust-toolchain.toml`.
The bootstrap for this checkout uses Rust under `~/.local/share/localsend-toolchains`, without changing shell profiles. `scripts/personal-env.sh` sets the tools only for its child commands. Reuse the existing Dart workspace and `pubspec.lock`.

Run `bash scripts/check-personal.sh` through the appropriate `heavy` test class. Native smoke test:

```bash
xcrun swiftc app/macos/Runner/ImageClipboard.swift scripts/test-image-clipboard.swift -o artifacts/test-image-clipboard
artifacts/test-image-clipboard
```

The smoke test uses a unique private pasteboard and does not read or overwrite the user's clipboard. UI tests mock only the platform channel; they do not establish compatibility with every destination app.

## Local test build and install

```bash
bash scripts/build-macos-personal.sh
```

The adapter enters Mac `heavy` build admission, compiles locally, ad-hoc signs and verifies `artifacts/LocalSend Personal.app`, and retains a source archive, dirty patch, source hashes and artifact hashes in `artifacts/provenance`. Existing artifact output is never overwritten. Install with `python3 scripts/install-personal.py`. By default it refuses any existing destination, copies to `/Applications/LocalSend Personal.app`, verifies file hashes and symlinks against the build manifest, and verifies the installed signature.

This build uses bundle ID `dev.ylagef.localsendPersonal`, its own app group and preferences, and the standard port 53317. It does not copy existing user data. Official installations remain intact. Quit the official app before launching Personal: sharing the standard discovery port is required for interoperability, so the two instances must not run together. The receiving device must select the Personal instance; its generated device alias can be changed in settings. Clipboard copying is manual and macOS-only. It does not change automatic acceptance or automatic finishing.

This local build targets Apple Silicon and macOS 12 or later. The deployment target override is required by the installed Xcode SDK, which rejects upstream's macOS 11 target. Ad-hoc signing is for local testing. Apple Developer distribution signing, notarization, App Store upload and all other platform delivery adapters are unavailable in this setup. No cloud builds or uploads are configured.

## Source releases

The shared release-tools sibling checkout powers `node scripts/release-local.mjs status`, `prepare`, `check`, `build`, `tag`, `publish` and `record`. `.release-local.json` configures source and macOS build targets plus an authorized public GitHub release target. `fork-version.json` is the fork packaging version; upstream package/platform version files stay under upstream's existing rules.

The release engine requires an authorized commit and a clean source tree on `main` before a source release. Feature work remains uncommitted unless separately authorized. A development build from dirty source is explicitly not a tagged source release. Do not bypass release-engine cleanliness checks.


For a verified upgrade, pass the exact retained previous manifest first with `--dry-run`, then without it:

```bash
python3 scripts/install-personal.py --previous-manifest artifacts/deliveries/2026103101/provenance/manifest.json --dry-run
```

```bash
python3 scripts/install-personal.py --previous-manifest artifacts/deliveries/2026103101/provenance/manifest.json
```

The installer refuses a running Personal app, checks the old installation against that manifest, retains its bundle beside the previous delivery, verifies the new copy, and restores the old bundle if copying or verification fails. It never launches or quits an app and never modifies sandbox user data. Use the manifest for the actually installed previous build on each later upgrade.


## GitHub fork releases

Fork release version `1.18.3` is packaging metadata. It distributes the user-accepted app runtime `1.18.2`, build `2026103103`, without rebuilding or reinstalling it. App and fork versions are intentionally separate. The binary is Apple Silicon only, macOS 12+, ad-hoc signed and not notarized.

The `github` target packages exact committed source plus the retained app from `artifacts/LocalSend Personal.app`. Its original manifest at `artifacts/provenance/manifest.json` must also be present. The adapter refuses product/build-source drift, modified bundle files or symlinks, wrong repository/Flutter pin and existing output. Only explicit release metadata and documentation may change relative to that accepted build. It verifies the extracted ZIP before retaining four assets in `.release-local/github`: source, macOS ZIP, sanitized provenance and checksums. No private signing material or local absolute paths enter the public provenance.

Release-tools checks run under Mac `heavy` admission because the Flutter fixtures use native macOS branches and fonts. CI runs automatically for upstream; this fork requires an explicit manual dispatch. No hosted builds are needed for a release.

After authorized commits have landed on clean `main`:

```bash
node scripts/release-local.mjs prepare --version 1.18.3
```

Review the version/changelog diff and commit the intended release metadata. Build and tag the clean release commit:

```bash
heavy run --class mac-test --label "LocalSend release package" -- node scripts/release-local.mjs build --target github
```

```bash
heavy run --class mac-test --label "LocalSend release tag" -- node scripts/release-local.mjs tag --yes
```

After explicitly pushing the exact main commit and tag, publish through the configured adapter:

```bash
heavy run --class mac-test --label "LocalSend GitHub release" -- node scripts/release-local.mjs publish --target github --yes --authorize-publication
```

A later release must preserve previous output before packaging, supply the actually accepted app/manifest, update its documented runtime/build mapping and use the next fork version. Source-only releases remain available via `build --target source`. GitHub publication does not imply notarization, App Store delivery, another platform build, or local installation. Git-common-directory release manifests and ignored artifacts need their existing local backup custody; they are not pushed with source.
