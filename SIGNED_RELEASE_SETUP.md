# Signed Release Branch Summary

This branch (`signed-releases`) sets up a complete workflow for code-signed and notarized macOS releases using your Apple Developer subscription.

## What's Been Added

### 1. Entitlements File
**File:** `AppleTVRemoteApp/Support/Atmo.entitlements`

Defines the sandboxing and permissions for the signed app:
- App sandboxing enabled
- Network client access (for Apple TV communication)
- User-selected file access
- Apple Events automation

### 2. Signing & Notarization Scripts

#### `AppleTVRemoteApp/Scripts/sign_and_notarize.sh`
Standalone script that handles the full signing and notarization workflow:
- Signs all Mach-O binaries in the bundle
- Signs the main app bundle with entitlements
- Submits to Apple's notarization service
- Staples the notarization ticket
- Creates final distribution ZIP

**Required environment variables:**
- `APPLE_DEVELOPER_ID` - Your name as it appears on the certificate
- `APPLE_TEAM_ID` - Your Apple Team ID
- `APPLE_ID` - Your Apple ID email
- `APPLE_APP_SPECIFIC_PASSWORD` - App-specific password

#### `AppleTVRemoteApp/Scripts/signing_helper.sh`
Developer convenience tool with subcommands:
- `list-identities` - Show available signing identities
- `verify-app` - Verify signature of built app
- `check-notarize` - Check notarization status
- `show-entitlements` - Display app entitlements
- `export-cert` - Guide for exporting certificates
- `test-sign` - Quick test signing without notarization
- `full-release` - Run complete release workflow

### 3. GitHub Actions Workflow
**File:** `.github/workflows/notarize-release.yml` (updated)

Automated CI/CD workflow that:
- Triggers on version tags (`v*`) or manual dispatch
- Builds the Python environment
- Compiles the Swift app
- Signs with Developer ID certificate
- Submits for notarization
- Staples the notarization ticket
- Creates GitHub release with signed artifact

**Workflow improvements:**
- Added tag-based automatic releases
- Version input for manual releases
- GitHub release creation with signed assets
- Proper cleanup of sensitive keychain data

### 4. Documentation
**File:** `docs/SIGNING.md`

Comprehensive guide covering:
- Prerequisites and setup
- Local signing configuration
- GitHub Actions secrets setup
- Creating app-specific passwords
- Creating API keys for notarization
- Triggering releases
- Troubleshooting common issues

## Quick Start Guide

### Local Signing

1. **Export your Developer ID certificate:**
   ```bash
   # Use Keychain Access or:
   AppleTVRemoteApp/Scripts/signing_helper.sh export-cert
   ```

2. **Set environment variables:**
   ```bash
   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM_ID)"
   export APPLEID="your-apple-id@example.com"
   export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
   ```

3. **Run the release script:**
   ```bash
   cd AppleTVRemoteApp
   ./Scripts/notarize_and_release.sh
   ```

### GitHub Actions Setup

Configure these secrets in your GitHub repository (**Settings → Secrets and variables → Actions**):

**Certificate:**
- `DEVELOPER_ID_P12` - Base64-encoded .p12 certificate
- `DEVELOPER_ID_CERT_PASSWORD` - Password for the .p12 file
- `DEVELOPER_ID_APPLICATION` - Full signing identity string

**Notarization (choose one):**

Option A - App-Specific Password:
- `APPLEID` - Your Apple ID
- `APP_SPECIFIC_PASSWORD` - From appleid.apple.com

Option B - API Key (recommended):
- `NOTARY_KEY` - Base64-encoded .p8 file
- `NOTARY_KEY_ID` - Key ID from App Store Connect
- `NOTARY_ISSUER_ID` - Issuer ID from App Store Connect

### Triggering Releases

**Automatic (on tag):**
```bash
git tag v1.0.0
git push origin v1.0.0
```

**Manual:**
Go to GitHub Actions → "Build, Notarize and Release" → Run workflow

## Integration with Existing Setup

This branch works alongside the existing release infrastructure:

- ✅ `Scripts/release.sh` - Still builds unsigned app bundle
- ✅ `Scripts/notarize_and_release.sh` - Enhanced with better error handling
- ✅ `NOTARIZE.md` - Updated to reference new documentation
- ✅ `RELEASE.md` - No changes needed (already references notarization)
- ✅ GitHub workflow - Enhanced with tag triggers and release creation

## Testing the Setup

1. **Test without notarization:**
   ```bash
   cd AppleTVRemoteApp
   ./Scripts/signing_helper.sh test-sign
   ```

2. **Verify signatures:**
   ```bash
   ./Scripts/signing_helper.sh verify-app
   ```

3. **Full local test:**
   ```bash
   export DEVELOPER_ID_APPLICATION="..." # Your identity
   export APPLEID="..." # Your Apple ID
   export APP_SPECIFIC_PASSWORD="..." # Your password
   ./Scripts/notarize_and_release.sh
   ```

## Next Steps

1. **Set up secrets** in your GitHub repository
2. **Test locally** with `signing_helper.sh test-sign`
3. **Create a test tag** to verify the workflow
4. **Merge to main** when ready for production releases

## Security Notes

- Never commit certificates or passwords to git
- Use GitHub secrets for all sensitive data
- App-specific passwords can be revoked at appleid.apple.com
- API keys can be revoked in App Store Connect
- Temporary keychains are cleaned up after workflow runs

## Resources

- [Full Documentation](docs/SIGNING.md)
- [Apple Developer - Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [notarytool Documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow)
