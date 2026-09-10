import Combine
import CoreBluetooth
import Foundation
import MacOSRemote

@MainActor
final class MacAppModel: ObservableObject {
    @Published private(set) var bluetoothState = "Starting Bluetooth…"
    @Published private(set) var connectedDeviceName: String?
    @Published private(set) var rememberedDevices: [RememberedMac] = []
    @Published private(set) var accessibilityGranted = false

    private struct PendingPairing {
        let centralID: UUID
        let deviceID: UUID
        let deviceName: String
        let challenge: PairingChallenge
        let code: PairingCode
    }

    private struct Connection {
        let centralID: UUID
        let deviceID: UUID
        let deviceName: String
        let sessionToken: String
        var lastSequence: UInt64
    }

    private let bluetooth = BluetoothPeripheralController()
    private let automation = InputAutomationController()
    private let credentials = MacCredentialStore()
    private let pairingOverlay = PairingOverlayController()
    private var pendingPairing: PendingPairing?
    private var connection: Connection?
    private var pairingExpiryTask: Task<Void, Never>?
    private var sequenceTask: Task<Void, Never>?

    var isConnected: Bool {
        connection != nil
    }

    init() {
        rememberedDevices = credentials.devices
        bluetooth.onMessage = { [weak self] message, centralID in
            self?.handle(message, from: centralID)
        }
        bluetooth.onCentralUnavailable = { [weak self] centralID in
            self?.centralBecameUnavailable(centralID)
        }
        bluetooth.onStateChange = { [weak self] state in
            self?.updateBluetoothState(state)
        }

        DispatchQueue.main.async { [weak self] in
            self?.refreshAccessibility(requestIfNeeded: true)
        }
    }

    func refreshAccessibility(requestIfNeeded: Bool = false) {
        accessibilityGranted = automation.isAccessibilityGranted
        if requestIfNeeded, !accessibilityGranted {
            automation.requestAccessibility()
        }
    }

