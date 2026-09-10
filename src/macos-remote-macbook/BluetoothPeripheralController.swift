import CoreBluetooth
import Foundation
import MacOSRemote

final class BluetoothPeripheralController: NSObject {
    var onMessage: ((WireMessage, UUID) -> Void)?
    var onCentralUnavailable: ((UUID) -> Void)?
    var onStateChange: ((CBManagerState) -> Void)?

    private var manager: CBPeripheralManager!
    private var commandCharacteristic: CBMutableCharacteristic?
    private var responseCharacteristic: CBMutableCharacteristic?
    private var assemblers: [UUID: BLEFrameAssembler] = [:]
    private var subscribedCentrals: [UUID: CBCentral] = [:]
    private var pendingNotifications: [(data: Data, central: CBCentral)] = []

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func send(_ message: WireMessage, to centralID: UUID) {
        guard let central = subscribedCentrals[centralID] else {
            return
        }
        do {
            let data = try WireCodec.encode(message)
            let frames = try BLEFrameCodec.frames(
                for: data,
                maximumFrameSize: central.maximumUpdateValueLength
            )
            pendingNotifications.append(
                contentsOf: frames.map { ($0, central) }
            )
            flushNotifications()
        } catch {
            return
        }
    }

    private func publishService() {
        guard manager.state == .poweredOn else {
            return
        }
        manager.removeAllServices()

        let command = CBMutableCharacteristic(
            type: CBUUID(string: BluetoothIdentifiers.command),
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable, .writeEncryptionRequired]
        )
        let response = CBMutableCharacteristic(
            type: CBUUID(string: BluetoothIdentifiers.response),
            properties: [.notify],
            value: nil,
            permissions: [.readable, .readEncryptionRequired]
        )
        let service = CBMutableService(
            type: CBUUID(string: BluetoothIdentifiers.service),
            primary: true
        )
        service.characteristics = [command, response]
        commandCharacteristic = command
        responseCharacteristic = response
        manager.add(service)
    }

    private func flushNotifications() {
        guard let responseCharacteristic else {
            return
        }
        while let notification = pendingNotifications.first {
            let sent = manager.updateValue(
                notification.data,
                for: responseCharacteristic,
                onSubscribedCentrals: [notification.central]
            )
            guard sent else {
                return
            }
            pendingNotifications.removeFirst()
        }
    }

    private func accept(_ data: Data, from central: CBCentral) {
        var assembler = assemblers[central.identifier] ?? BLEFrameAssembler()
        do {
            if let payload = try assembler.accept(data) {
                let message = try WireCodec.decode(payload)
                onMessage?(message, central.identifier)
            }
            assemblers[central.identifier] = assembler
        } catch {
            assemblers[central.identifier] = BLEFrameAssembler()
        }
    }
}

extension BluetoothPeripheralController: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        onStateChange?(peripheral.state)
        if peripheral.state == .poweredOn {
            publishService()
        } else {
            subscribedCentrals.removeAll()
            pendingNotifications.removeAll()
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [
                CBUUID(string: BluetoothIdentifiers.service),
            ],
            CBAdvertisementDataLocalNameKey: BluetoothIdentifiers.localName,
        ])
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        subscribedCentrals[central.identifier] = central
        assemblers[central.identifier] = BLEFrameAssembler()
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        subscribedCentrals.removeValue(forKey: central.identifier)
        assemblers.removeValue(forKey: central.identifier)
        pendingNotifications.removeAll { $0.central.identifier == central.identifier }
        onCentralUnavailable?(central.identifier)
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        guard let firstRequest = requests.first else {
            return
        }
        guard requests.allSatisfy({ request in
            request.characteristic.uuid
                == CBUUID(string: BluetoothIdentifiers.command)
                && request.offset == 0
                && request.value != nil
        }) else {
            peripheral.respond(to: firstRequest, withResult: .requestNotSupported)
            return
        }
        for request in requests {
            accept(request.value!, from: request.central)
        }
        peripheral.respond(to: firstRequest, withResult: .success)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        flushNotifications()
    }
}
