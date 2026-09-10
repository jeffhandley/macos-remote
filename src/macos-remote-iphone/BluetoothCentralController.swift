import Combine
import CoreBluetooth
import Foundation
import MacOSRemote

struct NearbyMac: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

enum BluetoothConnectionState: Equatable {
    case unavailable(String)
    case scanning
    case connecting
    case discovering
    case ready
}

final class BluetoothCentralController: NSObject, ObservableObject {
    @Published private(set) var nearbyMacs: [NearbyMac] = []
    @Published private(set) var state: BluetoothConnectionState = .unavailable("Starting Bluetooth…")

    var onReady: ((UUID) -> Void)?
    var onMessage: ((WireMessage) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    private var manager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var discoveredRSSI: [UUID: Int] = [:]
    private var lastSeen: [UUID: Date] = [:]
    private var pruneTimer: Timer?
    private var connectedPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var assembler = BLEFrameAssembler()
    private var pendingWrites: [Data] = []
    private var readyNotified = false
    private var disconnectRequested = false

    override init() {
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard manager.state == .poweredOn else {
            return
        }
        state = .scanning
        if !manager.isScanning {
            manager.scanForPeripherals(
                withServices: [CBUUID(string: BluetoothIdentifiers.service)],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
        if pruneTimer == nil {
            pruneTimer = Timer.scheduledTimer(
                withTimeInterval: 2,
                repeats: true
            ) { [weak self] _ in
                self?.pruneStalePeripherals()
            }
        }
    }

    func connect(to peripheralID: UUID) {
        guard let peripheral = peripherals[peripheralID] else {
            return
        }
        manager.stopScan()
        resetConnectionState()
        connectedPeripheral = peripheral
        state = .connecting
        manager.connect(peripheral)
    }

    func disconnect() {
        disconnectRequested = true
        if let connectedPeripheral {
            manager.cancelPeripheralConnection(connectedPeripheral)
        } else {
            finishDisconnect(error: nil)
        }
    }

    func send(_ message: WireMessage) {
        guard let peripheral = connectedPeripheral,
              commandCharacteristic != nil,
              state == .ready
        else {
            return
        }
        do {
            let encoded = try WireCodec.encode(message)
            let maximumLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
            let frames = try BLEFrameCodec.frames(
                for: encoded,
                maximumFrameSize: maximumLength
            )
            pendingWrites.append(contentsOf: frames)
            flushWrites()
        } catch {
            finishDisconnect(error: error)
        }
    }

    func isNearby(_ peripheralID: UUID) -> Bool {
        peripherals[peripheralID] != nil
    }

    private func flushWrites() {
        guard let peripheral = connectedPeripheral,
              let commandCharacteristic
        else {
            return
        }
        while !pendingWrites.isEmpty, peripheral.canSendWriteWithoutResponse {
            let frame = pendingWrites.removeFirst()
            peripheral.writeValue(
                frame,
                for: commandCharacteristic,
                type: .withoutResponse
            )
        }
    }

    private func finishDiscoveryIfReady() {
        guard let peripheral = connectedPeripheral,
              commandCharacteristic != nil,
              responseCharacteristic != nil
        else {
            return
        }
        if responseCharacteristic?.isNotifying == true, !readyNotified {
            readyNotified = true
            state = .ready
            onReady?(peripheral.identifier)
        }
    }

    private func resetConnectionState() {
        commandCharacteristic = nil
        responseCharacteristic = nil
        assembler = BLEFrameAssembler()
        pendingWrites.removeAll()
        readyNotified = false
    }

    private func finishDisconnect(error: Error?) {
        resetConnectionState()
        connectedPeripheral = nil
        let requested = disconnectRequested
        disconnectRequested = false
        onDisconnect?(requested ? nil : error)
        startScanning()
    }

    private func refreshNearbyMacs() {
        let refreshed = peripherals.values
            .map { peripheral in
                NearbyMac(
                    id: peripheral.identifier,
                    name: peripheral.name ?? BluetoothIdentifiers.localName,
                    rssi: discoveredRSSI[peripheral.identifier] ?? -100
                )
            }
            .sorted {
                if $0.rssi == $1.rssi {
                    return $0.name < $1.name
                }
                return $0.rssi > $1.rssi
            }
        if refreshed != nearbyMacs {
            nearbyMacs = refreshed
        }
    }

    private func pruneStalePeripherals(now: Date = Date()) {
        let connectedID = connectedPeripheral?.identifier
        let staleIDs = lastSeen.compactMap { identifier, seenAt in
            identifier != connectedID && now.timeIntervalSince(seenAt) > 6
                ? identifier
                : nil
        }
        guard !staleIDs.isEmpty else {
            return
        }
        for identifier in staleIDs {
            peripherals.removeValue(forKey: identifier)
            discoveredRSSI.removeValue(forKey: identifier)
            lastSeen.removeValue(forKey: identifier)
        }
        refreshNearbyMacs()
    }
}

extension BluetoothCentralController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startScanning()
        case .poweredOff:
            state = .unavailable("Bluetooth is off")
        case .unauthorized:
            state = .unavailable("Bluetooth permission is required")
        case .unsupported:
            state = .unavailable("Bluetooth is not supported")
        case .resetting:
            state = .unavailable("Bluetooth is resetting…")
        case .unknown:
            state = .unavailable("Starting Bluetooth…")
        @unknown default:
            state = .unavailable("Bluetooth is unavailable")
        }
        if central.state != .poweredOn {
            central.stopScan()
            peripherals.removeAll()
            discoveredRSSI.removeAll()
            lastSeen.removeAll()
            refreshNearbyMacs()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        peripherals[peripheral.identifier] = peripheral
        discoveredRSSI[peripheral.identifier] = RSSI.intValue
        lastSeen[peripheral.identifier] = Date()
        refreshNearbyMacs()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        state = .discovering
        peripheral.discoverServices([CBUUID(string: BluetoothIdentifiers.service)])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        finishDisconnect(error: error)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        finishDisconnect(error: error)
    }
}

extension BluetoothCentralController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: {
                  $0.uuid == CBUUID(string: BluetoothIdentifiers.service)
              })
        else {
            disconnect()
            return
        }
        peripheral.discoverCharacteristics(
            [
                CBUUID(string: BluetoothIdentifiers.command),
                CBUUID(string: BluetoothIdentifiers.response),
            ],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            disconnect()
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case CBUUID(string: BluetoothIdentifiers.command):
                commandCharacteristic = characteristic
            case CBUUID(string: BluetoothIdentifiers.response):
                responseCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        finishDiscoveryIfReady()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, characteristic.isNotifying else {
            disconnect()
            return
        }
        finishDiscoveryIfReady()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == CBUUID(string: BluetoothIdentifiers.response),
              let value = characteristic.value
        else {
            return
        }
        do {
            if let payload = try assembler.accept(value) {
                onMessage?(try WireCodec.decode(payload))
            }
        } catch {
            assembler = BLEFrameAssembler()
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        flushWrites()
    }
}
