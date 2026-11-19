import SwiftUI

struct PowerView: View {
    @State private var level = Level.three
    @State private var refresh = 0
    @State private var completedRequest: Request?
    @State private var result: Result<PowerForecast, Error>?

    private let client = BackendConfiguration.baseURL.map { PowerAPIClient(baseURL: $0) }

    private struct Request: Equatable {
        let level: Level
        let refresh: Int
    }

    var body: some View {
        let request = Request(level: level, refresh: refresh)
        Screen(title: "Power outlook", subtitle: "Outage risk by underground level.") {
            Picker("Underground level", selection: $level) {
                ForEach(Level.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)

            if client == nil {
                unavailable("Set HollowAPIURL to load server forecasts.", retry: false)
            } else if completedRequest == request, let result {
                switch result {
                case .success(let forecast):
                    forecastPanel(forecast)
                case .failure(let error):
                    unavailable(error.localizedDescription, retry: true)
                }
            } else {
                ProgressView("Loading \(level.title) forecast…")
                    .hollowPanel()
            }
        }
        .task(id: request) {
            await load(request)
        }
    }

    @MainActor
    private func load(_ request: Request) async {
        guard let client else { return }
        let outcome: Result<PowerForecast, Error>
        do {
            outcome = .success(try await client.forecast(for: request.level.rawValue))
        } catch is URLError {
            outcome = .failure(ConnectionError.unreachable)
        } catch {
            outcome = .failure(error)
        }
        guard !Task.isCancelled else { return }
        result = outcome
        completedRequest = request
    }

    private func forecastPanel(_ forecast: PowerForecast) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(forecast.readingSource == .syntheticReplay ? "Synthetic replay" : "Submitted readings",
                  systemImage: "bolt.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.signal)
            probability(forecast.probability)
            Text("Chance of an outage starting during this 24-hour window.")
                .foregroundStyle(Palette.muted)

            VStack(alignment: .leading, spacing: 6) {
                dateRow("Window starts", forecast.windowStart)
                dateRow("Window ends", forecast.windowEnd)
                dateRow("Generated", forecast.generatedAt)
            }
            .font(.subheadline)

            Text("Model \(forecast.model.version) · Training data: \(forecast.model.trainedOn)")
                .font(.caption)
                .foregroundStyle(Palette.muted)
            Button("Refresh forecast", systemImage: "arrow.clockwise") { refresh += 1 }
                .buttonStyle(.bordered)
        }
        .hollowPanel()
    }

    private func unavailable(_ message: String, retry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Forecast unavailable", systemImage: "exclamationmark.circle")
                .font(.headline)
            Text(message)
                .foregroundStyle(Palette.muted)
            if retry {
                Button("Try again", systemImage: "arrow.clockwise") { refresh += 1 }
                    .buttonStyle(.bordered)
            }
            if let sample = level.forecast {
                DisclosureGroup("Offline sample") {
                    VStack(alignment: .leading, spacing: 8) {
                        probability(sample.probability)
                        Text(sample.note)
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .hollowPanel()
    }

    private func probability(_ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let label = value.formatted(.percent.precision(.fractionLength(1)))
            Text(label)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .accessibilityLabel("Outage probability")
                .accessibilityValue(label)
            ProgressView(value: value)
                .tint(Palette.signal)
                .accessibilityHidden(true)
        }
    }

    private func dateRow(_ label: String, _ date: Date) -> some View {
        LabeledContent {
            Text(date, format: .dateTime.year().month(.abbreviated).day().hour().minute().timeZone())
        } label: {
            Text(label).foregroundStyle(Palette.muted)
        }
    }

    private enum ConnectionError: LocalizedError {
        case unreachable

        var errorDescription: String? {
            "Couldn’t reach the power server. Check the connection and try again."
        }
    }
}
