import AppKit
import SwiftUI

@MainActor
final class PairingOverlayController {
    @Published var rememberDevice = true

    private var windows: [NSPanel] = []
    private var code = ""
    private var onCancel: (() -> Void)?

    func present(code: String, onCancel: @escaping () -> Void) {
        dismiss()
        self.code = code
        self.onCancel = onCancel
        rememberDevice = true

        windows = NSScreen.screens.map { screen in
            let panel = PairingPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(
                rootView: PairingCodeView(
                    code: code,
                    rememberDevice: Binding(
                        get: { [weak self] in self?.rememberDevice ?? false },
                        set: { [weak self] in self?.rememberDevice = $0 }
                    ),
                    cancel: { [weak self] in self?.onCancel?() }
                )
            )
            panel.orderFrontRegardless()
            return panel
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        onCancel = nil
    }
}

private final class PairingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct PairingCodeView: View {
    let code: String
    @Binding var rememberDevice: Bool
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.gray.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Text("Pair iPhone")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Enter this code on your iPhone")
                    .font(.title3)
                    .foregroundStyle(.white)

                HStack(spacing: 16) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(width: 82, height: 98)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pairing code \(code)")

                Toggle("Remember Device", isOn: $rememberDevice)
                    .toggleStyle(.checkbox)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .fixedSize()

                Button("Cancel Pairing", action: cancel)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(48)
        }
    }
}
