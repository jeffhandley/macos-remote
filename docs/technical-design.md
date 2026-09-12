# Technical design

## Goals and constraints

macOS Remote provides low-latency input from an iPhone to a Mac without a
network service or user account. The connection must be discoverable nearby,
must require physical confirmation for first use, and must optionally survive
future app launches. The receiver performs privileged input automation, so an
unpaired central must never be able to issue a command.

The product uses native Swift and SwiftUI. CoreBluetooth supplies local
transport, the Security framework stores reconnect credentials, and
CoreGraphics posts input on macOS. The platform-independent protocol is kept in
a Swift package so framing, serialization, timing, and modifier behavior can be
tested on any Swift host.

## Repository layout

```text
src/
  macos-remote/           Shared Swift package target
  macos-remote-macbook/   macOS SwiftUI menu-bar application
  macos-remote-iphone/    iOS SwiftUI application
tests/
  macos-remoteTests/      Shared unit and functional protocol tests
docs/
  README.md               Setup, behavior, and usage
  technical-design.md     This document
Package.swift             Shared library/test build
project.yml               XcodeGen application project
```

`Package.swift` intentionally includes only the shared library and tests. This
keeps `swift test` portable to Linux while XcodeGen composes the Apple-platform
applications with the local `MacOSRemote` package.

## Component architecture

### Shared library

The `MacOSRemote` module contains:

- stable BLE service and characteristic identifiers;
- wire handshake and session message models;
- remote key, modifier, pointer, gesture, and timed-sequence models;
- four-digit code and secure-token generation;
- the modifier activation state machine;
- MLB.tv command definitions; and
- bounded BLE fragmentation and reassembly.

It imports Foundation only. CoreBluetooth, SwiftUI, UIKit, AppKit, Security, and
CoreGraphics remain in their platform targets.

### macOS application

`MacAppModel` owns the receiver state machine. It coordinates:

- `BluetoothPeripheralController`, which publishes the GATT service and
  exchanges framed messages;
- `PairingOverlayController`, which creates full-screen borderless panels;
- `MacCredentialStore`, which stores remembered-device credentials; and
- `InputAutomationController`, which validates Accessibility trust and posts
  keyboard and pointer events.

The SwiftUI `MenuBarExtra` observes `MacAppModel`. No Dock window is created
because `LSUIElement` is enabled. CoreBluetooth delegates use the main queue,
which serializes connection and pairing transitions with UI updates.

### iOS application

`RemoteAppModel` is the presentation and session state machine. It owns:

- `BluetoothCentralController` for scanning, connection, service discovery,
  framing, write flow control, and notifications;
- `IOSDeviceStore` for the stable local client ID, previous-Mac metadata, and
  Keychain credentials; and
- phase state for browsing, connecting, code entry, mode choice, and active
  remote mode.

Each remote is a focused SwiftUI view sharing `ModeHeaderView`. The trackpad
bridges to a custom multi-touch `UIView`; the iOS keyboard bridges to a
`UITextView`; the MacBook layout is data-driven; and MLB.tv actions use shared
command definitions.

## Bluetooth transport

The Mac acts as a BLE peripheral and advertises the primary service below. The
iPhone acts as the central and scans only for that service.

| GATT member | UUID suffix | Direction | Properties |
| --- | --- | --- | --- |
| Remote service | `...1000` | — | Primary service |
| Command | `...1001` | iPhone to Mac | Write / write without response |
| Response | `...1002` | Mac to iPhone | Notify |

Both characteristics require link encryption. The app protocol still performs
its own explicit code confirmation because BLE link establishment alone does
not express user intent to grant input control.

The iPhone uses write-without-response for pointer latency and observes
`canSendWriteWithoutResponse`. It resumes its FIFO from
`peripheralIsReady(toSendWriteWithoutResponse:)`. The Mac uses notification
flow control: if `updateValue` returns false, frames stay queued until
`peripheralManagerIsReady(toUpdateSubscribers:)`.

Advertisements are allowed to repeat so the iPhone can maintain a recent
last-seen time and RSSI. Entries unseen for six seconds are removed unless they
are the active connection. This prevents a stale Mac from appearing nearby.

## Framing and serialization

Messages are JSON-encoded `WireMessage` values. JSON was chosen because both
ends share Codable models, message volumes are low, and captured messages
remain diagnosable. Encoded messages are limited to 32 KiB.

BLE attribute payload length varies with negotiated MTU, so each message is
split into frames. The 15-byte frame header is:

| Bytes | Field |
| --- | --- |
| 0–1 | Magic bytes `MR` |
| 2 | Framing version |
| 3–10 | Random 64-bit message identifier |
| 11–12 | Zero-based frame index, big endian |
| 13–14 | Total frame count, big endian |
| 15… | Payload |

A 15-byte header leaves five payload bytes even with the legacy 20-byte
attribute value limit. Reassembly accepts out-of-order delivery, tolerates an
identical duplicate, rejects conflicting duplicates, and verifies that index
and frame count agree. It limits an endpoint to eight partial messages, caps
assembled size, and evicts partial messages after ten seconds. These bounds
prevent malformed peers from causing unbounded memory growth.

## Pairing and session protocol

The first-connection flow is:

1. The iPhone connects, discovers both characteristics, and subscribes to the
   response characteristic.
2. It sends `hello` with protocol version, stable iPhone client ID, display
   name, and any credential saved for this Mac.
3. If that credential matches a Mac Keychain entry, the Mac skips code entry
   and continues at step 7.
