# Release Guide

This repository includes a small utility script to produce a distributable build of the Atmo app along with the embedded Python bridge.

## Prerequisites

- An activated Python virtual environment containing the project dependencies (use `.venv` created earlier and install `pyatv==0.16.1`).
- Xcode command line tools so that `xcrun` and `swift build` are available.

## One-step release build

```bash
bash Scripts/release.sh
```

The script performs the following:

1. Rebuilds the bundled Python environment by running `Scripts/package_python.sh`.
2. Compiles the Swift executable in `release` configuration via `xcrun swift build`.
3. Creates an `Atmo.app` bundle containing the executable and embedded Python resources.
4. Archives the bundle into `dist/Atmo.zip`.

After producing the unsigned distribution, see NOTARIZE.md for instructions and an automated script to codesign, notarize, staple, and publish a notarized release via GitHub.

## Installing the bundle

1. Extract `dist/Atmo.zip` to your desired destination (for example `/Applications`).
2. Ensure `Atmo.app` remains intact; the executable expects the embedded Python resources inside the bundle.
3. Launch the app by double-clicking `Atmo.app` or via Spotlight.

After extraction you can also launch from the terminal with:

```bash
/Applications/Atmo.app/Contents/MacOS/Atmo
```

The app discovers the bundled Python interpreter automatically and uses it to run the bridge commands.
