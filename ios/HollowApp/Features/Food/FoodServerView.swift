import SwiftUI

struct FoodServerView: View {
    let client: FoodAPIClient?

    @State private var household = FoodHousehold()
    @State private var demandText = "12 24 36"
    @State private var stockText = "36"
    @State private var operation: Operation?
    @State private var prediction: FoodDemandPrediction?
    @State private var allocation: SharedFoodAllocation?
    @State private var errorMessage: String?

    private enum Operation: Equatable {
        case predict(FoodHousehold)
        case allocate(SharedFoodAllocationRequest)
    }

    private var validHousehold: Bool {
        (1...8).contains(household.levelId) &&
        household.householdSize > 0 &&
        (0...household.householdSize).contains(household.childrenCount) &&
        (0...(household.householdSize - household.childrenCount)).contains(household.seniorCount) &&
        household.cannedFoodCount >= 0 &&
        (1...30).contains(household.planningDays) &&
        household.dailyPortionsPerPerson.isFinite &&
        household.dailyPortionsPerPerson > 0 &&
        [household.riceKg, household.beansKg, household.waterLiters, household.reservePortionsPerPerson]
            .allSatisfy { $0.isFinite && $0 >= 0 }
    }

    private var allocationRequest: SharedFoodAllocationRequest? {
        let entries = demandText.split(whereSeparator: { $0.isWhitespace })
        let demands = entries.compactMap { Double($0) }
        guard !demands.isEmpty, entries.count == demands.count,
              demands.allSatisfy({ $0.isFinite && $0 >= 0 }),
              let stock = Double(stockText.trimmingCharacters(in: .whitespacesAndNewlines)),
              stock.isFinite, stock >= 0 else { return nil }
        return SharedFoodAllocationRequest(demands: demands, availableSharedUnits: stock)
    }

    var body: some View {
        Form {
            Section {
                Text("Use fictional household and shared stock data for this demo. Requests send the values on this screen to the configured server.")
                if client == nil {
                    Label("Food server URL is missing or invalid.", systemImage: "exclamationmark.circle")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                }
                if operation != nil {
                    ProgressView("Contacting food server…")
                }
            }

            Section("Household demand") {
                Stepper("Level \(household.levelId)", value: $household.levelId, in: 1...8)
                LabeledContent("Household size") {
                    TextField("Household size", value: $household.householdSize, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                LabeledContent("Children") {
                    TextField("Children", value: $household.childrenCount, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                LabeledContent("Seniors") {
                    TextField("Seniors", value: $household.seniorCount, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                LabeledContent("Rice (kg)") {
                    TextField("Rice (kg)", value: $household.riceKg, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                LabeledContent("Beans (kg)") {
                    TextField("Beans (kg)", value: $household.beansKg, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                LabeledContent("Cans") {
                    TextField("Cans", value: $household.cannedFoodCount, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                LabeledContent("Water (L)") {
                    TextField("Water (L)", value: $household.waterLiters, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                LabeledContent("Daily portions per person") {
                    TextField("Daily portions per person", value: $household.dailyPortionsPerPerson, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                Stepper("Planning days: \(household.planningDays)", value: $household.planningDays, in: 1...30)
                LabeledContent("Reserve portions per person") {
                    TextField("Reserve portions per person", value: $household.reservePortionsPerPerson, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                if !validHousehold {
                    Text("Enter valid household counts and nonnegative supplies. Daily portions must be greater than zero.")
                        .font(.footnote)
                }
                Button("Predict demand") {
                    prediction = nil
                    start(.predict(household))
                }
                .disabled(client == nil || !validHousehold)
            }
            .disabled(operation != nil)

            if let prediction {
                Section("Demand prediction") {
                    LabeledContent("Additional demand", value: prediction.predictedAdditionalRationUnits.formatted())
                    Text(prediction.unit)
                }
            }

            Section {
                LabeledContent("Household demands") {
                    TextField("Household demands", text: $demandText)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Available shared units") {
                    TextField("Available shared units", text: $stockText)
                        .multilineTextAlignment(.trailing)
                }
                Button("Calculate allocation") {
                    guard let request = allocationRequest else { return }
                    allocation = nil
                    start(.allocate(request))
                }
                .disabled(client == nil || allocationRequest == nil)
            } header: {
                Text("Shared stock allocation")
            } footer: {
                Text("Enter nonnegative demands separated by spaces, using a dot for decimals.")
            }
            .disabled(operation != nil)

            if let allocation {
                Section("Allocation result") {
                    ForEach(allocation.allocatedUnits.indices, id: \.self) { index in
                        LabeledContent("Household \(index + 1)", value: allocation.allocatedUnits[index].formatted())
                    }
                    LabeledContent("Remaining shared units", value: allocation.remainingUnits.formatted())
                }
            }
        }
        .navigationTitle("Food server demo")
        .task(id: operation) {
            guard let operation, let client else { return }
            defer {
                if !Task.isCancelled { self.operation = nil }
            }
            do {
                switch operation {
                case let .predict(household):
                    let result = try await client.predict(household)
                    try Task.checkCancellation()
                    prediction = result
                case let .allocate(request):
                    let result = try await client.allocate(request)
                    try Task.checkCancellation()
                    allocation = result
                }
            } catch {
                guard !Task.isCancelled else { return }
                if error is URLError {
                    errorMessage = "Couldn’t reach the food server. Check the connection and try again."
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .onDisappear { operation = nil }
    }

    private func start(_ operation: Operation) {
        errorMessage = nil
        self.operation = operation
    }
}
