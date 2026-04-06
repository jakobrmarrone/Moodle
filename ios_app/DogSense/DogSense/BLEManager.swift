import Foundation
import CoreBluetooth
import Combine

// UUIDs must match ble_config.h
private let serviceUUID     = CBUUID(string: "8d8439b3-ecbc-59a6-8135-1b1cb5623943")
private let audioCharUUID   = CBUUID(string: "6aefa1e2-d6b9-5cb9-9fcb-4447897212f2")
private let imuCharUUID     = CBUUID(string: "66c1f950-3f93-5424-87a2-cfef024bd248")
private let commandCharUUID = CBUUID(string: "a5568574-2b7e-578f-b456-a6a54fb175d2")

/// Publishes raw BLE payloads for audio (160 µ-law bytes) and IMU (12 bytes).
/// ClassifierCoordinator subscribes to these and does all processing.
final class BLEManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var statusMessage = "Scanning..."

    // Callbacks set by ClassifierCoordinator
    var onAudioPacket: ((Data) -> Void)?
    var onIMUPacket:   ((Data) -> Void)?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func sendStartStreaming() {
        guard let char = commandChar, let p = peripheral else { return }
        p.writeValue(Data([0x01]), for: char, type: .withoutResponse)
    }

    func sendStopStreaming() {
        guard let char = commandChar, let p = peripheral else { return }
        p.writeValue(Data([0x00]), for: char, type: .withoutResponse)
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [serviceUUID])
            statusMessage = "Scanning for DogSense..."
        } else {
            statusMessage = "Bluetooth unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi: NSNumber) {
        guard peripheral.name == "DogSense" else { return }
        self.peripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral)
        statusMessage = "Connecting..."
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        statusMessage = "Connected — discovering services..."
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        commandChar = nil
        self.peripheral = nil
        statusMessage = "Disconnected — scanning..."
        centralManager.scanForPeripherals(withServices: [serviceUUID])
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
        isConnected = true
        statusMessage = "Streaming"
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
