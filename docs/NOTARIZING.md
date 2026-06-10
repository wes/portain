# Signing & Notarizing Portain

By default Portain ships **ad-hoc signed**, so macOS shows *"Apple could not
verify…"* on first launch and users must allow it via **System Settings →
Privacy & Security → Open Anyway** (or `xattr -dr com.apple.quarantine`).

To make the app launch with no warning for everyone, sign it with a **Developer
ID Application** certificate and **notarize** it with Apple. This requires a paid
[Apple Developer Program](https://developer.apple.com/programs/) membership
($99/year).

## One-time setup

1. **Create a Developer ID Application certificate** in Xcode
   (Settings → Accounts → Manage Certificates → ＋ → *Developer ID Application*),
   or on the Apple Developer website. Confirm it's in your keychain:

   ```sh
   security find-identity -v -p codesigning
   # → "Developer ID Application: Your Name (TEAMID)"
   ```

2. **Store notarization credentials** in your keychain once. Use an
   [app-specific password](https://support.apple.com/en-us/102654) for your
   Apple ID:

   ```sh
   xcrun notarytool store-credentials portain-notary \
     --apple-id "you@example.com" \
     --team-id "TEAMID" \
     --password "abcd-efgh-ijkl-mnop"   # app-specific password
   ```

## Build a notarized release locally

`scripts/release.sh` signs and notarizes automatically when these env vars are
set:

```sh
export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="portain-notary"
scripts/release.sh 1.1.0
```

This produces a hardened-runtime, signed, **stapled** `.app` inside
`dist/Portain-1.1.0.dmg` and `.zip`. Verify:

```sh
spctl -a -vv /Applications/Portain.app     # → accepted, source=Notarized Developer ID
xcrun stapler validate dist/Portain-1.1.0.dmg
```

Portain launches subprocesses (`docker`, `lsof`, `kill`) but needs **no special
entitlements** — the default hardened runtime is sufficient.

## Notarizing in CI (GitHub Actions)

Add these repository **Secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12` | base64 of your exported `Developer ID Application.p12` |
| `MACOS_CERT_PASSWORD` | password you set when exporting the `.p12` |
| `DEVELOPER_ID_APP` | `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | your 10-char Team ID |
| `APPLE_APP_PASSWORD` | app-specific password |

Export the `.p12` and base64 it:

```sh
# In Keychain Access: right-click the cert → Export → .p12
base64 -i DeveloperIDApplication.p12 | pbcopy   # paste into MACOS_CERT_P12
```

Then add a step before `scripts/release.sh` in `.github/workflows/release.yml`
to import the certificate into a temporary keychain and store a notary profile:

```yaml
      - name: Import signing certificate
        env:
          MACOS_CERT_P12: ${{ secrets.MACOS_CERT_P12 }}
          MACOS_CERT_PASSWORD: ${{ secrets.MACOS_CERT_PASSWORD }}
        run: |
          KEYCHAIN="$RUNNER_TEMP/build.keychain"
          security create-keychain -p "" "$KEYCHAIN"
          security set-keychain-settings "$KEYCHAIN"
          security unlock-keychain -p "" "$KEYCHAIN"
          security list-keychains -d user -s "$KEYCHAIN" login.keychain
          echo "$MACOS_CERT_P12" | base64 --decode > cert.p12
          security import cert.p12 -k "$KEYCHAIN" -P "$MACOS_CERT_PASSWORD" \
            -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -k "" "$KEYCHAIN"
          xcrun notarytool store-credentials portain-notary \
            --apple-id "${{ secrets.APPLE_ID }}" \
            --team-id "${{ secrets.APPLE_TEAM_ID }}" \
            --password "${{ secrets.APPLE_APP_PASSWORD }}"
```

…and pass the identity into the build step:

```yaml
      - name: Build & package
        env:
          DEVELOPER_ID_APP: ${{ secrets.DEVELOPER_ID_APP }}
          NOTARY_PROFILE: portain-notary
        run: bash scripts/release.sh "${GITHUB_REF_NAME#v}"
```

That's it — the published `.dmg`/`.zip` will open cleanly on any Mac with no
Gatekeeper prompt.
