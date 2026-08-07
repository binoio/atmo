# Release Guide

This repository produces a distributable, sandboxed build of the Atmo app with the embedded Python bridge, published with Sparkle auto-updates: an EdDSA-signed appcast at `docs/appcast.xml` is served from GitHub Pages (`https://binoio.github.io/atmo/appcast.xml`) and the zips live on GitHub Releases.

## Prerequisites

- A Python 3.11 virtual environment at the repo root: `./fetch_python.sh && ./setup_python_env.sh`.
- Xcode (or Command Line Tools) so that `xcrun` and `swift build` are available.
- A "Developer ID Application" signing identity in the keychain (override with `ATMO_SIGN_IDENTITY`).
- Notary credentials stored in a keychain profile (override with `ATMO_NOTARY_PROFILE`): `xcrun notarytool store-credentials atmo-notary --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>` (never put credentials in a repo file).
- Sparkle EdDSA key pair in the login Keychain (`generate_keys` from the Sparkle tools under `AppleTVRemoteApp/.build/artifacts`).
- `gh auth login` with access to `binoio/atmo`.

## One-step release (do NOT use `./ship notarize`)

> **Warning:** the ship-it submodule ignores the `SIGN_HOOK` defined in `.ship-it.conf`.
> Its notarize step runs a naive `codesign --deep` with **no entitlements**, which
> strips `app-sandbox`/network entitlements from the app and the embedded Python —
> exactly the signing regression that broke device discovery in v1.1.0. Until
> ship-it honors `SIGN_HOOK`, release with `release.sh` (or the manual sequence below).

1. Bump `VERSION` at the repository root.
2. Write `ReleaseNotes/Atmo-X.Y.Z.md` (GitHub release body) and `ReleaseNotes/Atmo-X.Y.Z.html` (embedded in the Sparkle appcast).
3. Commit everything, then run from the repo root:

```bash
zsh AppleTVRemoteApp/Scripts/release.sh
```

The script performs the following:

1. Preflight: clean working tree, version newer than the latest tag, release notes present, signing identity and `gh` auth available.
2. Rebuilds the bundled Python environment via `Scripts/package_python.sh` and compiles the Swift executable in `release` configuration.
3. Bundles `dist/Atmo.app` with the embedded Python resources and `Sparkle.framework`, and verifies `SUFeedURL`/`SUPublicEDKey` and the Frameworks rpath.
4. Codesigns inside-out via `codesign_python_app.sh` (never `--deep`), notarizes via the App Store Connect API, and staples.
5. Regenerates `docs/appcast.xml` with an EdDSA signature from the login Keychain, embedding the HTML release notes.
6. Tags `vX.Y.Z`, publishes the GitHub release with the zip, then commits and pushes the appcast (release first, so the download URL exists before the appcast goes live). The Pages workflow deploys `docs/`, which serves the feed.

## Manual build, sign, notarize

Equivalent to steps 2–4 above, from the repo root:

```bash
bash AppleTVRemoteApp/Scripts/package_python.sh
swift build -c release --package-path AppleTVRemoteApp
mkdir -p AppleTVRemoteApp/build
cp "$(swift build -c release --package-path AppleTVRemoteApp --show-bin-path)/Atmo" AppleTVRemoteApp/build/Atmo
APP_VERSION=<x.y.z> bash AppleTVRemoteApp/Scripts/bundle.sh
bash AppleTVRemoteApp/Scripts/codesign_python_app.sh dist/Atmo.app "Developer ID Application: <name> (<team>)"
ditto -c -k --keepParent dist/Atmo.app dist/Atmo.zip
xcrun notarytool submit dist/Atmo.zip --keychain-profile atmo-notary --wait
xcrun stapler staple dist/Atmo.app
rm dist/Atmo.zip && ditto -c -k --keepParent dist/Atmo.app dist/Atmo.zip
```

`codesign_python_app.sh` signs inner-to-outer (`.so` → `.dylib` → Mach-O executables →
Sparkle.framework internals → app). The embedded Python binaries are signed with hardened
runtime but no entitlements, so the children exec'd by the sandboxed app inherit its
sandbox — the v1.0.0 behavior that makes Local Network discovery work. Sparkle's
Autoupdate, Updater.app, and XPC services are signed individually, with the XPC services
keeping their shipped entitlements.

### Post-sign checks

```bash
codesign --verify --deep --strict dist/Atmo.app
codesign -d --entitlements - dist/Atmo.app                                            # app-sandbox + network
codesign -d --entitlements - dist/Atmo.app/Contents/Resources/Python/.venv/bin/python3.11
spctl -a -vv -t exec dist/Atmo.app                                                    # "Notarized Developer ID" after stapling
```

### On-device verification (required before publishing)

1. Clear the previous grant: System Settings ▸ Privacy & Security ▸ Local Network ▸ toggle
   Atmo off. (`tccutil` can NOT reset Local Network on modern macOS — the per-service form
   fails and `reset All io.bino.atmo` silently leaves the grant intact.)
2. Copy `dist/Atmo.app` to `/Applications` and launch from Finder.
3. The Local Network permission prompt should appear; grant it — devices should list within ~5 s.
4. If scanning fails, inspect `log show --predicate 'subsystem == "io.bino.atmo"' --last 10m`.
   The default spawn strategy is `disclaiming` (Foundation Process, the verified-working v1.0.0
   behavior); `defaults write io.bino.atmo ATMO_SPAWN_STRATEGY inheriting` switches to the
   posix_spawn attribution mode for A/B debugging, `defaults delete io.bino.atmo ATMO_SPAWN_STRATEGY`
   restores the default. (For the sandboxed app the defaults domain lives in
   `~/Library/Containers/io.bino.atmo/Data/Library/Preferences/`.)
5. Deny the permission and relaunch: the in-app "no Local Network access" banner should
   appear and a scan must stop with an actionable message (never an endless spinner).
6. Settings ▸ Updates should show the automatic-update toggles, and "Check for Updates…"
   in the Atmo menu should reach the appcast without a signature error.

## Installing the bundle

1. Extract `dist/Atmo.zip` to `/Applications`.
2. Ensure `Atmo.app` remains intact; the executable expects the embedded Python resources inside the bundle.
3. Launch by double-clicking `Atmo.app`, or from Terminal: `/Applications/Atmo.app/Contents/MacOS/Atmo`.
