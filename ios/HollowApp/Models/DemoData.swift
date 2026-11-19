import Foundation

struct DemoMessage: Identifiable {
    let id = UUID()
    let text: String
    let incoming: Bool

    init?(text: String, incoming: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 240 else { return nil }
        self.text = trimmed
        self.incoming = incoming
    }
}

enum Level: Int, CaseIterable, Identifiable {
    case two = 2
    case three
    case four

    var id: Int { rawValue }
    var title: String { "Level \(rawValue.formatted(.number.precision(.integerLength(2))))" }

    var forecast: Forecast? {
        switch self {
        case .two: return Forecast(probability: 0.18, risk: "LOW", note: "Sample readings show steady electrical load.")
        case .three: return Forecast(probability: 0.68, risk: "ELEVATED", note: "Sample readings show higher load during the evening.")
        case .four: return nil
        }
    }
}

struct Forecast {
    let probability: Double
    let risk: String
    let note: String
}

enum FoodUnit: String, CaseIterable, Identifiable {
    case kilograms = "kg"
    case liters = "L"
    case items = "items"

    var id: String { rawValue }
}

struct FoodDraft: Identifiable {
    let id = UUID()
    let name: String
    let quantity: Decimal
    let unit: FoodUnit

    init?(name: String, quantity: String, unit: FoodUnit, locale: Locale = .current) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuantity = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmedQuantity.components(separatedBy: locale.decimalSeparator ?? ".")
        guard !trimmedName.isEmpty, !trimmedQuantity.isEmpty,
              parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let amount = try? Decimal(trimmedQuantity, format: .number.locale(locale)),
              amount > 0,
              unit != .items || amount == amount.roundedToInteger else { return nil }
        self.name = trimmedName
        self.quantity = amount
        self.unit = unit
    }
}

private extension Decimal {
    var roundedToInteger: Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .down)
        return result
    }
}

struct DemoFoodAssignment: Equatable {
    private static let pickupWindows = [
        "9:00–9:30 AM", "9:30–10:00 AM", "10:00–10:30 AM", "10:30–11:00 AM",
        "1:00–1:30 PM", "1:30–2:00 PM", "2:00–2:30 PM", "2:30–3:00 PM",
    ]

    let pickupWindow: String
    let riceKilograms: Int
    let beanCans: Int
    let waterLiters: Int

    init(residentID: UUID) {
        // Use separate UUID bytes to keep the demo values stable across launches.
        let bytes = residentID.uuid
        pickupWindow = Self.pickupWindows[Int(bytes.12) % Self.pickupWindows.count]
        riceKilograms = 1 + Int(bytes.13) % 4
        beanCans = 2 + Int(bytes.14) % 4
        waterLiters = 3 + Int(bytes.15) % 4
    }
}
