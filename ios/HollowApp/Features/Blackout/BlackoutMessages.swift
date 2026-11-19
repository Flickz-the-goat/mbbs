import Foundation

enum FamilyCheckIn: String, CaseIterable, Hashable {
    case safe = "I’m safe"
    case supplies = "Need supplies"
    case pickup = "Can’t reach pickup"

    var message: String { "Hollow check-in: " + rawValue }

    static func read(_ text: String?) -> FamilyCheckIn? {
        allCases.first { $0.message == text }
    }
}

enum PickupStation: String, CaseIterable, Codable, Hashable {
    case north = "North station"
    case junction = "Junction station"

    var level: Int { self == .north ? 4 : 3 }
}

struct BlackoutReport: Codable, Identifiable {
    enum Kind: String, CaseIterable, Codable {
        case powerOut = "Power out"
        case stationClosed = "Pickup station closed"
    }

    let id: UUID
    let kind: Kind
    let level: Int
    let station: PickupStation?
    let date: Date

    var title: String {
        if let station { return "\(kind.rawValue) · \(station.rawValue) · Level \(level)" }
        return "\(kind.rawValue) · Level \(level)"
    }

    var message: String {
        "Hollow report: \(kind.rawValue) | \(level) | \(station?.rawValue ?? "-") | \(id.uuidString)"
    }

    static func read(_ packet: MeshPacket) -> BlackoutReport? {
        let prefix = "Hollow report: "
        guard let text = packet.payload, text.hasPrefix(prefix) else { return nil }
        let fields = String(text.dropFirst(prefix.count)).components(separatedBy: " | ")
        guard fields.count == 4, let kind = Kind(rawValue: fields[0]),
              let level = Int(fields[1]), (2...4).contains(level),
              let id = UUID(uuidString: fields[3]) else { return nil }
        let station = PickupStation(rawValue: fields[2])
        guard kind == .stationClosed ? station?.level == level : fields[2] == "-" else { return nil }
        return BlackoutReport(id: id, kind: kind, level: level, station: station, date: packet.createdAt)
    }
}
