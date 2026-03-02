# Signed Release Setup

This guide explains how to set up code signing and notarization for Atmo releases.

## Prerequisites

1. **Apple Developer Account** with an active subscription
2. **Developer ID Application Certificate** from Apple Developer portal
3. **App-Specific Password** for notarization
4. **Xcode Command Line Tools** installed

## Local Signing Setup

### 1. Export Your Developer ID Certificate

1. Open **Keychain Access** on your Mac
2. Find your "Developer ID Application" certificate
3. Right-click → Export → Save as `.p12` file with a strong password
4. Keep this file secure (do not commit to git)

### 2. Set Environment Variables

For local signing, set these in your shell:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM_ID)"
export APPLEID="your-apple-id@example.com"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

Or use API key authentication (recommended for CI):

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM_ID)"
export NOTARY_KEY_PATH="/path/to/AuthKey_XXXXXXXXXX.p8"
export NOTARY_KEY_ID="XXXXXXXXXX"
export NOTARY_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### 3. Run the Notarization Script

```bash
cd AppleTVRemoteApp
./Scripts/notarize_and_release.sh --no-upload
```

This will:
- Build the unsigned app bundle
- Sign with your Developer ID
- Submit for notarization
- Staple the notarization ticket
- Create `Atmo-stapled.zip` in `dist/`

### 4. Upload to GitHub (Optional)

After notarization completes, upload the release:

```bash
# Using gh CLI (recommended)
gh auth login
./Scripts/upload_release.sh v1.0.0

# Or with GitHub token
export GITHUB_TOKEN="ghp_xxxxxxxxxxxx"
./Scripts/upload_release.sh v1.0.0

# Create as draft
./Scripts/upload_release.sh --draft v1.0.1

# Use custom release notes
./Scripts/upload_release.sh --notes CHANGELOG.md v1.0.0
```

## GitHub Actions Setup (Optional)

The automated workflow is **disabled by default** to support local-only builds.

If you want to enable automated releases via GitHub Actions, uncomment the workflow in `.github/workflows/notarize-release.yml` and configure these secrets:

### Required Secrets

Go to **Settings → Secrets and variables → Actions** in your GitHub repository and add:

#### Certificate & Keychain
- `APPLE_CERTIFICATE_BASE64`: Your Developer ID certificate exported as .p12, then base64 encoded
  ```bash
  base64 -i certificate.p12 | pbcopy
  ```
- `APPLE_CERTIFICATE_PASSWORD`: Password for the .p12 file
- `KEYCHAIN_PASSWORD`: Random password for temporary keychain (generate a secure one)

#### Developer ID Identity
- `DEVELOPER_ID_APPLICATION`: Your full signing identity string
  ```
  Developer ID Application: Your Name (TEAM_ID)
  ```
  Find this with: `security find-identity -v -p codesigning`

#### Notarization (Option A: App-Specific Password)
- `APPLE_ID`: Your Apple ID email
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password from appleid.apple.com

#### Notarization (Option B: API Key - Recommended)
- `NOTARY_KEY_PATH`: Path to save the .p8 key in the runner (e.g., `/tmp/AuthKey.p8`)
- `NOTARY_KEY_ID`: Key ID from App Store Connect
- `NOTARY_ISSUER_ID`: Issuer ID from App Store Connect
- `NOTARY_KEY_CONTENT`: Base64-encoded .p8 file content

### Creating an App-Specific Password

1. Go to https://appleid.apple.com
2. Sign in with your Apple ID
3. Navigate to **Security → App-Specific Passwords**
4. Click **Generate an app-specific password**
5. Name it "Atmo Notarization"
6. Copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

### Creating API Keys (Recommended for CI)

1. Go to https://appstoreconnect.apple.com/access/api
2. Click the **Keys** tab
3. Click **+** to generate a new key
4. Name it "Atmo Notarization", select "Admin" access
5. Download the `.p8` file (you can only download once!)
6. Note the **Key ID** and **Issuer ID**

Then in GitHub secrets:
```bash
# Convert .p8 to base64
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

## Triggering a Release

### Local Build and Upload (Recommended)

```bash
# 1. Build and notarize locally
cd AppleTVRemoteApp
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM_ID)"
export APPLEID="your-apple-id@example.com"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
./Scripts/notarize_and_release.sh --no-upload

# 2. Upload to GitHub
./Scripts/upload_release.sh v1.0.0
```

### Automatic (if CI/CD enabled)

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Manual (workflow dispatch - if CI/CD enabled)

1. Go to **Actions** tab in GitHub
2. Select "Build, Notarize and Release" workflow
3. Click "Run workflow"
4. Enter version tag (e.g., `v1.0.0`)

## Entitlements

The app uses these entitlements (defined in `Support/Atmo.entitlements`):

- `com.apple.security.app-sandbox` - Sandboxed for security
- `com.apple.security.network.client` - Network access to communicate with Apple TV
- `com.apple.security.files.user-selected.read-write` - User-selected file access
- `com.apple.security.automation.apple-events` - Apple Events for automation

## Verification

After signing and notarization:

```bash
# Verify signature
codesign -vvv --deep --strict dist/Atmo.app

# Check notarization
spctl -a -vvv -t install dist/Atmo.app

# View entitlements
codesign -d --entitlements - dist/Atmo.app
```

## Troubleshooting

### "No identity found"
- Ensure your Developer ID certificate is installed in Keychain
- Run: `security find-identity -v -p codesigning`

### "Notarization failed"
- Check Apple ID credentials are correct
- Verify app-specific password hasn't expired
- Review notarization log: `xcrun notarytool log <submission-id>`

### "Invalid signature"
- Ensure all Mach-O binaries are signed (Python libraries, etc.)
- Try cleaning and rebuilding: `rm -rf dist/ && ./Scripts/notarize_and_release.sh`

### GitHub Actions fails on signing
- Verify `APPLE_CERTIFICATE_BASE64` is correctly encoded
- Check certificate password is correct
- Ensure certificate hasn't expired

## Resources

- [Apple Developer - Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Apple Developer - Code Signing](https://developer.apple.com/support/code-signing/)
- [notarytool Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow)
