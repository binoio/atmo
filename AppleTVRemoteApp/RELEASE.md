# Release Guide

This repository produces a distributable, sandboxed build of the Atmo app with the embedded Python bridge.

## Prerequisites

- A Python 3.11 virtual environment at the repo root: `./fetch_python.sh && ./setup_python_env.sh`.
- Xcode (or Command Line Tools) so that `xcrun` and `swift build` are available.
- A "Developer ID Application" signing identity in the keychain.
- Notary credentials stored in a keychain profile: `xcrun notarytool store-credentials atmo-notary` (never put the app-specific password in a repo file).

## Build, sign, notarize (manual — do NOT use `./ship notarize`)

> **Warning:** the ship-it submodule ignores the `SIGN_HOOK` defined in `.ship-it.conf`.
> Its notarize step runs a naive `codesign --deep` with **no entitlements**, which
> strips `app-sandbox`/network entitlements from the app and the embedded Python —
> exactly the signing regression that broke device discovery in v1.1.0. Until
> ship-it honors `SIGN_HOOK`, sign manually with the sequence below.

Run from the repo root:

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

`codesign_python_app.sh` signs inner-to-outer (`.so` → `.dylib` → Mach-O executables → app),
applying the **app's entitlements to the embedded Python binaries as well** — the child
processes run in their own sandbox with network access, mirroring the v1.0.0 `--deep`
signing that made Local Network discovery work.

### Post-sign checks

```bash
codesign --verify --deep --strict dist/Atmo.app
codesign -d --entitlements - dist/Atmo.app                                            # app-sandbox + network
codesign -d --entitlements - dist/Atmo.app/Contents/Resources/Python/.venv/bin/python3.11  # same entitlements
spctl -a -vv -t exec dist/Atmo.app                                                    # "Notarized Developer ID" after stapling
```

### On-device verification (required before publishing)

1. `tccutil reset LocalNetwork io.bino.atmo`
2. Copy `dist/Atmo.app` to `/Applications` and launch from Finder.
3. The Local Network permission prompt should appear; grant it — devices should list within ~5 s.
4. If scanning fails immediately, inspect `log show --predicate 'subsystem == "io.bino.atmo"' --last 10m`
   and try the spawn-strategy fallback: `defaults write io.bino.atmo ATMO_SPAWN_STRATEGY disclaiming`, relaunch.
   (`defaults delete io.bino.atmo ATMO_SPAWN_STRATEGY` restores the default.)
5. Deny the permission and relaunch: the in-app "no Local Network access" banner should
   appear and a scan must stop with an actionable message (never an endless spinner).

## Installing the bundle

1. Extract `dist/Atmo.zip` to `/Applications`.
2. Ensure `Atmo.app` remains intact; the executable expects the embedded Python resources inside the bundle.
3. Launch by double-clicking `Atmo.app`, or from Terminal: `/Applications/Atmo.app/Contents/MacOS/Atmo`.
