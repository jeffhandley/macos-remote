# macos-remote

An iOS/macOS pair of apps that turns an iPhone into a Bluetooth keyboard,
trackpad, and MLB.tv remote for a Mac.

- [Setup, usage, and behavior](docs/README.md)
- [Technical design](docs/technical-design.md)
- [Release signing configuration](docs/apple-developer-release.md)

## Install a release

Publishing a GitHub release with a `vMAJOR.MINOR.PATCH` or
`MAJOR.MINOR.PATCH` tag runs the **Release installers** workflow. After it
finishes, open that workflow run on the repository's **Actions** tab and
download its two artifacts:

- **macos-remote-macOS-VERSION** contains a signed and notarized `.pkg`. Extract
  the artifact, open the package on the Mac, and complete Installer. Start
  macOS Remote, then grant Accessibility access when prompted.
- **macos-remote-iPhone-VERSION** contains an Ad Hoc signed `.ipa`. The iPhone's
  UDID must be included in the release provisioning profile. Connect the iPhone
  to a Mac, open Apple Configurator, and add the extracted IPA to the device.

iOS rejects an Ad Hoc IPA on devices absent from its provisioning profile. See
[release signing configuration](docs/apple-developer-release.md) for Apple
Developer setup and profile renewal instructions.

## Development

The shared protocol is a Swift package:

```sh
swift test
```

The application project is generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open macos-remote.xcodeproj
```

Both apps require a physical Apple device for end-to-end Bluetooth testing.
