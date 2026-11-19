import Foundation

let us = Locale(identifier: "en_US")
let french = Locale(identifier: "fr_FR")

precondition(DemoMessage(text: "  Check lights  ")?.text == "Check lights")
precondition(DemoMessage(text: "\n ") == nil)
precondition(DemoMessage(text: String(repeating: "a", count: 240)) != nil)
precondition(DemoMessage(text: String(repeating: "a", count: 241)) == nil)
precondition(Level.two.forecast?.probability == 0.18)
precondition(Level.three.forecast?.probability == 0.68)
precondition(Level.four.forecast == nil)
precondition(FoodDraft(name: "Rice", quantity: "1.5", unit: .kilograms, locale: us)?.quantity == 1.5)
precondition(FoodDraft(name: "Rice", quantity: "1,5", unit: .kilograms, locale: french)?.quantity == 1.5)
precondition(FoodDraft(name: "Tin", quantity: "2", unit: .items, locale: us)?.quantity == 2)
precondition(FoodDraft(name: "Tin", quantity: "1.5", unit: .items, locale: us) == nil)
precondition(FoodDraft(name: "Rice", quantity: "0", unit: .kilograms, locale: us) == nil)
precondition(FoodDraft(name: "Rice", quantity: "-2", unit: .kilograms, locale: us) == nil)
precondition(FoodDraft(name: "Rice", quantity: "2abc", unit: .kilograms, locale: us) == nil)
precondition(FoodDraft(name: " ", quantity: "2", unit: .kilograms, locale: us) == nil)
let firstResident = UUID(uuidString: "00000000-0000-4000-8000-000000000000")!
let secondResident = UUID(uuidString: "00000000-0000-4000-8000-000001020304")!
let firstAssignment = DemoFoodAssignment(residentID: firstResident)
let secondAssignment = DemoFoodAssignment(residentID: secondResident)
precondition(firstAssignment == DemoFoodAssignment(residentID: firstResident))
precondition(firstAssignment.pickupWindow != secondAssignment.pickupWindow)
precondition(firstAssignment.riceKilograms != secondAssignment.riceKilograms)
precondition(firstAssignment.beanCans != secondAssignment.beanCans)
precondition((3...6).contains(secondAssignment.waterLiters))
print("Hollow demo model checks passed.")

let powerResponse = """
{
  "level_id": 3,
  "probability": 0.428,
  "window_start": "2025-03-01T18:00:00Z",
  "window_end": "2025-03-02T18:00:00+00:00",
  "generated_at": "2026-11-19T22:20:00.123456Z",
  "reading_source": "synthetic_replay",
  "model": {"version": "outage-v1-test", "trained_on": "synthetic"}
}
"""
let decodedPower = try PowerForecast.decode(Data(powerResponse.utf8), for: 3)
precondition(decodedPower.probability == 0.428)
precondition(decodedPower.readingSource == .syntheticReplay)
precondition(decodedPower.windowEnd.timeIntervalSince(decodedPower.windowStart) == 86_400)
precondition(decodedPower.generatedAt > decodedPower.windowEnd)
precondition(decodedPower.model.version == "outage-v1-test")
precondition((try? PowerForecast.decode(Data(powerResponse.utf8), for: 4)) == nil)
let invalidPower = powerResponse.replacingOccurrences(of: "0.428", with: "1.428")
precondition((try? PowerForecast.decode(Data(invalidPower.utf8), for: 3)) == nil)
print("Hollow power forecast decoding checks passed.")

// Each simulated device stores a serialized copy, and links can be stopped and recreated.
final class SimulatedDevice: PeerTransport {
    var onReceive: ((Data) -> Bool)?
    var onStatus: ((String) -> Void)?
    var onSent: ((UUID) -> Void)?
    private var active = false
    private var packets: [MeshPacket] = []
    private(set) var router: MeshRouter
    private let disk: Disk

    private final class Disk {
        var data: Data?
        func save(_ state: MeshState) throws { data = try JSONEncoder().encode(state) }
    }

    init() {
        let disk = Disk()
        self.disk = disk
        router = MeshRouter(state: MeshState(address: UUID()), save: disk.save)
        onReceive = { [weak self] data in
            guard let self else { return false }
            try! self.router.receive(data)
            return true
        }
    }