    func requestAccessibility() {
        automation.requestAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshAccessibility()
        }
    }

    func forget(_ device: RememberedMac) {
        credentials.forget(deviceID: device.id)
        rememberedDevices = credentials.devices
    }

    func disconnect() {
        guard let connection else {
            return
        }
        bluetooth.send(
            .disconnect(sessionToken: connection.sessionToken),
            to: connection.centralID
        )
        clearConnection()
    }

    private func handle(_ message: WireMessage, from centralID: UUID) {
        switch message {
        case let .hello(hello):
            handle(hello, from: centralID)
        case let .pairingResponse(response):
            handle(response, from: centralID)
        case let .command(command):
            handle(command, from: centralID)
        case let .disconnect(token):
            if connection?.centralID == centralID,
               connection?.sessionToken == token {
                clearConnection()
            }
        case let .ping(identifier):
            if connection?.centralID == centralID {
                bluetooth.send(.pong(identifier), to: centralID)
            }
        case .pairingChallenge, .connectionAccepted, .connectionRejected, .pong:
            break
        }
    }

    private func handle(_ hello: ClientHello, from centralID: UUID) {
        guard hello.protocolVersion == macOSRemoteProtocolVersion else {
            bluetooth.send(
                .connectionRejected(reason: "This app version is not compatible."),
                to: centralID
            )
            return
        }
        guard connection == nil || connection?.centralID == centralID else {
            bluetooth.send(
                .connectionRejected(reason: "This Mac is already connected."),
                to: centralID
            )
            return
        }

        if credentials.matches(hello.credential, for: hello.deviceID) {
            acceptConnection(
                centralID: centralID,
                deviceID: hello.deviceID,
                deviceName: hello.displayName,
                remembered: true,
                newCredential: nil
            )
            return
        }

        if let pendingPairing,
           pendingPairing.centralID == centralID,
           pendingPairing.deviceID == hello.deviceID {
            bluetooth.send(
                .pairingChallenge(pendingPairing.challenge),
                to: centralID
            )
            return
        }
        guard pendingPairing == nil else {
            bluetooth.send(
                .connectionRejected(reason: "Another pairing request is in progress."),
                to: centralID
            )
            return
        }

        let code = PairingCode.generate()
        let challenge = PairingChallenge(
            requestID: UUID(),
            expiresAt: Date().addingTimeInterval(120)
        )
        pendingPairing = PendingPairing(
            centralID: centralID,
            deviceID: hello.deviceID,
            deviceName: hello.displayName,
            challenge: challenge,
            code: code
        )
        pairingOverlay.present(code: code.value) { [weak self] in
            self?.cancelPairing(reason: "Pairing was canceled on the Mac.")
        }
        bluetooth.send(.pairingChallenge(challenge), to: centralID)
        schedulePairingExpiry(for: challenge.requestID)
    }

    private func handle(_ response: PairingResponse, from centralID: UUID) {
        guard let pendingPairing,
              pendingPairing.centralID == centralID,
              pendingPairing.challenge.requestID == response.requestID,
              pendingPairing.challenge.expiresAt > Date()
        else {
            bluetooth.send(
                .connectionRejected(reason: "The pairing request expired."),
                to: centralID
            )
            return
        }
        guard response.code == pendingPairing.code.value else {
            cancelPairing(reason: "The pairing code did not match.")
            return
        }

        let remember = pairingOverlay.rememberDevice
        let credential = remember ? SecureToken.generate() : nil
        if let credential {
            credentials.remember(
                deviceID: pendingPairing.deviceID,
                name: pendingPairing.deviceName,
                credential: credential
            )
            rememberedDevices = credentials.devices
        }
        acceptConnection(
            centralID: centralID,
            deviceID: pendingPairing.deviceID,
            deviceName: pendingPairing.deviceName,
            remembered: remember,
            newCredential: credential
        )
    }

    private func handle(_ command: SessionCommand, from centralID: UUID) {
        guard var connection,
              connection.centralID == centralID,
              connection.sessionToken == command.sessionToken,
              command.sequence > connection.lastSequence
        else {
            return
        }
        connection.lastSequence = command.sequence
        self.connection = connection

        if case .keySequence = command.command {
            sequenceTask?.cancel()
            sequenceTask = Task { [weak self] in
                await self?.automation.execute(command.command)
            }
        } else {
            Task { [weak self] in
                await self?.automation.execute(command.command)
            }
        }
    }

    private func acceptConnection(
        centralID: UUID,
        deviceID: UUID,
        deviceName: String,
        remembered: Bool,
        newCredential: String?
    ) {
        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil
        pendingPairing = nil
        pairingOverlay.dismiss()

        let token = SecureToken.generate()
        connection = Connection(
            centralID: centralID,
            deviceID: deviceID,
            deviceName: deviceName,
            sessionToken: token,
            lastSequence: 0
        )
        connectedDeviceName = deviceName
        bluetooth.send(
            .connectionAccepted(ConnectionAccepted(
                sessionToken: token,
                serverName: Host.current().localizedName ?? "Mac",
                remembered: remembered,
                credential: newCredential
            )),
            to: centralID
        )
    }

    private func cancelPairing(reason: String) {
        guard let pendingPairing else {
            return
        }
        bluetooth.send(
            .connectionRejected(reason: reason),
            to: pendingPairing.centralID
        )
        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil
        self.pendingPairing = nil
        pairingOverlay.dismiss()
    }

    private func schedulePairingExpiry(for requestID: UUID) {
        pairingExpiryTask?.cancel()
        pairingExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled,
                  self?.pendingPairing?.challenge.requestID == requestID
            else {
                return
            }
            self?.cancelPairing(reason: "The pairing request expired.")
        }
    }

    private func centralBecameUnavailable(_ centralID: UUID) {
        if pendingPairing?.centralID == centralID {
            pairingExpiryTask?.cancel()
            pairingExpiryTask = nil
            pendingPairing = nil
            pairingOverlay.dismiss()
        }
        if connection?.centralID == centralID {
            clearConnection()
        }
    }

    private func clearConnection() {
        sequenceTask?.cancel()
        sequenceTask = nil
        automation.cancelInteractions()
        connection = nil
        connectedDeviceName = nil
    }

    private func updateBluetoothState(_ state: CBManagerState) {
        bluetoothState = switch state {
        case .poweredOn: "Available for pairing"
        case .poweredOff: "Bluetooth is off"
        case .unauthorized: "Bluetooth permission is required"
        case .unsupported: "Bluetooth is not supported"
        case .resetting: "Bluetooth is resetting…"
        case .unknown: "Starting Bluetooth…"
        @unknown default: "Bluetooth is unavailable"
        }
        if state != .poweredOn {
            clearConnection()
        }
    }
}
