import CoreBluetooth
import Foundation

final class BluetoothTransport: NSObject, PeerTransport {
    private static let serviceID = CBUUID(string: "742D0001-CCB4-4D28-AE1E-0AA2AAEBE301")
    private static let writeID = CBUUID(string: "742D0002-CCB4-4D28-AE1E-0AA2AAEBE301")
    var onReceive: ((Data) -> Bool)?
    var onStatus: ((String) -> Void)?
    var onSent: ((UUID) -> Void)?

    private final class Link {
        let peer: CBPeripheral
        var characteristic: CBCharacteristic?
        var sentTTL: [UUID: Int] = [:]
        var transfer: (id: UUID, ttl: Int, data: Data, offset: Int)?
        var pendingBytes = 0

        init(_ peer: CBPeripheral) { self.peer = peer }
    }

    private struct Assembly {
        var data: Data
        let updatedAt: Date
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var active = false
    private var service: CBMutableService?
    private var links: [UUID: Link] = [:]
    private var assemblies: [UUID: Assembly] = [:]
    private var packets: [MeshPacket] = []

    func start() {
        active = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            peripheral = CBPeripheralManager(delegate: self, queue: .main)
        }
        refresh()
    }

    func stop() {
        active = false
        central?.stopScan()
        peripheral?.stopAdvertising()
        service = nil
        if peripheral?.state == .poweredOn { peripheral?.removeAllServices() }
        for link in links.values where central?.state == .poweredOn {
            central?.cancelPeripheralConnection(link.peer)
        }
        // Keep cancelling links until their disconnect callback arrives.
        assemblies.removeAll()
    }

    func update(_ packets: [MeshPacket]) {
        self.packets = packets
        guard active else { return }
        for link in links.values { pump(link) }
    }

    private func refresh() {
        guard active, let central, let peripheral else { return }
        switch (central.state, peripheral.state) {
        case (.unauthorized, _), (_, .unauthorized): onStatus?("Bluetooth permission denied")
        case (.unsupported, _), (_, .unsupported): onStatus?("Bluetooth unavailable on this device")
        case (.poweredOff, _), (_, .poweredOff): onStatus?("Bluetooth is off")
        case (.poweredOn, .poweredOn):
            let ready = links.values.filter { $0.characteristic != nil }.count
            onStatus?(ready == 0 ? "Searching for nearby Hollow devices" : "Bluetooth links ready: \(ready)")
        default: onStatus?("Starting Bluetooth")
        }

        if central.state == .poweredOn, !central.isScanning {
            central.scanForPeripherals(withServices: [Self.serviceID])
        }
        if peripheral.state == .poweredOn, service == nil {
            let characteristic = CBMutableCharacteristic(type: Self.writeID, properties: .write,
                                                         value: nil, permissions: .writeable)
            let service = CBMutableService(type: Self.serviceID, primary: true)
            service.characteristics = [characteristic]
            self.service = service
            peripheral.add(service)
        }
    }

    private func pump(_ link: Link) {
        guard link.pendingBytes == 0, let characteristic = link.characteristic,
              link.peer.state == .connected else { return }
        if link.transfer == nil {
            guard let packet = packets.first(where: { (link.sentTTL[$0.id] ?? 0) < $0.ttl && $0.isLive(at: .now) }),
                  let data = try? JSONEncoder().encode(packet), data.count <= MeshPacket.maxBytes else { return }
            link.transfer = (packet.id, packet.ttl, data, 0)
        }

        guard let transfer = link.transfer else { return }
        let capacity = min(link.peer.maximumWriteValueLength(for: .withResponse),
                           link.peer.maximumWriteValueLength(for: .withoutResponse)) - 1
        guard capacity > 0 else { return }
        let end = min(transfer.offset + capacity, transfer.data.count)
        // Bit 0 starts an assembly. Bit 1 completes it.
        let flags: UInt8 = (transfer.offset == 0 ? 1 : 0) | (end == transfer.data.count ? 2 : 0)
        var frame = Data([flags])
        frame.append(transfer.data[transfer.offset..<end])
        link.pendingBytes = end - transfer.offset
        link.peer.writeValue(frame, for: characteristic, type: .withResponse)
    }
}

