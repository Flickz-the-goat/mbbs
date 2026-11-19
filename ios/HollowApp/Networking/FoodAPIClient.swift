import Foundation

struct FoodHousehold: Encodable, Equatable, Sendable {
    var levelId = 2
    var householdSize = 3
    var childrenCount = 1
    var seniorCount = 1
    var riceKg = 1.0
    var beansKg = 1.0
    var cannedFoodCount = 2
    var waterLiters = 4.0
    var dailyPortionsPerPerson = 2.0
    var planningDays = 4
    var reservePortionsPerPerson = 1.0
}

struct FoodDemandPrediction: Decodable, Sendable {
    let predictedAdditionalRationUnits: Double
    let unit: String
}

struct SharedFoodAllocationRequest: Encodable, Equatable, Sendable {
    let demands: [Double]
    let availableSharedUnits: Double
}

struct SharedFoodAllocation: Decodable, Sendable {
    let allocatedUnits: [Double]
    let remainingUnits: Double
}

struct FoodAPIClient: Sendable {
    let baseURL: URL

    static var configured: FoodAPIClient? {
        guard let url = BackendConfiguration.baseURL else { return nil }
        return FoodAPIClient(baseURL: url)
    }

    func predict(_ household: FoodHousehold) async throws -> FoodDemandPrediction {
        try await post("predict-demand", payload: household)
    }

    func allocate(_ request: SharedFoodAllocationRequest) async throws -> SharedFoodAllocation {
        let result: SharedFoodAllocation = try await post("allocate", payload: request)
        guard result.allocatedUnits.count == request.demands.count else {
            throw FoodAPIError.invalidResponse
        }
        return result
    }

    private func post<Payload: Encodable, Result: Decodable>(
        _ endpoint: String, payload: Payload
    ) async throws -> Result {
        let url = baseURL.appendingPathComponent("food").appendingPathComponent(endpoint)
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FoodAPIError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200..<300).contains(http.statusCode) else {
            let detail = try? decoder.decode(ValidationErrorResponse.self, from: data)
            throw FoodAPIError.rejected(http.statusCode, detail?.detail.first?.msg)
        }
        do {
            return try decoder.decode(Result.self, from: data)
        } catch {
            throw FoodAPIError.invalidResponse
        }
    }

    private struct ValidationErrorResponse: Decodable {
        struct Issue: Decodable {
            let msg: String
        }

        let detail: [Issue]
    }
}

private enum FoodAPIError: LocalizedError {
    case invalidResponse
    case rejected(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The food server sent an unexpected response."
        case let .rejected(status, message):
            return message ?? "The food server returned HTTP \(status)."
        }
    }
}
