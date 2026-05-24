import Foundation
import CoreBluetooth
import Combine

// UUIDs must match ble_config.h
private let serviceUUID     = CBUUID(string: "8d8439b3-ecbc-59a6-8135-1b1cb5623943")
private let audioCharUUID   = CBUUID(string: "6aefa1e2-d6b9-5cb9-9fcb-4447897212f2")
private let imuCharUUID     = CBUUID(string: "66c1f950-3f93-5424-87a2-cfef024bd248")
private let commandCharUUID = CBUUID(string: "a5568574-2b7e-578f-b456-a6a54fb175d2")

/// Publishes raw BLE payloads for audio (200 µ-law bytes) and IMU (12 bytes).
/// ClassifierCoordinator subscribes to these and does all processing.
final class BLEManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var statusMessage = "Ready — tap Connect"

    // Callbacks set by ClassifierCoordinator
    var onAudioPacket: ((Data) -> Void)?
    var onIMUPacket:   ((Data) -> Void)?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?

    // Dedicated queue keeps BLE callbacks off the main thread so UI rendering
    // doesn't compete with the 80 audio notifications/sec coming from the device.
    private let bleQueue = DispatchQueue(label: "com.moodle.ble", qos: .userInitiated)

    convenience override init() {
        self.init(forPreview: false)
    }

    init(forPreview: Bool) {
        super.init()
        if !forPreview {
            centralManager = CBCentralManager(delegate: self, queue: bleQueue)
        }
    }

    func sendStartStreaming() {
        guard let char = commandChar, let p = peripheral else { return }
        p.writeValue(Data([0x01]), for: char, type: .withoutResponse)
    }

    func sendStopStreaming() {
        guard let char = commandChar, let p = peripheral else { return }
        p.writeValue(Data([0x00]), for: char, type: .withoutResponse)
    }

    /// Start scanning and connect to the first DogSense peripheral found.
    func connect() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth unavailable"
            return
        }
        statusMessage = "Scanning for DogSense..."
        centralManager.scanForPeripherals(withServices: nil)
    }

    /// Disconnect from the current peripheral and stop scanning.
    func disconnect() {
        centralManager.stopScan()
        if let p = peripheral {
            sendStopStreaming()
            centralManager.cancelPeripheralConnection(p)
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("[BLE] Central state: \(central.state.rawValue)")
        let message: String
        switch central.state {
        case .poweredOn:     message = "Ready — tap Connect"
        case .unauthorized:  message = "Bluetooth permission denied — check Settings"
        case .poweredOff:    message = "Bluetooth is turned off"
        default:             message = "Bluetooth unavailable"
        }
        DispatchQueue.main.async { self.statusMessage = message }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let deviceName = peripheral.name
        print("[BLE] Discovered: advertised=\(advertisedName ?? "nil") device=\(deviceName ?? "nil") | ID: \(peripheral.identifier)")
        guard advertisedName == "DogSense" || deviceName == "DogSense"
           || advertisedName == "Arduino"  || deviceName == "Arduino" else { return }
        self.peripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral)
        DispatchQueue.main.async { self.statusMessage = "Connecting..." }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        DispatchQueue.main.async { self.statusMessage = "Connected — discovering services..." }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        commandChar = nil
        self.peripheral = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.statusMessage = "Disconnected"
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([audioCharUUID, imuCharUUID, commandCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            switch char.uuid {
            case audioCharUUID:
                peripheral.setNotifyValue(true, for: char)
            case imuCharUUID:
                peripheral.setNotifyValue(true, for: char)
            case commandCharUUID:
                commandChar = char
            default:
                break
            }
        }
        DispatchQueue.main.async {
            self.isConnected = true
            self.statusMessage = "Streaming"
        }
        sendStartStreaming()
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case audioCharUUID:
            onAudioPacket?(data)
        case imuCharUUID:
            onIMUPacket?(data)
        default:
            break
        }
    }
}
