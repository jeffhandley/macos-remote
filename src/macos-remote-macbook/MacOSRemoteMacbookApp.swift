import AppKit
import SwiftUI

@main
struct MacOSRemoteMacbookApp: App {
    @StateObject private var model = MacAppModel()

    var body: some Scene {
        MenuBarExtra {
            MacMenuView(model: model)
        } label: {
            Image(systemName: model.isConnected
                ? "iphone.radiowaves.left.and.right"
                : "iphone.slash")
            .accessibilityLabel(model.isConnected ? "iPhone connected" : "iPhone disconnected")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MacMenuView: View {
    @ObservedObject var model: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: model.isConnected
                    ? "iphone.radiowaves.left.and.right"
                    : "iphone.slash")
                .font(.title2)
                .foregroundStyle(model.isConnected ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.connectedDeviceName ?? "No iPhone connected")
                        .font(.headline)
                    Text(model.isConnected ? "Connected" : model.bluetoothState)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !model.accessibilityGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Accessibility permission is required for remote input.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                    Button("Open Accessibility Prompt") {
                        model.requestAccessibility()
                    }
                }
                .padding(10)
                .background(.orange.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if model.isConnected {
                Button("Disconnect iPhone", role: .destructive) {
                    model.disconnect()
                }
            }

            if !model.rememberedDevices.isEmpty {
                Divider()
                Text("Remembered Devices")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(model.rememberedDevices) { device in
                    HStack {
                        Label(device.name, systemImage: "iphone")
                            .lineLimit(1)
                        Spacer()
                        Button("Forget") {
                            model.forget(device)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Divider()
            HStack {
                Button("Refresh Permissions") {
                    model.refreshAccessibility()
                }
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 330)
    }
}
