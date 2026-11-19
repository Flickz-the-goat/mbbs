
import Foundation

struct LevelFoodData: Identifiable {
    let id: Int
    let population: Int
    let children: Int
    let additionalNeeds: Int

    var demand: Int {
        population + additionalNeeds
    }
}

struct FoodAllocationResult: Identifiable {
    let id: Int
    let population: Int
    let demand: Int
    let allocated: Int

    var shortage: Int {
        max(0, demand - allocated)
    }

    var coverage: Double {
        guard demand > 0 else { return 1.0 }
        return Double(allocated) / Double(demand)
    }
}

enum FoodAllocationEngine {

    static func allocate(
        levels: [LevelFoodData],
        availableFood: Int
    ) -> [FoodAllocationResult] {

        let totalDemand = levels.reduce(0) {
            $0 + $1.demand
        }

        guard totalDemand > 0 else {
            return levels.map {
                FoodAllocationResult(
                    id: $0.id,
                    population: $0.population,
                    demand: 0,
                    allocated: 0
                )
            }
        }

        let supply = max(0, min(availableFood, totalDemand))

        let exactShares = levels.map {
            Double(supply) * Double($0.demand)
                / Double(totalDemand)
        }

        var allocations = exactShares.map {
            Int($0.rounded(.down))
        }

        let remaining = supply - allocations.reduce(0, +)

        let order = exactShares.indices.sorted {
            let left = exactShares[$0] - Double(allocations[$0])
            let right = exactShares[$1] - Double(allocations[$1])

            if left == right {
                return levels[$0].id < levels[$1].id
            }

            return left > right
        }

        for index in order.prefix(remaining) {
            allocations[index] += 1
        }

        return levels.enumerated().map { index, level in
            FoodAllocationResult(
                id: level.id,
                population: level.population,
                demand: level.demand,
                allocated: allocations[index]
            )
        }
    }
}
