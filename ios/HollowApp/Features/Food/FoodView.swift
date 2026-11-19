import SwiftUI

struct FoodView: View {
    let assignment: DemoFoodAssignment?
    let isGuest: Bool

    var body: some View {
        Screen(title: "Food supplies", subtitle: "View your demo rations and pickup time.") {
            if let assignment {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ration pickup", systemImage: "calendar")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    LabeledContent("Pickup window", value: assignment.pickupWindow)
                    if isGuest {
                        Text("Guest sample. Sign in to view your resident assignment.")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                }
                .hollowPanel()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Your rations", systemImage: "shippingbox")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    LabeledContent("Rice", value: "\(assignment.riceKilograms) kg")
                    LabeledContent("Canned beans", value: "\(assignment.beanCans) cans")
                    LabeledContent("Drinking water", value: "\(assignment.waterLiters) L")
                }
                .hollowPanel()
            } else {
                Text("Sign in to view your demo assignment.")
                    .foregroundStyle(Palette.muted)
                    .hollowPanel()
            }
        }
    }
}
