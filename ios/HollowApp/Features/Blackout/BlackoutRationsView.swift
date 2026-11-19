import SwiftUI

struct BlackoutRationsView: View {
    @Binding var sharedStock: Int
    let closedStation: PickupStation?
    let updateStation: (PickupStation?) -> Void

    @State private var selectedStation = PickupStation.north

    var body: some View {
        let rows = BlackoutPlanner.plan(sharedStock: sharedStock, closed: closedStation)
        let demand = rows.reduce(0) { $0 + $1.household.demand }
        let assigned = rows.reduce(0) { $0 + $1.allocated }
        let waiting = rows.filter { $0.allocated > 0 && $0.pickup == nil }
        let redirected = rows.filter { $0.pickup != nil && $0.pickup != $0.original }

        VStack(alignment: .leading, spacing: 12) {
            Text("Ration allocation and pickup").font(.headline)
            Text("Coordinator simulation · Fictional households and shared stock")
                .font(.footnote).foregroundStyle(Palette.muted)
            Stepper("Shared stock: \(sharedStock) units", value: $sharedStock, in: 0...80, step: 1)
            LabeledContent("Total demand", value: "\(demand) units")
            LabeledContent("Allocated", value: "\(assigned) units")
            LabeledContent("Unmet demand", value: "\(demand - assigned) units")
            LabeledContent("Unallocated stock", value: "\(sharedStock - assigned) units")
            Text("Households receive a proportional share. Whole-unit remainders go to the largest fractional shares.")
                .font(.footnote).foregroundStyle(Palette.muted)

            Divider()
            Text("Pickup slots").font(.headline)
            Text("Each station serves up to two households per 30-minute window.")
                .font(.footnote).foregroundStyle(Palette.muted)
            if let closedStation {
                Label("\(closedStation.rawValue) closed", systemImage: "xmark.circle")
                    .foregroundStyle(.orange)
                LabeledContent("Redirected households", value: redirected.count.formatted())
                Button("Reopen \(closedStation.rawValue)") { updateStation(nil) }
                    .buttonStyle(.bordered)
            } else {
                Picker("Station to close", selection: $selectedStation) {
                    ForEach(PickupStation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button("Close station and redirect", systemImage: "arrow.triangle.branch") {
                    updateStation(selectedStation)
                }
                .buttonStyle(.bordered)
            }
            if !waiting.isEmpty {
                Label("\(waiting.count) awaiting pickup capacity · \(waiting.reduce(0) { $0 + $1.allocated }) units held",
                      systemImage: "clock")
                    .foregroundStyle(.orange)
            }

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent("Household \(row.id) · Level \(row.household.level)",
                                   value: "\(row.allocated) / \(row.household.demand)")
                        .font(.subheadline.weight(.semibold))
                    Text("Unmet demand: \(row.unmet) units")
                        .foregroundStyle(Palette.muted)
                    if let pickup = row.pickup {
                        let status = pickup == row.original ? "Pickup" : "Redirected"
                        Text("\(status) · \(pickup.station.rawValue) · \(BlackoutPlanner.windowLabels[pickup.window])")
                    } else if row.allocated > 0 {
                        Text("Awaiting pickup capacity").foregroundStyle(.orange)
                    } else {
                        Text("No stock allocated").foregroundStyle(Palette.muted)
                    }
                }
                .font(.footnote)
                .padding(.vertical, 4)
            }
        }
        .hollowPanel()
    }
}
