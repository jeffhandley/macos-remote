# macos-remote

An iOS/macOS pair of apps that turns an iPhone into a Bluetooth keyboard,
trackpad, and MLB.tv remote for a Mac.

- [Setup, usage, and behavior](docs/README.md)
- [Technical design](docs/technical-design.md)

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
