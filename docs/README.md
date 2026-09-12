# macOS Remote

macOS Remote is a pair of native SwiftUI apps:

- **macOS Remote for Mac** advertises itself over Bluetooth Low Energy (BLE),
  receives authenticated input commands, and posts keyboard and pointer events.
- **macOS Remote for iPhone** discovers nearby Macs, pairs with them, and
  provides trackpad, keyboard, and MLB.tv control modes.

## Requirements

- A Mac running macOS 14 or later with Bluetooth
- An iPhone running iOS 17 or later with Bluetooth
- The Mac app running while pairing or using the remote
- Accessibility permission for the Mac app

The apps communicate directly over BLE. They do not need a shared Wi-Fi
network, an account, or an internet connection. Discovery and pairing happen
inside the iPhone app's **Nearby Macs** screen rather than in the system
Bluetooth Settings screen.

## Install a published release

Publishing a GitHub release triggers the **Release installers** workflow on a
GitHub-hosted macOS runner. When it succeeds:

1. Open **Actions > Release installers** in this repository.
2. Open the run whose title matches the published release.
3. Download and extract both artifacts listed at the bottom of the run.
4. On the Mac, open `macos-remote-macOS-VERSION.pkg` and complete Installer.
   The package is Developer ID signed, notarized, and stapled for Gatekeeper.
5. Connect the iPhone to a Mac and open Apple Configurator.
6. Select the iPhone and add `macos-remote-iPhone-VERSION.ipa`.

The IPA uses Apple Ad Hoc distribution. Installation works only when the
iPhone's UDID was registered in the Apple Developer account and included in
the provisioning profile used for that release. It is not an App Store or
TestFlight build. To support another iPhone, update the profile and repository
secret before publishing another release.

GitHub retains these workflow artifacts for 90 days. The repository must be
configured with Apple Developer signing material before the workflow can run;
maintainers should follow
[Apple Developer release configuration](apple-developer-release.md).

## Build and install from source

1. Install Xcode 16 or later and XcodeGen.
2. From the repository root, run `xcodegen generate`.
3. Open `macos-remote.xcodeproj`.
4. Select a signing team for the `macos-remote-macbook` and
   `macos-remote-iphone` targets. Change the bundle identifiers if your signing
   team does not own the configured identifiers.
5. Build `macos-remote-macbook` for the Mac.
6. Build `macos-remote-iphone` for a physical iPhone. The iOS Simulator cannot
   exercise the BLE connection.

The shared library and its platform-independent tests can also be built with
`swift test`.

## First launch on the Mac

The Mac app is a menu-bar utility and does not open a normal Dock window. Its
menu-bar item uses:

- an iPhone-with-radio-waves symbol, similar to 📳, while connected;
- an iPhone-with-slash symbol, similar to 📴, while disconnected.

Open the menu to view Bluetooth and connection status. The app prompts for
Accessibility permission the first time it runs. If permission is not granted,
choose **Open Accessibility Prompt**, enable macOS Remote in **System Settings
> Privacy & Security > Accessibility**, and then choose **Refresh
Permissions**. Bluetooth can still connect without Accessibility permission,
but the Mac intentionally ignores remote input until permission is granted.

The menu also lists devices the Mac has remembered. Choose **Forget** beside a
device to revoke its saved reconnect credential. Forgetting a device does not
end an already-active session; it requires a new pairing code on the next
connection.

## Pair an iPhone

1. Keep the Mac app running and Bluetooth enabled on both devices.
2. Open the iPhone app.
3. Select the Mac under **Nearby Macs**.
4. The Mac covers every display with a semi-transparent gray pairing overlay.
   A random four-digit numeric code appears in four opaque white rectangles.
5. On the Mac, select or clear **Remember Device**.
6. Enter the four digits on the iPhone. The numeric keyboard appears
   automatically, and **Pair** becomes available after four digits are entered.

The code expires after two minutes. It must match exactly. A canceled, expired,
or incorrect request does not create a session.

**Remember Device is controlled only by the Mac.** When selected, the Mac and
iPhone save a long-lived credential in their Keychains, allowing subsequent
connections without another code. When cleared, the iPhone still shows the Mac
as a previously paired device, but connecting again requires a fresh code.

After a successful connection, the iPhone presents the remote-mode chooser.