    var address: UUID { router.state.address }
    func start() { active = true }
    func stop() { active = false }
    func update(_ packets: [MeshPacket]) { self.packets = packets }
    func send(_ text: String, to destination: UUID) throws { try router.send(text, to: destination) }

    func reload() throws {
        let state = try JSONDecoder().decode(MeshState.self, from: disk.data!)
        router = MeshRouter(state: state, save: disk.save)
    }

    func transfer(to peer: SimulatedDevice) throws {
        guard active, peer.active else { return }
        for packet in packets {
            if peer.onReceive?(try JSONEncoder().encode(packet)) == true { onSent?(packet.id) }
        }
    }
}

let sender = SimulatedDevice()
let relay = SimulatedDevice()
let destination = SimulatedDevice()
try sender.send(String(repeating: "🟢", count: 240), to: destination.address)
let message = sender.router.outgoing()[0]
try sender.reload()
precondition(sender.address == message.origin && sender.router.outgoing() == [message])
sender.start()
relay.start()
sender.update(sender.router.outgoing())
try sender.transfer(to: relay)
try sender.transfer(to: relay)
precondition(relay.router.state.packets.count == 1)
precondition(!sender.router.isDelivered(message))
precondition(relay.router.outgoing().first?.hopCount == 1)
relay.update(relay.router.outgoing())
try relay.transfer(to: sender)
precondition(sender.router.state.packets.count == 1)
try relay.transfer(to: destination)
precondition(destination.router.state.packets.isEmpty)

relay.stop()
try relay.reload()
destination.start()
try relay.transfer(to: destination)
precondition(destination.router.state.packets.isEmpty)
relay.start()
relay.update(relay.router.outgoing())
try relay.transfer(to: destination)
try relay.transfer(to: destination)
precondition(destination.router.state.packets.count == 2)
precondition(destination.router.state.packets.first?.payload == message.payload)
precondition(!sender.router.isDelivered(message))
destination.update(destination.router.outgoing())
try destination.transfer(to: relay)
relay.update(relay.router.outgoing())
try relay.transfer(to: sender)
precondition(sender.router.isDelivered(message))
try sender.reload()
precondition(sender.router.isDelivered(message))
precondition(sender.router.outgoing().isEmpty)

var edge = MeshRouter(state: MeshState(address: UUID()), save: { _ in })
let wire = try JSONEncoder().encode(message)
try edge.receive(wire, now: message.createdAt.addingTimeInterval(MeshPacket.lifetime))
try edge.receive(Data("invalid".utf8))
try edge.receive(Data(repeating: 0, count: MeshPacket.maxBytes + 1))
var invalid = message
invalid.version = 99
try edge.receive(JSONEncoder().encode(invalid))
invalid = message
invalid.ttl = 0
try edge.receive(JSONEncoder().encode(invalid))
precondition(edge.state.packets.isEmpty)
var lastHop = message
lastHop.ttl = 1
lastHop.hopCount = MeshPacket.hopLimit - 1
try edge.receive(JSONEncoder().encode(lastHop))
precondition(edge.outgoing().isEmpty)
try edge.receive(wire)
precondition(edge.outgoing().first?.hopCount == 1)
precondition(edge.outgoing(at: message.createdAt.addingTimeInterval(MeshPacket.lifetime)).isEmpty)

enum SimulatedDiskError: Error { case writeFailed }
var unavailable = MeshRouter(state: MeshState(address: UUID()), save: { _ in throw SimulatedDiskError.writeFailed })
do {
    try unavailable.receive(wire)
    preconditionFailure("Expected disk write to fail")
} catch SimulatedDiskError.writeFailed {
    precondition(unavailable.state.packets.isEmpty)
}
print("Hollow simulated mesh checks passed.")

let chain = (0...MeshPacket.hopLimit).map { _ in SimulatedDevice() }
try chain[0].send("Across the Hollows", to: chain[MeshPacket.hopLimit].address)
let longMessage = chain[0].router.outgoing()[0]

