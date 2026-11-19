import SwiftUI

enum Palette {
    static let ground = Color(red: 0.06, green: 0.085, blue: 0.08)
    static let panel = Color(red: 0.10, green: 0.14, blue: 0.125)
    static let signal = Color(red: 0.73, green: 0.93, blue: 0.59)
    static let muted = Color(red: 0.65, green: 0.72, blue: 0.67)
    static let line = Color.white.opacity(0.12)
}

struct Screen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("HOLLOW", systemImage: "circle.hexagongrid.fill")
                        .foregroundStyle(Palette.signal)
                        .accessibilityLabel("Hollow")
                    Spacer()
                    Text("OFFLINE DEMO")
                        .foregroundStyle(Palette.muted)
                }
                .font(.caption.monospaced().weight(.semibold))
                .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .foregroundStyle(Palette.muted)
                }
                content
            }
            .frame(maxWidth: 520)
            .padding(22)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.ground.ignoresSafeArea())
    }
}

extension View {
    func hollowPanel() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line)
                    .allowsHitTesting(false)
            }
    }
}