extension BluetoothTransport: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn { links.removeAll() }
        refresh()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peer: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard active, links[peer.identifier] == nil else { return }
        links[peer.identifier] = Link(peer)
        peer.delegate = self
        central.connect(peer)
    }

    func centralManager(_ central: CBCentralManager, didConnect peer: CBPeripheral) {
        guard active else {
            central.cancelPeripheralConnection(peer)
            return
        }
        peer.discoverServices([Self.serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peer: CBPeripheral, error: Error?) {
        reconnectScanning(after: peer)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peer: CBPeripheral, error: Error?) {
        reconnectScanning(after: peer)
    }

    private func reconnectScanning(after peer: CBPeripheral) {
        links.removeValue(forKey: peer.identifier)
        if active, central?.state == .poweredOn { central?.stopScan() }
        refresh()
    }

    func peripheral(_ peer: CBPeripheral, didDiscoverServices error: Error?) {
        guard active, error == nil, let service = peer.services?.first(where: { $0.uuid == Self.serviceID }) else {
            central?.cancelPeripheralConnection(peer)
            return
        }
        peer.discoverCharacteristics([Self.writeID], for: service)
    }

    func peripheral(_ peer: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard active, error == nil, let link = links[peer.identifier],
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.writeID && $0.properties.contains(.write) }) else {
            central?.cancelPeripheralConnection(peer)
            return
        }
        link.characteristic = characteristic
        refresh()
        pump(link)
    }

    func peripheral(_ peer: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard invalidatedServices.contains(where: { $0.uuid == Self.serviceID }) else { return }
        links[peer.identifier]?.characteristic = nil
        central?.cancelPeripheralConnection(peer)
    }

    func peripheral(_ peer: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active, let link = links[peer.identifier], var transfer = link.transfer else { return }
        let bytes = link.pendingBytes
        link.pendingBytes = 0
        guard error == nil else {
            link.transfer = nil
            return
        }
        transfer.offset += bytes
        if transfer.offset == transfer.data.count {
            link.sentTTL[transfer.id] = transfer.ttl
            link.transfer = nil
            onSent?(transfer.id)
        } else {
            link.transfer = transfer
        }
        pump(link)
    }
}

extension BluetoothTransport: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state != .poweredOn {
            service = nil
            assemblies.removeAll()
        }
        refresh()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard active, service === self.service else { return }
        guard error == nil else {
            self.service = nil
            onStatus?("Could not publish the Bluetooth service")
            return
        }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceID]])
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if active, error != nil { onStatus?("Could not advertise the Bluetooth service") }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first else { return }
        guard requests.count == 1, active, request.characteristic.uuid == Self.writeID,
              request.offset == 0, let frame = request.value, frame.count > 1,
              frame.count <= MeshPacket.maxBytes + 1, let flags = frame.first, flags < 4 else {
            peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            return
        }

        let now = Date.now
        assemblies = assemblies.filter { now.timeIntervalSince($0.value.updatedAt) < 30 }
        let sender = request.central.identifier
        let previous = assemblies.removeValue(forKey: sender)?.data
        guard var data = flags & 1 != 0 ? Data() : previous,
              data.count + frame.count - 1 <= MeshPacket.maxBytes else {
            peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            return
        }
        data.append(contentsOf: frame.dropFirst())
        if flags & 2 != 0 {
            peripheral.respond(to: request, withResult: onReceive?(data) == true ? .success : .unlikelyError)
        } else if assemblies.count < 32 {
            assemblies[sender] = Assembly(data: data, updatedAt: now)
            peripheral.respond(to: request, withResult: .success)
        } else {
            peripheral.respond(to: request, withResult: .insufficientResources)
        }
    }
}
