import CoreBluetooth
import DLCore
import Foundation

/// Raw bytes to and from one Meshtastic radio over Bluetooth LE: scan, connect, write ToRadio, and
/// drain FromRadio whenever the radio says something is waiting. Knows nothing about what the bytes
/// mean. Pairing (the radio's PIN) is handled by iOS the first time a characteristic needs it.
///
/// A radio serves one app at a time. If another app on this iPhone (the Meshtastic app) already holds
/// it, `connect` reports `.busy` and waits for it to be free instead of taking it, unless `evenIfBusy`.
/// `disconnect` lets go cleanly: it tells the radio first, so the radio is free for another app at once.
@MainActor
protocol RadioLink: AnyObject {
    var onFound: ((RadioLinkRadio) -> Void)? { get set }
    var onState: ((RadioLinkState) -> Void)? { get set }
    var onFrame: ((Data) -> Void)? { get set }
    func scan()
    func connect(_ id: UUID, evenIfBusy: Bool)
    func disconnect()
    func write(_ data: Data)
}

extension RadioLink {
    func connect(_ id: UUID) { connect(id, evenIfBusy: false) }
}

struct RadioLinkRadio: Equatable, Identifiable {
    let id: UUID
    let name: String
    /// Signal strength when found (dBm): DLChat connects to the strongest, which is usually the nearest.
    var rssi = -127
}
enum RadioLinkState: Equatable { case bluetoothOff, unauthorized, idle, scanning, connecting, busy, ready, disconnected }

@MainActor
final class MeshtasticLink: NSObject, RadioLink {
    static let service = CBUUID(string: "6ba1b218-15a8-461f-9fa8-5dcae273eafd")
    static let toRadio = CBUUID(string: "f75c76d2-129e-4dad-a1dd-7866124401e7")
    static let fromRadio = CBUUID(string: "2c55e69e-4993-11ed-b878-0242ac120002")
    static let fromNum = CBUUID(string: "ed9da18c-a800-4f66-a670-aa7547e34453")

    var onFound: ((RadioLinkRadio) -> Void)?
    var onState: ((RadioLinkState) -> Void)?
    var onFrame: ((Data) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var found: [UUID: CBPeripheral] = [:]
    private var wantScan = false
    private var wantConnect: UUID?
    private var draining = false
    /// Waiting for another app on this iPhone to let go of the radio.
    private var busyWatch: Task<Void, Never>?
    /// Sent the radio a disconnect and waiting for it to land before dropping the link.
    private var leaving: CBPeripheral?

    override init() {
        super.init()
        // Created only when the person turns the radio on, so the Bluetooth prompt comes in context.
        // The restore identifier lets iOS relaunch DLChat in the background when the radio reconnects.
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionRestoreIdentifierKey: "dlchat-radio"])
    }

    func scan() {
        wantScan = true
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [Self.service])
        onState?(.scanning)
    }

    func connect(_ id: UUID, evenIfBusy: Bool) {
        wantConnect = id
        busyWatch?.cancel(); busyWatch = nil
        guard central.state == .poweredOn else { return }
        central.stopScan()
        if !evenIfBusy, heldElsewhere(id) {
            onState?(.busy)
            watchUntilFree(id)
            return
        }
        guard let p = found[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else { scan(); return }
        peripheral = p
        p.delegate = self
        onState?(.connecting)
        // Restored by iOS still connected: no didConnect will come, so set the link up now.
        if p.state == .connected { p.discoverServices([Self.service]) } else { central.connect(p) }
    }

    func disconnect() {
        wantScan = false
        wantConnect = nil
        busyWatch?.cancel(); busyWatch = nil
        central.stopScan()
        if let peripheral {
            if let to = characteristics[Self.toRadio], peripheral.state == .connected {
                // Tell the radio first, so it ends the session now rather than after a Bluetooth timeout.
                // The link is dropped once the write lands, or after a second if it never does.
                leaving = peripheral
                peripheral.writeValue(Meshtastic.disconnect, for: to, type: .withResponse)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.finishLeaving(peripheral)
                }
            } else {
                central.cancelPeripheralConnection(peripheral)
            }
        }
        peripheral = nil
        characteristics = [:]
        draining = false
    }

    private func finishLeaving(_ p: CBPeripheral) {
        guard leaving === p else { return }
        leaving = nil
        // Picked again in the meantime: keep the link.
        guard wantConnect != p.identifier else { return }
        central.cancelPeripheralConnection(p)
    }

    /// Connected at the system level while DLChat does not hold it: another app on this iPhone is using it.
    private func heldElsewhere(_ id: UUID) -> Bool {
        guard peripheral?.identifier != id, leaving?.identifier != id else { return false }
        return central.retrieveConnectedPeripherals(withServices: [Self.service]).contains { $0.identifier == id }
    }

    /// Checks every few seconds and connects once the other app lets go.
    private func watchUntilFree(_ id: UUID) {
        busyWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled, self.wantConnect == id else { return }
                if !self.heldElsewhere(id) { self.busyWatch = nil; self.connect(id, evenIfBusy: false); return }
            }
        }
    }

    func write(_ data: Data) {
        guard let peripheral, let to = characteristics[Self.toRadio] else { return }
        peripheral.writeValue(data, for: to, type: .withResponse)
    }

    private func drain() {
        guard !draining, let peripheral, let from = characteristics[Self.fromRadio] else { return }
        draining = true
        peripheral.readValue(for: from)
    }
}

