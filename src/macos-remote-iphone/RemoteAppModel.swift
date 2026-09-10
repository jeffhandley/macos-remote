import Combine
import Foundation
import MacOSRemote
import UIKit

enum RemoteMode: String, CaseIterable, Identifiable {
    case trackpad = "Trackpad & iOS Keyboard"
    case macBookKeyboard = "MacBook Keyboard"
    case mlbTV = "MLB.tv"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .macBookKeyboard: "keyboard"
        case .mlbTV: "baseball"
        }
    }
}

enum RemotePhase: Equatable {
    case browser
    case connecting
    case pairing(PairingChallenge)
    case choosingMode
    case remote(RemoteMode)
}

@MainActor
final class RemoteAppModel: ObservableObject {
    @Published private(set) var phase: RemotePhase = .browser
    @Published private(set) var knownMacs: [KnownMac] = []
    @Published private(set) var connectedMacName: String?
    @Published var pairingCode = ""
    @Published var errorMessage: String?

    let bluetooth = BluetoothCentralController()

    private let store = IOSDeviceStore()
    private var currentPeripheralID: UUID?
    private var sessionToken: String?
    private var commandSequence: UInt64 = 0
    private var isDisconnecting = false
    private var connectionTimeoutTask: Task<Void, Never>?

    init() {
        knownMacs = store.devices
        bluetooth.onReady = { [weak self] peripheralID in
            self?.sendHello(to: peripheralID)
        }
        bluetooth.onMessage = { [weak self] message in
            self?.handle(message)
        }
        bluetooth.onDisconnect = { [weak self] error in
            self?.handleDisconnect(error)
        }
    }

    func connect(to peripheralID: UUID) {
        guard bluetooth.isNearby(peripheralID) else {
            errorMessage = "That Mac is not currently nearby."
            return
        }
        currentPeripheralID = peripheralID
        phase = .connecting
        bluetooth.connect(to: peripheralID)
        scheduleConnectionTimeout(
            after: 20,
            message: "The Mac did not respond. Make sure macOS Remote is running and try again."
        )
    }

    func submitPairingCode() {
        guard case let .pairing(challenge) = phase,
              let code = PairingCode(pairingCode)
        else {
            return
        }
        phase = .connecting
        scheduleConnectionTimeout(
            after: 15,
            message: "The Mac did not confirm the pairing code."
        )
        bluetooth.send(.pairingResponse(PairingResponse(
            requestID: challenge.requestID,
            code: code.value
        )))
    }

    func chooseMode(_ mode: RemoteMode) {
        guard sessionToken != nil else {
            return
        }
        phase = .remote(mode)
        AppOrientation.request(
            mode == .macBookKeyboard ? .landscape : .portrait
        )
    }

    func showModeChooser() {
        guard sessionToken != nil else {
            return
        }
        phase = .choosingMode
        AppOrientation.request(.allButUpsideDown)
    }

    func send(_ command: RemoteCommand) {
        guard let sessionToken else {
            return
        }
        guard commandSequence < UInt64.max else {
            disconnect()
            return
        }
        commandSequence += 1
        bluetooth.send(.command(SessionCommand(
            sessionToken: sessionToken,
            sequence: commandSequence,
            command: command
        )))
    }

    func disconnect() {
        if let sessionToken {
            bluetooth.send(.disconnect(sessionToken: sessionToken))
        }
        isDisconnecting = true
        clearSession()
        phase = .browser
        AppOrientation.request(.portrait)
        bluetooth.disconnect()
    }

    func forget(_ device: KnownMac) {
        if currentPeripheralID == device.id, sessionToken != nil {
            disconnect()
        }
        store.forget(device)
        knownMacs = store.devices
    }

    func dismissError() {
        errorMessage = nil
    }

    private func sendHello(to peripheralID: UUID) {
        currentPeripheralID = peripheralID
        bluetooth.send(.hello(ClientHello(
            deviceID: store.clientID,
            displayName: UIDevice.current.name,
            credential: store.credential(for: peripheralID)
        )))
    }

    private func handle(_ message: WireMessage) {
        switch message {
        case let .pairingChallenge(challenge):
            guard challenge.expiresAt > Date() else {
                failAndDisconnect("The pairing code expired. Try again.")
                return
            }
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            pairingCode = ""
            phase = .pairing(challenge)
        case let .connectionAccepted(accepted):
            accept(accepted)
        case let .connectionRejected(reason):
            failAndDisconnect(reason)
        case let .disconnect(token):
            guard token == sessionToken else {
                return
            }
            errorMessage = "The Mac ended the connection."
            isDisconnecting = true
            clearSession()
            phase = .browser
            AppOrientation.request(.portrait)
            bluetooth.disconnect()
        case let .ping(identifier):
            bluetooth.send(.pong(identifier))
        case .hello, .pairingResponse, .command, .pong:
            break
        }
    }

    private func accept(_ accepted: ConnectionAccepted) {
        guard let currentPeripheralID else {
            return
        }
        sessionToken = accepted.sessionToken
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        connectedMacName = accepted.serverName
        commandSequence = 0

        let device = KnownMac(id: currentPeripheralID, name: accepted.serverName)
        if let credential = accepted.credential {
            store.remember(device, credential: credential)
        } else if accepted.remembered {
            store.update(device)
        } else {
            store.remember(device, credential: nil)
        }
        knownMacs = store.devices
        phase = .choosingMode
    }

    private func failAndDisconnect(_ reason: String) {
        errorMessage = reason
        isDisconnecting = true
        clearSession()
        phase = .browser
        bluetooth.disconnect()
    }

    private func handleDisconnect(_ error: Error?) {
        let expected = isDisconnecting
        isDisconnecting = false
        clearSession()
        phase = .browser
        AppOrientation.request(.portrait)
        if !expected {
            errorMessage = error?.localizedDescription ?? "The Mac disconnected."
        }
    }

    private func clearSession() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        sessionToken = nil
        currentPeripheralID = nil
        connectedMacName = nil
        commandSequence = 0
        pairingCode = ""
    }

    private func scheduleConnectionTimeout(
        after seconds: UInt64,
        message: String
    ) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.failAndDisconnect(message)
        }
    }
}

@MainActor
enum AppOrientation {
    static func request(_ orientations: UIInterfaceOrientationMask) {
        RemoteAppDelegate.orientationLock = orientations
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            return
        }
        scene.windows
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(
            .iOS(interfaceOrientations: orientations)
        )
    }
}
