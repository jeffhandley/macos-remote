import SwiftUI
import UIKit

final class RemoteAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

@main
struct MacOSRemoteIPhoneApp: App {
    @UIApplicationDelegateAdaptor(RemoteAppDelegate.self) private var appDelegate
    @StateObject private var model = RemoteAppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

private struct RootView: View {
    @ObservedObject var model: RemoteAppModel

    var body: some View {
        Group {
            switch model.phase {
            case .browser:
                DeviceBrowserView(model: model)
            case .connecting:
                ConnectionProgressView(model: model)
            case let .pairing(challenge):
                PairingEntryView(model: model, challenge: challenge)
            case .choosingMode:
                ModeChooserView(model: model)
            case let .remote(mode):
                remoteView(mode)
            }
        }
        .animation(.default, value: model.phase)
        .alert(
            "Connection Problem",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.dismissError() } }
            )
        ) {
            Button("OK") {
                model.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func remoteView(_ mode: RemoteMode) -> some View {
        switch mode {
        case .trackpad:
            TrackpadKeyboardView(model: model)
        case .macBookKeyboard:
            MacBookKeyboardView(model: model)
        case .mlbTV:
            MLBTVRemoteView(model: model)
        }
    }
}
