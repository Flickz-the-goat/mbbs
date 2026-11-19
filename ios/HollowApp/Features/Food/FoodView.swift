import SwiftUI

struct FoodView: View {
    @Binding var drafts: [FoodDraft]
    @State private var name = ""
    @State private var quantity = ""
    @State private var unit = FoodUnit.kilograms
    private enum Field: Hashable { case name, quantity }
    @FocusState private var editing: Field?

    private var draft: FoodDraft? { FoodDraft(name: name, quantity: quantity, unit: unit) }

    var body: some View {
        Screen(title: "Food supplies", subtitle: "Keep a private inventory draft for this demo session.") {
            VStack(alignment: .leading, spacing: 14) {
                
                NavigationLink {
                    FoodDistributionView()
                } label: {
                    Label(
                        "Open Food Distribution",
                        systemImage: "chart.bar.fill"
                    )
                }
                .buttonStyle(.borderedProminent)

                NavigationLink {
                    FoodServerView(client: FoodAPIClient.configured)
                } label: {
                    Label("Food server demo", systemImage: "network")
                }

                Text("Add inventory").font(.headline).accessibilityAddTraits(.isHeader)
                TextField("Food name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($editing, equals: .name)
                TextField("Quantity", text: $quantity)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($editing, equals: .quantity)
                Picker("Unit", selection: $unit) {
                    ForEach(FoodUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                if !quantity.isEmpty, FoodDraft(name: "Food", quantity: quantity, unit: unit) == nil {
                    Text(unit == .items ? "Enter a positive whole number." : "Enter a positive quantity.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                Button("Save private draft", systemImage: "plus") {
                    guard let draft else { return }
                    drafts.append(draft)
                    name = ""
                    quantity = ""
                    editing = nil
                }
                .buttonStyle(.bordered)
                .disabled(draft == nil)
            }
            .hollowPanel()

            ForEach(drafts.reversed()) { draft in
                VStack(alignment: .leading, spacing: 6) {
                    Text(draft.name).font(.headline)
                    Text("\(draft.quantity.formatted()) \(draft.unit.rawValue) · Private draft")
                        .foregroundStyle(Palette.muted)
                }
                .hollowPanel()
                .accessibilityElement(children: .combine)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Ration pickup", systemImage: "calendar")
                    .font(.headline)
                Text("Pickup assignments are unavailable in this demo.")
                    .foregroundStyle(Palette.muted)
            }
            .hollowPanel()
        }
    }
}
