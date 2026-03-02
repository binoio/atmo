# Quick Start Checklist for Signed Releases

## Prerequisites
- [ ] Active Apple Developer subscription
- [ ] Developer ID Application certificate installed in Keychain
- [ ] Xcode Command Line Tools installed (`xcode-select --install`)

## Local Signing Setup (5 minutes)

### 1. Find Your Signing Identity
```bash
security find-identity -v -p codesigning
```
Look for a line like:
```
Developer ID Application: Your Name (TEAM_ID)
```

### 2. Create App-Specific Password
1. Go to https://appleid.apple.com
2. Navigate to **Security → App-Specific Passwords**
3. Click **Generate an app-specific password**
4. Name it "Atmo Notarization"
5. Save the password (format: `xxxx-xxxx-xxxx-xxxx`)

### 3. Set Environment Variables
```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAM_ID)"
export APPLEID="your-apple-id@example.com"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

### 4. Test the Setup
```bash
cd AppleTVRemoteApp
./Scripts/signing_helper.sh list-identities
./Scripts/signing_helper.sh test-sign
```

### 5. Create First Signed Release
```bash
./Scripts/notarize_and_release.sh
```

## GitHub Actions Setup (10 minutes)

### 1. Export Your Certificate
```bash
# Using Keychain Access:
# 1. Open Keychain Access
# 2. Find "Developer ID Application" certificate
# 3. Right-click → Export → Save as certificate.p12 with password

# Or use command line:
cd AppleTVRemoteApp
./Scripts/signing_helper.sh export-cert
```

### 2. Convert to Base64
```bash
# Certificate
base64 -i certificate.p12 | pbcopy

# If using API key (recommended):
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

### 3. Add GitHub Secrets
Go to your repository: **Settings → Secrets and variables → Actions**

Add these secrets:

**Required:**
- `DEVELOPER_ID_P12` - Paste base64 certificate
- `DEVELOPER_ID_CERT_PASSWORD` - Your .p12 password
- `DEVELOPER_ID_APPLICATION` - Full identity string

**Notarization (Option A - Simple):**
- `APPLEID` - Your Apple ID email
- `APP_SPECIFIC_PASSWORD` - From step 2 above

**Notarization (Option B - Recommended for CI):**
- `NOTARY_KEY` - Base64-encoded .p8 API key
- `NOTARY_KEY_ID` - Key ID from App Store Connect
- `NOTARY_ISSUER_ID` - Issuer ID from App Store Connect

### 4. Test the Workflow
```bash
# Create and push a tag
git tag v0.1.0-test
git push origin v0.1.0-test

# Or use manual workflow dispatch in GitHub Actions UI
```

## Troubleshooting

### "No identity found"
```bash
# Check installed certificates
security find-identity -v -p codesigning

# If missing, download from developer.apple.com
```

### "Notarization failed"
```bash
# Check recent submission
xcrun notarytool history --apple-id YOUR_APPLE_ID

# Get detailed log
xcrun notarytool log SUBMISSION_ID --apple-id YOUR_APPLE_ID
```

### "Codesign failed" in GitHub Actions
- Verify `DEVELOPER_ID_P12` is correctly base64-encoded
- Check certificate password is correct
- Ensure certificate hasn't expired

## Success Indicators

✓ Local signing produces `dist/Atmo-stapled.zip`
✓ `spctl -a -vvv -t install dist/Atmo.app` shows "accepted"
✓ `codesign -vvv --deep --strict dist/Atmo.app` succeeds
✓ GitHub Actions workflow completes successfully
✓ GitHub release is created with `Atmo-stapled.zip` attached

## Next Steps After Setup

1. **Test the signed app** on a different Mac
2. **Update version** in `Support/Info.plist`
3. **Create release tag** for production
4. **Download and verify** from GitHub Releases

## Resources

- Full documentation: [docs/SIGNING.md](docs/SIGNING.md)
- Apple's guide: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
- Setup overview: [SIGNED_RELEASE_SETUP.md](SIGNED_RELEASE_SETUP.md)

---

**Time estimate:** 
- Local setup: 5-10 minutes
- GitHub Actions setup: 10-15 minutes
- Total: 15-25 minutes
