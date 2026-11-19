import SwiftUI

struct BlackoutView: View {
    @ObservedObject var messaging: MessagingModel
    let contacts: [ContactProfile]

    @AppStorage("hollow.blackout.reports.v1") private var reportData = Data()
    @AppStorage("hollow.blackout.station.v1") private var closedStationName = ""
    @AppStorage("hollow.blackout.updateTime.v1") private var updateTime = 0.0
    @AppStorage("hollow.blackout.sharedStock.v1") private var sharedStock = 36
    @State private var level = Level.four
    @State private var station = PickupStation.north
    @State private var notice: String?
    @State private var forecastState: ForecastState?

    private struct BoardReport: Identifiable {
        let report: BlackoutReport
        let reporter: String?
        var id: UUID { report.id }
    }

    private enum ForecastState {
        case available(Level, PowerForecast)
        case missing(Level, String)
    }

    private var closedStation: PickupStation? { PickupStation(rawValue: closedStationName) }

    private var recipients: [ContactProfile] {
        contacts.filter { $0.deviceId != messaging.address }
    }

    private var localReports: [BlackoutReport] {
        (try? JSONDecoder().decode([BlackoutReport].self, from: reportData)) ?? []
    }

    private var reports: [BoardReport] {
        let cutoff = messaging.now.addingTimeInterval(-MeshPacket.lifetime)
        var entries = localReports.filter { $0.date > cutoff }.map {
            BoardReport(report: $0, reporter: nil)
        }
        var seen = Set(entries.map(\.id))
        for packet in messaging.messages where packet.destination == messaging.address {
            guard let contact = contacts.first(where: { $0.deviceId == packet.origin }),
                  let report = BlackoutReport.read(packet), report.date > cutoff,
                  seen.insert(report.id).inserted else { continue }
            entries.append(BoardReport(report: report, reporter: contact.name))
        }
        return entries.sorted { $0.report.date > $1.report.date }
    }

    var body: some View {
        Screen(title: "Blackout Mode", subtitle: "Check on family, share incidents, and plan ration pickups.") {
            incidentBoard
            familyPanel
            BlackoutRationsView(sharedStock: $sharedStock, closedStation: closedStation) { station in
                closedStationName = station?.rawValue ?? ""
                updateTime = Date.now.timeIntervalSince1970
            }
        }
        .task(id: level) { await loadForecast(for: level) }
    }

