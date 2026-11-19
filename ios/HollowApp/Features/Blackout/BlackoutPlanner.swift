import Foundation

enum BlackoutPlanner {
    struct Household {
        let id: String
        let level: Int
        let demand: Int
        let station: PickupStation
        let availableWindows: [Int]
    }

    struct Pickup: Hashable {
        let station: PickupStation
        let window: Int
    }

    struct Row: Identifiable {
        let household: Household
        let allocated: Int
        let original: Pickup?
        let pickup: Pickup?
        var id: String { household.id }
        var unmet: Int { household.demand - allocated }
    }

    // Demo slots are relative to the start of distribution.
    static let windowLabels = ["First 30 minutes", "30–60 minutes"]
    private static let households = [
        Household(id: "A", level: 4, demand: 16, station: .north, availableWindows: [0]),
        Household(id: "B", level: 4, demand: 12, station: .north, availableWindows: [0, 1]),
        Household(id: "C", level: 4, demand: 10, station: .north, availableWindows: [1]),
        Household(id: "D", level: 3, demand: 8, station: .junction, availableWindows: [0, 1]),
        Household(id: "E", level: 3, demand: 8, station: .junction, availableWindows: [0, 1]),
        Household(id: "F", level: 2, demand: 6, station: .junction, availableWindows: [1]),
    ]

    static func capacity(of pickup: Pickup) -> Int { 2 }

    static func plan(sharedStock: Int, closed: PickupStation?) -> [Row] {
        let demand = households.reduce(0) { $0 + $1.demand }
        let stock = max(0, min(sharedStock, demand))
        var allocated = households.map { stock * $0.demand / demand }
        let remainder = stock - allocated.reduce(0, +)
        let priority = households.indices.sorted {
            let left = stock * households[$0].demand % demand
            let right = stock * households[$1].demand % demand
            return left == right ? households[$0].id < households[$1].id : left > right
        }
        for index in priority.prefix(remainder) { allocated[index] += 1 }

        let active = households.indices.filter { allocated[$0] > 0 }.sorted {
            let left = households[$0], right = households[$1]
            return left.availableWindows.count == right.availableWindows.count
                ? left.id < right.id : left.availableWindows.count < right.availableWindows.count
        }
        var used: [Pickup: Int] = [:]
        func reserve(_ index: Int, at station: PickupStation) -> Pickup? {
            for window in households[index].availableWindows {
                let pickup = Pickup(station: station, window: window)
                if used[pickup, default: 0] < capacity(of: pickup) {
                    used[pickup, default: 0] += 1
                    return pickup
                }
            }
            return nil
        }

        var original: [Int: Pickup] = [:]
        for index in active {
            original[index] = reserve(index, at: households[index].station)
        }
        var final = original
        if let closed {
            used = used.filter { $0.key.station != closed }
            let alternate: PickupStation = closed == .north ? .junction : .north
            for index in active where households[index].station == closed {
                final[index] = reserve(index, at: alternate)
            }
        }
        return households.indices.map { index in
            Row(household: households[index], allocated: allocated[index],
                original: original[index], pickup: final[index])
        }
    }
}
