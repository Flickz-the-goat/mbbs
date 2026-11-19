
import SwiftUI

struct FoodDistributionView: View {

    @State private var availableFood = 800.0

    private let levels: [LevelFoodData] = [
        .init(id: 1, population: 150,
              children: 25, additionalNeeds: 20),
        .init(id: 2, population: 200,
              children: 40, additionalNeeds: 35),
        .init(id: 3, population: 250,
              children: 65, additionalNeeds: 55),
        .init(id: 4, population: 300,
              children: 90, additionalNeeds: 80),
        .init(id: 5, population: 350,
              children: 120, additionalNeeds: 110)
    ]

    private var results: [FoodAllocationResult] {
        FoodAllocationEngine.allocate(
            levels: levels,
            availableFood: Int(availableFood)
        )
    }

    private var totalDemand: Int {
        results.reduce(0) { $0 + $1.demand }
    }

    private var allocated: Int {
        results.reduce(0) { $0 + $1.allocated }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                Text("FOOD INTELLIGENCE")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)

                Text("Resource Distribution")
                    .font(.largeTitle.bold())

                Text("The Hollow • Emergency Food Allocation")
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    metric("Residents", "1,250")
                    metric("Food Units", "\(Int(availableFood))")
                    metric("Shortage", "\(totalDemand - allocated)")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Available Food")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(availableFood)) units")
                            .foregroundStyle(.cyan)
                    }

                    Slider(
                        value: $availableFood,
                        in: 0...1600,
                        step: 50
                    )
                    .tint(.cyan)
                }
                .padding()
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text("Distribution by Level")
                    .font(.title3.bold())

                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Level \(result.id)")
                                .font(.headline)

                            Spacer()

                            Text(
                                "\(result.allocated) / \(result.demand)"
                            )
                            .foregroundStyle(.secondary)
                        }

                        ProgressView(value: result.coverage)
                            .tint(
                                result.coverage < 0.5
                                    ? .orange : .cyan
                            )

                        Text(
                            "Unmet demand: \(result.shortage) units"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if totalDemand > allocated {
                    Label(
                        "Food shortage detected. Additional supplies required.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .padding()
                } else {
                    Label(
                        "All modeled demand is covered.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                    .padding()
                }

                Text("Simulation • Fictional population and supply data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Color(red: 0.04, green: 0.08, blue: 0.14))
        .preferredColorScheme(.dark)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
