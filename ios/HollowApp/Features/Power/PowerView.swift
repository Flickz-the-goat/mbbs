import SwiftUI

struct PowerView: View {
    @State private var level = Level.three

    var body: some View {
        Screen(title: "Power outlook", subtitle: "Outage risk by underground level.") {
            Picker("Underground level", selection: $level) {
                ForEach(Level.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 14) {
                Label("NEXT 24 HOURS · SYNTHETIC DATA", systemImage: "bolt.fill")
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.signal)
                if let forecast = level.forecast {
                    Text(forecast.probability, format: .percent)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .accessibilityLabel("Sample outage probability")
                        .accessibilityValue(forecast.probability.formatted(.percent))
                    ProgressView(value: forecast.probability)
                        .tint(Palette.signal)
                        .accessibilityHidden(true)
                    Text(forecast.risk + " RISK")
                        .font(.subheadline.monospaced().weight(.semibold))
                    Text(forecast.note)
                        .foregroundStyle(Palette.muted)
                } else {
                    Text("Forecast unavailable").font(.title2.bold())
                    Text("This level has insufficient sample history.")
                        .foregroundStyle(Palette.muted)
                }
            }
            .hollowPanel()
        }
    }
}