## Previously paired and nearby devices

The entry screen separates:

- **Previously Paired** Macs, including remembered Macs and Macs that require a
  fresh code; and
- other currently discoverable **Nearby Macs**.

A previous Mac that is not advertising is shown as **Not nearby** and cannot be
selected. Swipe a previous device to the left and tap the trash button to
forget its local record and Keychain credential. Connecting to that Mac again
then requires normal discovery and fresh pairing. The Mac's own remembered
credential can be revoked independently from its menu.

Connection attempts time out rather than leaving the app on a permanent
spinner. The connecting screen also provides a **Cancel** button.

## Remote modes

Every active mode has a menu at the top. Use it to change modes, return to the
mode chooser, or disconnect. Disconnecting closes the BLE connection and
returns the iPhone app to the device entry screen.

### Trackpad & iOS Keyboard

The upper part of the screen is a multi-touch trackpad. The lower part is the
normal iOS keyboard, including QuickPath/swipe entry, suggestions, alternate
languages, and emoji.

Trackpad controls are:

| Gesture | Mac action |
| --- | --- |
| Move one finger | Move the pointer |
| Tap one finger | Primary click |
| Double-tap one finger | Double-click |
| Hold, then move one finger | Drag |
| Move two fingers | Scroll horizontally or vertically |
| Tap two fingers | Secondary click |
| Pinch two fingers | Zoom using Command-plus or Command-minus |
| Swipe three fingers up/down | Mission Control/App Exposé shortcuts |
| Swipe three fingers left/right | Move between Spaces shortcuts |

Three-finger actions use the standard Control-arrow macOS shortcuts and
therefore follow the shortcuts configured in System Settings.

Text committed by the iOS input system is sent as Unicode, so composed text,
accented characters, swipe-entered words, and emoji are preserved. Return and
backspace are sent as Mac keys.

### MacBook Keyboard

This mode requests and locks a landscape presentation. It displays a MacBook
Pro-style keyboard, including Escape and F1 through F12 on the top row. The
bottom row contains:

`fn`, `control`, `option`, `command`, `space`, `command`, `option`, left arrow,
up arrow, down arrow, and right arrow.

Modifier keys cycle independently through three states:

1. **Normal** — off.
2. **Blue** — one-shot; included with the next non-modifier key, then cleared.
3. **Green** — sticky; included with every key until changed.

Tap a modifier once for blue, again for green, and a third time to turn it off.
Multiple modifiers can be active at the same time. Both visible copies of
Shift, Command, and Option control their corresponding shared modifier state.

### MLB.tv

This mode uses large full-screen controls:

- **Pause / Play** sends Space.
- **Full Screen** sends `F`.
- **Skip Forward 10s** sends Right Arrow once.
- **Back 10s** sends Left Arrow once.
- **Skip Commercials** sends Escape, sends Right Arrow 12 times with a
  one-second pause between presses, waits three seconds, and sends `F`.

The commercial-skip sequence runs on the Mac so BLE scheduling jitter does not
alter its timing. Starting another commercial-skip sequence replaces the
current sequence, and disconnecting cancels it.

## Privacy and security

- BLE characteristics require an encrypted link.
- The four-digit code is generated with the system random-number generator and
  is never sent to the iPhone.
- A correct response creates a random per-connection session token.
- Remembered credentials and iPhone-side Mac credentials are stored in the
  Keychain, not in preferences.
- Commands require the active session token and a strictly increasing sequence
  number, which prevents replay within a session.
- Only one iPhone can control the Mac at a time.
- The Mac app posts input only after Accessibility permission is granted.

## Troubleshooting

- **The Mac is not listed:** Confirm the Mac app is running, Bluetooth is on,
  and the menu says **Available for pairing**. Move the devices closer.
- **The Mac is listed as Not nearby:** Open the Mac app and wait a few seconds
  for a fresh advertisement.
- **Pairing failed:** Start a new attempt and enter the newly displayed code
  before it expires.
- **Connected but input does nothing:** Grant and refresh Accessibility
  permission from the Mac menu.
- **The keyboard mode remains portrait:** Ensure orientation lock is disabled
  in Control Center; the app will then request landscape again when entering
  the mode.
- **MLB.tv shortcuts do not work:** Make sure the browser player has keyboard
  focus and its keyboard shortcuts have not changed.
