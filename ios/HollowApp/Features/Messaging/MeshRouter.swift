import Foundation

struct MeshPacket: Codable, Equatable {
    static let hopLimit = 12
    static let lifetime: TimeInterval = 86_400
    static let maxBytes = 4096

    var version = 2
    let id: UUID
    let origin: UUID
    let destination: UUID
    let createdAt: Date
    var ttl = hopLimit
    var hopCount = 0
    let payload: String?
    let acknowledging: UUID?

    func isLive(at now: Date) -> Bool {
        createdAt <= now.addingTimeInterval(300) && now.timeIntervalSince(createdAt) < Self.lifetime
    }

    static func validText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            text.count <= 240 && text.utf8.count <= 960
    }

    func isValid(at now: Date) -> Bool {
        let limit: Int
        switch version {
        case 1: limit = 4
        case 2: limit = Self.hopLimit
        default: return false
        }
        guard origin != destination, isLive(at: now),
              (1...limit).contains(ttl), hopCount == limit - ttl else { return false }
        if let payload { return acknowledging == nil && Self.validText(payload) }
        return acknowledging != nil
    }
}

struct MeshState: Codable {
    let address: UUID
    var packets: [MeshPacket] = []
}

struct MeshRouter {
    private(set) var state: MeshState
    private let save: (MeshState) throws -> Void

    init(state: MeshState, save: @escaping (MeshState) throws -> Void) {
        self.state = state
        self.save = save
    }

    mutating func send(_ text: String, to destination: UUID, now: Date = .now) throws {
        let packet = MeshPacket(id: UUID(), origin: state.address, destination: destination,
                                createdAt: now, payload: text, acknowledging: nil)
        guard packet.isValid(at: now) else { return }
        try commit([packet])
    }

    mutating func receive(_ data: Data, now: Date = .now) throws {
        guard data.count <= MeshPacket.maxBytes,
              var packet = try? JSONDecoder().decode(MeshPacket.self, from: data),
              packet.isValid(at: now), packet.origin != state.address else { return }

        packet.ttl -= 1
        packet.hopCount += 1
        if let index = state.packets.firstIndex(where: { $0.id == packet.id }) {
            let previous = state.packets[index]
            var comparison = packet
            comparison.ttl = previous.ttl
            comparison.hopCount = previous.hopCount
            guard packet.destination != state.address, packet.ttl > previous.ttl,
                  comparison == previous else { return }
            var updated = state
            updated.packets[index] = packet
            try commit(updated)
        } else if packet.destination == state.address, packet.payload != nil {
            let receipt = MeshPacket(version: packet.version, id: UUID(), origin: state.address,
                                     destination: packet.origin, createdAt: now,
                                     ttl: packet.version == 1 ? 4 : MeshPacket.hopLimit,
                                     payload: nil, acknowledging: packet.id)
            try commit([packet, receipt])
        } else {
            try commit([packet])
        }
    }

    func outgoing(at now: Date = .now) -> [MeshPacket] {
        state.packets.filter {
            $0.destination != state.address && $0.ttl > 0 && $0.isLive(at: now) && !isDelivered($0)
        }
    }

    func isDelivered(_ packet: MeshPacket) -> Bool {
        packet.payload != nil && state.packets.contains {
            $0.acknowledging == packet.id && $0.origin == packet.destination &&
                $0.destination == packet.origin
        }
    }

    private mutating func commit(_ packets: [MeshPacket]) throws {
        var updated = state
        updated.packets.append(contentsOf: packets)
        try commit(updated)
    }

    private mutating func commit(_ updated: MeshState) throws {
        try save(updated)
        state = updated
    }
}

protocol PeerTransport: AnyObject {
    var onReceive: ((Data) -> Bool)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    var onSent: ((UUID) -> Void)? { get set }
    func start()
    func stop()
    func update(_ packets: [MeshPacket])
}