4. Otherwise the Mac generates a random four-digit code and a challenge ID with
   a two-minute expiration. It renders the code locally and sends only the
   challenge ID and expiration to the iPhone.
5. The user chooses **Remember Device** on the Mac and enters the code on the
   iPhone. The iPhone returns the challenge ID and entered code.
6. The Mac compares the code. On success, it optionally creates and stores a
   random 256-bit reconnect credential. On failure, cancellation, or timeout,
   it rejects the connection and clears the overlay.
7. The Mac creates a new random 256-bit session token and returns
   `connectionAccepted`. A newly created reconnect credential is included over
   the encrypted link.

The reconnect credential identifies the iPhone installation to this Mac; it is
not the session authorization value. Every connection receives a fresh session
token. The iPhone includes that token and an increasing 64-bit sequence number
with each command. The Mac executes only commands from the subscribed central
whose token matches and whose sequence is greater than the last accepted
sequence.

The Mac admits one active connection and one pending pairing request. A second
central receives a busy rejection. Disconnect, unsubscribe, Bluetooth loss,
pairing expiry, and pairing cancellation clear transient state and cancel any
running timed key sequence.

## Credential persistence

The Mac Keychain stores one generic-password item per stable iPhone client ID.
UserDefaults stores only the corresponding display name for menu presentation.
Clearing **Remember Device** means no credential is created.

The iPhone stores one generic-password item per CoreBluetooth peripheral
identifier with `AfterFirstUnlockThisDeviceOnly` accessibility. Its
UserDefaults record contains only the peripheral identifier and last known Mac
name. A successfully paired Mac remains in the previous-device list even when
the Mac declined remembrance, but there is then no credential and a new code
is required.

Deleting on one endpoint does not silently mutate the other endpoint. Either
side's missing credential is enough to require fresh code confirmation.

## macOS input execution

Accessibility trust is checked with `AXIsProcessTrusted`. Commands are ignored
until trust is present. Keyboard commands map protocol keys to hardware virtual
key codes and apply CoreGraphics Shift, Control, Option, Command, and secondary
Fn flags. Text commands use Unicode keyboard events in small UTF-16 chunks.

Pointer movement and dragging post CoreGraphics mouse events. Two-finger
scrolling posts pixel scroll events. Two-finger pinch maps to Command-plus or
Command-minus. Three-finger swipes map to standard Control-arrow shortcuts:
up/down for Mission Control/App Exposé and left/right for Spaces.

Peer-provided floating-point deltas are checked for finiteness, and scroll
values are clamped before integer conversion. Ending or losing a connection
always emits mouse-up if a drag is active.

Timed key sequences execute in a cancellable task on the Mac. The MLB.tv
commercial sequence is represented as data rather than a chain of iPhone
timers, keeping its one-second and three-second delays stable if radio writes
are briefly backpressured.

## iOS input implementation

The custom trackpad view enables multiple touches and tracks centroid,
inter-finger distance, duration, and cumulative translation. It latches a
two-finger gesture as scrolling or magnification after a threshold so ordinary
scroll jitter does not alternate into zoom. Three-finger direction is resolved
when the gesture ends.

An almost invisible `UITextView` remains first responder in trackpad mode. That
preserves the system keyboard, QuickPath, language switching, composition,
autocorrection, and emoji. The bridge diffs committed text, emitting backspaces
for replaced text and Unicode for inserted text.

The landscape keyboard uses a shared `ModifierLatch`. Each modifier progresses
from off to one-shot to sticky and back to off. Sending a regular key consumes
only one-shot modifiers. An application delegate restricts supported
orientations to landscape while this mode is active.

## Failure handling

- BLE connection and handshake stages have explicit timeouts and a user-facing
  cancel action.
- Pairing challenges have an absolute expiration checked by both apps.
- Unsupported protocol versions and concurrent connection attempts are
  rejected.
- Stale advertisements age out of the nearby list.
- Notification and write queues respect CoreBluetooth backpressure.
- Malformed frames reset only that central's frame assembler.
- Sequence numbers suppress duplicated or replayed commands.
- Disconnect clears session authorization before returning to discovery.

## Testing strategy

`tests/macos-remoteTests` exercises behavior that does not require Apple
hardware:

- framing at a legacy 20-byte limit, out-of-order assembly, `Data` slices,
  conflicting duplicates, partial-assembly caps, and invalid sizes;
- Codable round trips for every handshake/session message;
- an end-to-end encode, fragment, assemble, and decode flow;
- four-ASCII-digit validation and random code/token shape;
- independent one-shot and sticky modifier transitions; and
- the exact MLB.tv commercial-skip key count and timing.

Run these tests with `swift test`. End-to-end tests require a signed Mac build
and physical iPhone because neither CoreBluetooth peripheral behavior nor
Accessibility event injection is faithfully available in the iOS Simulator or
on non-Apple CI hosts.

## Build and release considerations

XcodeGen makes project settings reviewable and prevents a large generated
project file from obscuring source changes. Release builds must use unique
bundle identifiers and valid signing teams. The macOS app is deliberately not
sandboxed because Accessibility-driven system input injection is its core
function. Distribution therefore requires the appropriate hardened-runtime,
notarization, and user-consent workflow for the chosen channel.

The receiver must remain running to advertise and process commands. The iPhone
target does not request background Bluetooth modes because it is an
interactive foreground remote; disconnecting or suspending it should not leave
an unseen input controller active.