    private var incidentBoard: some View {
        let entries = reports
        let reportedOutage = entries.contains { $0.report.kind == .powerOut && $0.report.level == level.rawValue }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Incident board").font(.headline)
            Picker("Underground level", selection: $level) {
                ForEach(Level.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if reportedOutage {
                Label("Blackout reported on \(level.title)", systemImage: "bolt.slash.fill")
                    .foregroundStyle(.orange)
            }
            forecastLine

            if updateTime > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coordinator update · Local simulation").font(.caption.weight(.semibold))
                    if let closedStation {
                        Text("\(closedStation.rawValue) closed. Pickup plan updated.")
                    } else {
                        Text("Both pickup stations are open. Pickup plan updated.")
                    }
                    Text(Date(timeIntervalSince1970: updateTime), format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }

            ForEach(entries.prefix(8)) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.reporter.map { "Resident report · \($0)" } ?? "Your report")
                        .font(.caption.weight(.semibold))
                    Text(entry.report.title)
                    Text(entry.report.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }
            if entries.isEmpty { Text("No recent resident reports.").foregroundStyle(Palette.muted) }
            if entries.contains(where: { $0.reporter != nil }) {
                Text("Reports received over Bluetooth are unverified.")
                    .font(.footnote).foregroundStyle(Palette.muted)
            }

            Divider()
            Text(recipients.isEmpty
                 ? "Reports are saved on this device."
                 : "Reporting also queues a Bluetooth message to each saved contact.")
                .font(.footnote).foregroundStyle(Palette.muted)
            Button("Report power out for \(level.title)", systemImage: "bolt.slash") {
                publish(.powerOut)
            }
            Picker("Closed station", selection: $station) {
                ForEach(PickupStation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Button("Report station closed", systemImage: "exclamationmark.bubble") {
                publish(.stationClosed)
            }
            if let notice { Text(notice).font(.footnote).foregroundStyle(Palette.muted) }
        }
        .hollowPanel()
    }

    @ViewBuilder
    private var forecastLine: some View {
        switch forecastState {
        case .available(let selected, let forecast) where selected == level:
            VStack(alignment: .leading, spacing: 4) {
                Text(forecast.readingSource == .syntheticReplay ? "Model estimate · Synthetic replay" : "Model estimate")
                    .font(.caption.weight(.semibold))
                Text("\(forecast.probability.formatted(.percent.precision(.fractionLength(1)))) chance of an outage starting")
                Text(forecast.windowStart...forecast.windowEnd)
                    .font(.caption).foregroundStyle(Palette.muted)
            }
        case .missing(let selected, let message) where selected == level:
            Text(message).font(.footnote).foregroundStyle(Palette.muted)
        default:
            ProgressView("Loading model estimate…")
        }
    }

    private var familyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Family check-ins").font(.headline)
            Text(messaging.status).font(.caption).foregroundStyle(Palette.muted)
            if recipients.isEmpty {
                Text("Add family in Account before relying on offline check-ins.")
                    .foregroundStyle(Palette.muted)
            }
            ForEach(recipients) { contact in
                VStack(alignment: .leading, spacing: 8) {
                    Text(contact.name).font(.headline)
                    if let received = latestCheckIn(origin: contact.deviceId, destination: messaging.address),
                       let checkIn = FamilyCheckIn.read(received.payload) {
                        LabeledContent("Last received", value: checkIn.rawValue)
                        Text(received.createdAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(Palette.muted)
                    } else {
                        Text("No check-in received.").font(.caption).foregroundStyle(Palette.muted)
                    }
                    if let sent = latestCheckIn(origin: messaging.address, destination: contact.deviceId),
                       let checkIn = FamilyCheckIn.read(sent.payload) {
                        LabeledContent(checkIn.rawValue, value: messaging.deliveryStatus(for: sent))
                    }
                    ForEach(FamilyCheckIn.allCases, id: \.self) { checkIn in
                        Button(checkIn.rawValue) {
                            _ = messaging.send(checkIn.message, to: contact.deviceId)
                        }
                        .buttonStyle(.bordered)
                        .disabled(messaging.address == nil)
                    }
                }
            }
            if let error = messaging.storageError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .hollowPanel()
    }

    private func latestCheckIn(origin: UUID?, destination: UUID?) -> MeshPacket? {
        messaging.messages.filter {
            $0.origin == origin && $0.destination == destination && FamilyCheckIn.read($0.payload) != nil
        }.max { $0.createdAt < $1.createdAt }
    }

    private func publish(_ kind: BlackoutReport.Kind) {
        let now = Date.now
        let selectedStation = kind == .stationClosed ? station : nil
        let report = BlackoutReport(id: UUID(), kind: kind, level: selectedStation?.level ?? level.rawValue,
                                    station: selectedStation, date: now)
        let retained = localReports.filter { now.timeIntervalSince($0.date) < MeshPacket.lifetime }
        guard let data = try? JSONEncoder().encode(Array((retained + [report]).suffix(40))) else {
            notice = "Couldn’t save the report."
            return
        }
        reportData = data
        var queued = 0
        for contact in recipients where messaging.send(report.message, to: contact.deviceId) { queued += 1 }
        if recipients.isEmpty {
            notice = "Report saved on this device."
        } else {
            notice = "Report saved. Queued to \(queued) of \(recipients.count) saved contacts."
        }
    }

    @MainActor
    private func loadForecast(for selected: Level) async {
        guard let url = BackendConfiguration.baseURL else {
            forecastState = .missing(selected, "Model estimate unavailable. Set HollowAPIURL to connect.")
            return
        }
        let state: ForecastState
        do {
            let forecast = try await PowerAPIClient(baseURL: url).forecast(for: selected.rawValue)
            state = .available(selected, forecast)
        } catch {
            state = .missing(selected, "Model estimate unavailable. Resident reports are still available offline.")
        }
        if !Task.isCancelled { forecastState = state }
    }
}
