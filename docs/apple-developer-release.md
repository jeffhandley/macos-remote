# Apple Developer release configuration

The release workflow creates two installable artifacts:

- a Developer ID signed and notarized macOS installer package (`.pkg`); and
- an Ad Hoc signed iPhone application (`.ipa`).

Both require an active Apple Developer Program membership and private signing
material. The workflow runs only for a published GitHub release and reads its
secrets from the `release` GitHub environment.

## 1. Create Apple identifiers and certificates

Use the Apple Developer portal to ensure the team owns these explicit App IDs:

- `com.jeffhandley.macos-remote.macbook`
- `com.jeffhandley.macos-remote.iphone`

Create these certificates with their private keys:

1. **Developer ID Application** for signing the Mac app.
2. **Developer ID Installer** for signing the Mac installer package.
3. **Apple Distribution** for signing the Ad Hoc iPhone app.

Install the certificates on a trusted Mac. In Keychain Access, export the
Developer ID Application and Developer ID Installer certificates with their
private keys into one password-protected `macos-release.p12`. Export the Apple
Distribution certificate and private key into a separate
`ios-distribution.p12`.

Record the exact certificate names shown by Keychain Access. They normally
look like:

```text
Developer ID Application: Organization Name (TEAMID)
Developer ID Installer: Organization Name (TEAMID)
Apple Distribution: Organization Name (TEAMID)
```

Never commit either P12 file or its password.

## 2. Create the iOS Ad Hoc profile

1. Register every permitted iPhone's UDID in the Apple Developer portal.
2. Create an **Ad Hoc** provisioning profile for
   `com.jeffhandley.macos-remote.iphone`.
3. Select the Apple Distribution certificate exported above.
4. Include every iPhone that should be able to install the release artifact.
5. Download the resulting `.mobileprovision` file.

Adding a device or renewing an expired certificate requires regenerating the
profile and replacing the corresponding GitHub secret. An Ad Hoc IPA cannot be
installed on an iPhone omitted from this profile.

## 3. Create a notarization API key

In **App Store Connect > Users and Access > Integrations**, create a team API
key that can submit software to Apple's notary service. Save its:

- Key ID;
- Issuer ID; and
- downloaded `AuthKey_KEYID.p8` private key.

Apple allows the private key to be downloaded only once. Store it securely and
never commit it.

## 4. Encode the binary secrets

On macOS, Base64 encode each binary file without modifying it:

```sh
base64 -i macos-release.p12 | pbcopy
base64 -i ios-distribution.p12 | pbcopy
base64 -i macos-remote-adhoc.mobileprovision | pbcopy
base64 -i AuthKey_KEYID.p8 | pbcopy
```

Run one command at a time and paste the clipboard into the matching secret
below. Base64 is transport encoding, not encryption; the values must remain
GitHub secrets.

## 5. Configure the GitHub release environment

In the repository, open **Settings > Environments**, create an environment
named `release`, and add these environment secrets:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | The ten-character Apple Developer Team ID |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64 of `macos-release.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting that P12 |
| `MACOS_APPLICATION_SIGNING_IDENTITY` | Exact Developer ID Application certificate name |
| `MACOS_INSTALLER_SIGNING_IDENTITY` | Exact Developer ID Installer certificate name |
| `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | Base64 of `ios-distribution.p12` |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password used when exporting that P12 |
| `IOS_DISTRIBUTION_SIGNING_IDENTITY` | Exact Apple Distribution certificate name |
| `IOS_ADHOC_PROVISIONING_PROFILE_BASE64` | Base64 of the Ad Hoc `.mobileprovision` |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | Base64 of `AuthKey_KEYID.p8` |

Environment secrets are preferred over repository-wide secrets because only
the two packaging jobs request the `release` environment. Configure required
reviewers and deployment branch/tag protections there if the repository's
GitHub plan supports them.

The workflow creates a temporary random-password Keychain on each
GitHub-hosted runner, imports only the credentials needed by that job, and
deletes the Keychain and decoded files in an `always()` cleanup step.

## 6. Publish a release

1. Ensure the release commit contains the desired source.
2. Create a tag named `vMAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH`, such as
   `v1.2.0`.
3. Create and publish a GitHub release for that tag.
4. Approve the `release` environment deployment if approval is configured.
5. Open **Actions > Release installers** and monitor all three jobs.

The workflow checks out the release tag, runs `swift test`, generates the Xcode
project, and builds both apps on `macos-15` with Xcode 16.4. It then:

- signs the Mac app with hardened runtime, packages it with the Developer ID
  Installer identity, submits it to Apple notarization, staples the ticket, and
  verifies Gatekeeper acceptance; and
- validates the iOS profile's team, bundle identifier, and registered-device
  list before archiving and exporting an Ad Hoc IPA.

The completed run stores the `.pkg` and `.ipa` as separate GitHub Actions
artifacts for 90 days.

## Rotation and troubleshooting

- **Certificate expired or revoked:** create a replacement certificate, export
  a new P12, regenerate profiles that use it, and replace the secrets.
- **Provisioning profile rejected:** verify it is an Ad Hoc profile for the
  exact iPhone bundle identifier and Apple team, and that it has not expired.
- **IPA will not install:** add the device UDID, regenerate the Ad Hoc profile,
  replace `IOS_ADHOC_PROVISIONING_PROFILE_BASE64`, and publish a new release.
- **Notarization fails:** confirm the API key belongs to the same team and has
  access to the notary service. The workflow prints Apple's submission result.
- **Signing identity not found:** make the identity secret exactly match the
  certificate's Keychain name and ensure the exported P12 includes its private
  key.

Do not upload signing files to workflow artifacts, release assets, issues, or
logs. If a secret may have been exposed, revoke it in Apple Developer or App
Store Connect before replacing the GitHub secret.