extension MeshtasticLink: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn:
                onState?(.idle)
                if let id = wantConnect { connect(id) } else if wantScan { scan() }
            case .unauthorized: onState?(.unauthorized)
            default: onState?(.bluetoothOff)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Meshtastic radio"
            found[peripheral.identifier] = peripheral
            // 127 means "not available" in CoreBluetooth.
            let rssi = RSSI.intValue == 127 ? -127 : RSSI.intValue
            onFound?(RadioLinkRadio(id: peripheral.identifier, name: name, rssi: rssi))
            if wantConnect == peripheral.identifier { connect(peripheral.identifier) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { peripheral.discoverServices([Self.service]) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            onState?(.disconnected)
            // Keep trying the chosen radio; the pending connect completes when it is reachable again.
            if wantConnect == peripheral.identifier { central.connect(peripheral) }
        }
    }

    /// iOS relaunched DLChat for the radio (background): take back the connection it kept.
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            guard let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first else { return }
            found[restored.identifier] = restored
            peripheral = restored
            restored.delegate = self
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            if leaving === peripheral { leaving = nil }
            // A radio DLChat let go of on purpose: nothing to report.
            guard self.peripheral === peripheral || wantConnect == peripheral.identifier else { return }
            characteristics = [:]
            draining = false
            onState?(.disconnected)
            // Still wanted: a pending connect has no timeout and completes when the radio is back in range.
            if wantConnect == peripheral.identifier { central.connect(peripheral) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.service }) else { return }
            peripheral.discoverCharacteristics([Self.toRadio, Self.fromRadio, Self.fromNum], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] { characteristics[c.uuid] = c }
            guard characteristics.count == 3, let num = characteristics[Self.fromNum] else { onState?(.disconnected); return }
            peripheral.setNotifyValue(true, for: num)
            onState?(.ready)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }  // one DLChat is letting go of
            switch characteristic.uuid {
            case Self.fromNum:
                drain()
            case Self.fromRadio:
                draining = false
                // An empty read means the radio's queue is empty.
                guard error == nil, let value = characteristic.value, !value.isEmpty else { return }
                onFrame?(value)
                drain()
            default:
                break
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if leaving === peripheral { finishLeaving(peripheral); return }
            drain()  // the radio usually answers a write
        }
    }
}
