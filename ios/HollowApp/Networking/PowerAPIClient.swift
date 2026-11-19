import Foundation

struct PowerForecast: Decodable, Sendable {
    enum ReadingSource: String, Decodable, Sendable {
        case syntheticReplay = "synthetic_replay"
        case submittedReadings = "submitted_readings"
    }

    struct Model: Decodable, Sendable {
        let version: String
        let trainedOn: String
    }

    let levelId: Int
    let probability: Double
    let windowStart: Date
    let windowEnd: Date
    let generatedAt: Date
    let readingSource: ReadingSource
    let model: Model

    static func decode(_ data: Data, for levelID: Int) throws -> PowerForecast {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            let text = try value.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle().parse(text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid forecast timestamp.")
        }

        guard let forecast = try? decoder.decode(PowerForecast.self, from: data),
              forecast.levelId == levelID,
              (0...1).contains(forecast.probability),
              abs(forecast.windowEnd.timeIntervalSince(forecast.windowStart) - 86_400) < 0.001 else {
            throw PowerAPIError.invalidResponse
        }
        return forecast
    }
}

struct PowerAPIClient: Sendable {
    let baseURL: URL

    func forecast(for levelID: Int) async throws -> PowerForecast {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent("levels")
            .appendingPathComponent(String(levelID))
            .appendingPathComponent("power")
            .appendingPathComponent("forecast")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PowerAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            switch error?.detail.code {
            case "insufficient_data": throw PowerAPIError.insufficientData
            case "model_unavailable": throw PowerAPIError.modelUnavailable
            default: throw PowerAPIError.rejected(http.statusCode)
            }
        }
        return try PowerForecast.decode(data, for: levelID)
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable { let code: String }
        let detail: Detail
    }
}

enum PowerAPIError: LocalizedError, Equatable {
    case insufficientData
    case modelUnavailable
    case invalidResponse
    case rejected(Int)

    var errorDescription: String? {
        switch self {
        case .insufficientData: return "This level has insufficient training history."
        case .modelUnavailable: return "The power model is unavailable on the server."
        case .invalidResponse: return "The power server sent an unexpected forecast."
        case .rejected(let status): return "The power server returned HTTP \(status)."
        }
    }
}
