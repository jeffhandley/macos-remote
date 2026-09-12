import MacOSRemote
import SwiftUI

struct DeviceBrowserView: View {
    @ObservedObject var model: RemoteAppModel
    @ObservedObject private var bluetooth: BluetoothCentralController

    init(model: RemoteAppModel) {
        self.model = model
        _bluetooth = ObservedObject(wrappedValue: model.bluetooth)
    }

    private var knownIDs: Set<UUID> {
        Set(model.knownMacs.map(\.id))
    }

    private var newMacs: [NearbyMac] {
        bluetooth.nearbyMacs.filter { !knownIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !model.knownMacs.isEmpty {
                    Section("Previously Paired") {
                        ForEach(model.knownMacs) { device in
                            Button {
                                model.connect(to: device.id)
                            } label: {
                                DeviceRow(
                                    name: device.name,
                                    nearby: bluetooth.isNearby(device.id),
                                    remembered: true
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!bluetooth.isNearby(device.id))
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    model.forget(device)
                                } label: {
                                    Label("Forget", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section("Nearby Macs") {
                    ForEach(newMacs) { mac in
                        Button {
                            model.connect(to: mac.id)
                        } label: {
                            DeviceRow(
                                name: mac.name,
                                nearby: true,
                                remembered: false
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if newMacs.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Searching for Macs running macOS Remote…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if case let .unavailable(message) = bluetooth.state {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("macOS Remote")
        }
    }
}

private struct DeviceRow: View {
    let name: String
    let nearby: Bool
    let remembered: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: remembered ? "checkmark.circle" : "desktopcomputer")
                .font(.title2)
                .foregroundStyle(nearby ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.primary)
                Text(nearby ? "Nearby" : "Not nearby")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if nearby {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ConnectionProgressView: View {
    @ObservedObject var model: RemoteAppModel

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to Mac…")
                .font(.headline)
            Text("Keep macOS Remote running on the Mac.")
                .foregroundStyle(.secondary)
            Button("Cancel", role: .cancel) {
                model.disconnect()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct PairingEntryView: View {
    @ObservedObject var model: RemoteAppModel
    let challenge: PairingChallenge
    @FocusState private var codeIsFocused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "lock.iphone")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Enter Pairing Code")
                    .font(.largeTitle.bold())
                Text("Enter the four-digit code displayed across the Mac screen.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            TextField("0000", text: $model.pairingCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .tracking(14)
                .frame(maxWidth: 230)
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .focused($codeIsFocused)
                .onChange(of: model.pairingCode) { _, newValue in
                    let filtered = newValue.filter(\.isNumber)
                    model.pairingCode = String(filtered.prefix(4))
                }

            Button("Pair") {
                model.submitPairingCode()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.pairingCode.count != 4)

            Button("Cancel", role: .cancel) {
                model.disconnect()
            }
        }
        .padding(30)
        .onAppear {
            codeIsFocused = true
        }
    }
}

struct ModeChooserView: View {
    @ObservedObject var model: RemoteAppModel

    var body: some View {
        NavigationStack {
            List(RemoteMode.allCases) { mode in
                Button {
                    model.chooseMode(mode)
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: mode.systemImage)
                            .font(.title)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.rawValue)
                                .font(.headline)
                            Text(description(for: mode))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(model.connectedMacName ?? "Choose a Remote")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Disconnect", role: .destructive) {
                        model.disconnect()
                    }
                }
            }
        }
    }

    private func description(for mode: RemoteMode) -> String {
        switch mode {
        case .trackpad: "System keyboard with one-, two-, and three-finger gestures"
        case .macBookKeyboard: "A full landscape MacBook Pro keyboard"
        case .mlbTV: "Large playback and commercial-skip controls"
        }
    }
}

struct ModeHeaderView: View {
    @ObservedObject var model: RemoteAppModel
    let currentMode: RemoteMode

    var body: some View {
        HStack {
            Menu {
                ForEach(RemoteMode.allCases) { mode in
                    Button {
                        model.chooseMode(mode)
                    } label: {
                        Label(mode.rawValue, systemImage: mode.systemImage)
                    }
                }
                Divider()
                Button("Choose Mode…") {
                    model.showModeChooser()
                }
                Button("Disconnect", role: .destructive) {
                    model.disconnect()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: currentMode.systemImage)
                    Text(currentMode.rawValue)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            Spacer()
            Text(model.connectedMacName ?? "Mac")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