// Only adjacent links are activated, one at a time, as if devices moved into range.
for (source, target) in zip(chain, chain.dropFirst()) {
    source.start()
    target.start()
    source.update(source.router.outgoing())
    try source.transfer(to: target)
    source.stop()
    target.stop()
}
let finalDevice = chain[MeshPacket.hopLimit]
precondition(finalDevice.router.state.packets.first?.hopCount == MeshPacket.hopLimit)
precondition(!chain[0].router.isDelivered(longMessage))
for (source, target) in zip(chain.reversed(), chain.reversed().dropFirst()) {
    source.start()
    target.start()
    source.update(source.router.outgoing())
    try source.transfer(to: target)
    source.stop()
    target.stop()
}
precondition(chain[0].router.isDelivered(longMessage))

var legacy = MeshRouter(state: MeshState(address: UUID()), save: { _ in })
let legacyPacket = MeshPacket(version: 1, id: UUID(), origin: UUID(), destination: legacy.state.address,
                              createdAt: .now, ttl: 4, payload: "Legacy", acknowledging: nil)
try legacy.receive(JSONEncoder().encode(legacyPacket))
precondition(legacy.outgoing().first?.version == 1)
precondition(legacy.outgoing().first?.ttl == 4)
print("Hollow twelve-link relay and legacy protocol checks passed.")

let reporter = SimulatedDevice()
let courier = SimulatedDevice()
let relative = SimulatedDevice()
let stationReport = BlackoutReport(id: UUID(), kind: .stationClosed, level: 4, station: .north, date: .now)
try reporter.send(FamilyCheckIn.safe.message, to: relative.address)
try reporter.send(stationReport.message, to: relative.address)
let checkInPacket = reporter.router.outgoing().first!
precondition(!reporter.router.isDelivered(checkInPacket))
reporter.start()
courier.start()
reporter.update(reporter.router.outgoing())
try reporter.transfer(to: courier)
precondition(!reporter.router.isDelivered(checkInPacket))
relative.start()
courier.update(courier.router.outgoing())
try courier.transfer(to: relative)
precondition(relative.router.state.packets.filter { FamilyCheckIn.read($0.payload) == .safe }.count == 1)
precondition(relative.router.state.packets.compactMap(BlackoutReport.read).map(\.id) == [stationReport.id])
relative.update(relative.router.outgoing())
try relative.transfer(to: courier)
courier.update(courier.router.outgoing())
try courier.transfer(to: reporter)
precondition(reporter.router.isDelivered(checkInPacket))
precondition(FamilyCheckIn.read("I’m safe") == nil)
let badReport = MeshPacket(id: UUID(), origin: reporter.address, destination: relative.address, createdAt: .now,
                           payload: stationReport.message.replacingOccurrences(of: " | 4 | ", with: " | 2 | "),
                           acknowledging: nil)
precondition(BlackoutReport.read(badReport) == nil)

for stock in 0...80 {
    let normal = BlackoutPlanner.plan(sharedStock: stock, closed: nil)
    let demand = normal.reduce(0) { $0 + $1.household.demand }
    for station in PickupStation.allCases {
        let closed = BlackoutPlanner.plan(sharedStock: stock, closed: station)
        precondition(closed.reduce(0) { $0 + $1.allocated } == min(stock, demand))
        var pickups: [BlackoutPlanner.Pickup: Int] = [:]
        for (before, after) in zip(normal, closed) {
            precondition(before.allocated == after.allocated && after.unmet >= 0)
            if before.pickup?.station != station { precondition(before.pickup == after.pickup) }
            if let pickup = after.pickup {
                precondition(pickup.station != station && after.allocated > 0)
                precondition(after.household.availableWindows.contains(pickup.window))
                pickups[pickup, default: 0] += 1
            }
        }
        precondition(pickups.allSatisfy { pick, count in count <= BlackoutPlanner.capacity(of: pick) })
    }
}
let disrupted = BlackoutPlanner.plan(sharedStock: 36, closed: .north)
precondition(disrupted.contains { $0.pickup != nil && $0.pickup != $0.original })
precondition(disrupted.contains { $0.allocated > 0 && $0.pickup == nil })
print("Hollow blackout check-in, incident, and ration planning checks passed.")
