Notarization and GitHub Release Guide

Last updated: 2026-01-11

**NOTE:** For comprehensive signing and notarization setup, see [../docs/SIGNING.md](../docs/SIGNING.md).

This document provides quick reference for the automated notarization workflow.

Prerequisites

- Apple Developer account with access to the "Certificates, Identifiers & Profiles" and "Keys" sections.
- A Developer ID Application signing certificate installed in the signing machine's keychain.
- Either a Notary API key (recommended) or an Apple ID + app-specific password for notarization.
- xcode command line tools (xcrun, codesign, stapler) and the `gh` CLI for GitHub releases (optional).

Secure secrets for CI (GitHub Actions) using repository secrets:
- NOTARY_KEY (base64 of the .p8 file) or store the .p8 file in the runner environment
- NOTARY_KEY_ID
- NOTARY_ISSUER_ID
- DEVELOPER_ID_APPLICATION (exact codesign identity string)
- GH_TOKEN (for gh CLI if running in CI)

Automated script

A convenience script is provided at AppleTVRemoteApp/Scripts/notarize_and_release.sh that:
1. Runs the existing Scripts/release.sh to build the app bundle and a distribution zip.
2. Unzips the bundle, codesigns the .app using DEVELOPER_ID_APPLICATION, and repacks the signed bundle.
3. Submits the signed zip to Apple's notary service using notarytool (preferred) or altool as a fallback.
4. Staples the notarization ticket to the .app and produces a stapled zip.
5. (Optional) Uses the gh CLI to create a GitHub release and upload the stapled zip.

Usage (local)

1. Export required env vars, for example:

   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
   export NOTARY_KEY_PATH="/path/to/AuthKey_XXXX.p8"
   export NOTARY_KEY_ID="XXXX"
   export NOTARY_ISSUER_ID="YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY"

2. Make the script executable and run it from the AppleTVRemoteApp folder:

   chmod +x Scripts/notarize_and_release.sh
   ./Scripts/notarize_and_release.sh

Usage (CI - GitHub Actions)

- Create an API key in App Store Connect (Issuer ID, Key ID, .p8 file) and add secrets to the repository.
- In the workflow, restore the .p8 file, set DEVELOPER_ID_APPLICATION, NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID, and run the script.

Notes & Troubleshooting

- For fully automated CI runs, prefer notarytool with an API key rather than an Apple ID/app-specific password.
- Codesigning will fail if the Developer ID certificate private key is not available on the runner; use GitHub-hosted runners with a provisioning step that installs the certificate into the keychain (use actions/setup-keychain or similar).
- If using macOS self-hosted runners, ensure the signing identity is present and unlocked in the system keychain.
- Review notarytool/altool output for details; notarytool --wait returns JSON with status and logs.

Example GitHub Actions snippet (high-level)

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Restore .venv and build
        run: |
          # create venv and install deps as described in README
          python3 -m venv .venv
          . .venv/bin/activate
          pip install -r pybridge/requirements.lock
          bash AppleTVRemoteApp/Scripts/release.sh
      - name: Install signing key and notary key
        run: |
          # write NOTARY key and install Developer ID cert into the keychain for signing
          echo "$NOTARY_KEY" | base64 --decode > /tmp/AuthKey.p8
          security create-keychain -p actions build.keychain
          security import /tmp/your_developer_id_certificate.p12 -k build.keychain -P "$DEVELOPER_ID_CERT_PASSWORD" -T /usr/bin/codesign
          security list-keychains -s build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p actions build.keychain
      - name: Notarize and release
        env:
          DEVELOPER_ID_APPLICATION: ${{ secrets.DEVELOPER_ID_APPLICATION }}
          NOTARY_KEY_PATH: "/tmp/AuthKey.p8"
          NOTARY_KEY_ID: ${{ secrets.NOTARY_KEY_ID }}
          NOTARY_ISSUER_ID: ${{ secrets.NOTARY_ISSUER_ID }}
          GH_TOKEN: ${{ secrets.GH_TOKEN }}
        run: |
          chmod +x AppleTVRemoteApp/Scripts/notarize_and_release.sh
          AppleTVRemoteApp/Scripts/notarize_and_release.sh


# Creating an App Store Connect API Key (AuthKey .p8)

1. Sign in to App Store Connect (https://appstoreconnect.apple.com) with the Apple ID that is part of your App Store Connect account.
2. Open Integrations → App Store Connect API (or Users and Access → Keys on some accounts) and click the + / Create API Key button.
3. Enter a name for the key. Choose "Individual" for a personal account (no team) or "Team" when creating an organizational key; then select role "App Manager" or higher and click Create.
4. Download the generated AuthKey_XXXXX.p8 file immediately — App Store Connect will not let you download it again.
5. Note the Key ID (shown next to the key) and the Issuer ID (displayed on the App Store Connect API page). Store those in NOTARY_KEY_ID and NOTARY_ISSUER_ID respectively.

# Storing the .p8 key for GitHub Actions

- Option A: Store the raw file content as a secret (base64-encoded):

  base64 /path/to/AuthKey_XXXX.p8 | pbcopy
  # Paste into GitHub secret named NOTARY_KEY (base64 content)

  In the workflow, restore it:
    echo "$NOTARY_KEY" | base64 --decode > /tmp/AuthKey.p8

- Option B: Upload the .p8 file to a secure storage available to your runner and point NOTARY_KEY_PATH at it.

# Installing Developer ID signing certificate on macOS runner

1. Export your Developer ID Application certificate and private key to a PKCS#12 file (.p12) locally:

   security export -k ~/Library/Keychains/login.keychain-db -t priv -f pkcs12 -o DeveloperID.p12 -P "" -A

   # Or use Keychain Access: right click the certificate -> Export

2. In CI, store the .p12 content as a secret (base64) and install during the workflow:

   echo "$DEVELOPER_ID_P12" | base64 --decode > /tmp/DeveloperID.p12
   security create-keychain -p actions build.keychain
   security import /tmp/DeveloperID.p12 -k build.keychain -P "$DEVELOPER_ID_CERT_PASSWORD" -T /usr/bin/codesign
   security list-keychains -s build.keychain
   security default-keychain -s build.keychain
   security unlock-keychain -p actions build.keychain

3. Ensure DEVELOPER_ID_APPLICATION env var matches the Common Name of the certificate (e.g. "Developer ID Application: Your Name (TEAMID)").

# Quick-local test

1. Download AuthKey_XXXX.p8 and set NOTARY_KEY_PATH to its path and export NOTARY_KEY_ID and NOTARY_ISSUER_ID.
2. Ensure your Developer ID cert is installed in your login keychain and DEVELOPER_ID_APPLICATION is set.
3. Run:

   chmod +x AppleTVRemoteApp/Scripts/notarize_and_release.sh
   AppleTVRemoteApp/Scripts/notarize_and_release.sh

# Troubleshooting

- If notarytool reports permission errors, verify the Key ID / Issuer ID and that the .p8 file belongs to an API key with the appropriate role.
- If codesign fails in CI, ensure the imported .p12 was successful and the keychain is unlocked and set as default for the session.
- Remove temporary keychains after the run to avoid leaking credentials.