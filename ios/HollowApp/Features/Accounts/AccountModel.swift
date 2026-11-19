import Foundation
import Security
import Combine

struct ContactProfile: Codable, Identifiable {
    let username: String
    let name: String
    let deviceId: UUID

    var id: String { username }
}

struct AccountProfile: Codable {
    let username: String
    let name: String
    let level: Int
    let deviceId: UUID
}

struct AccountSession: Codable {
    let user: AccountProfile
    let token: String
}

private struct CachedAccount: Codable {
    let server: URL
    let session: AccountSession
    var contacts: [ContactProfile] = []
}

private struct ErrorResponse: Decodable { let detail: String }

private enum AccountError: LocalizedError {
    case serverURL, response, storage
    case rejected(Int, String)

    var errorDescription: String? {
        switch self {
        case .serverURL: "Enter the HTTPS URL for your Hollow backend."
        case .response: "The Hollow backend returned an unexpected response."
        case .storage: "Could not update the account saved on this device."
        case let .rejected(_, message): message
        }
    }
}

@MainActor
final class AccountModel: ObservableObject {
    @Published private var cached: CachedAccount?
    @Published private(set) var busy = false
    @Published private(set) var error: String?

    var user: AccountProfile? { cached?.session.user }
    var contacts: [ContactProfile] { cached?.contacts ?? [] }

    init() {
        var query = Self.keychainQuery
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            cached = try? JSONDecoder().decode(CachedAccount.self, from: data)
        }
    }

    func signIn(server input: String, username: String, password: String, deviceID: UUID,
                registration: (name: String, level: Int)? = nil) async {
        await perform {
            let server = try Self.serverURL(input)
            struct Credentials: Encodable {
                let username: String
                let password: String
                let deviceId: UUID
                let name: String?
                let level: Int?
            }
            let body = Credentials(username: username, password: password, deviceId: deviceID,
                                   name: registration?.name, level: registration?.level)
            let path = registration == nil ? "login" : "register"
            let session: AccountSession = try await request(path, server: server, body: body)
            guard session.user.deviceId == deviceID else { throw AccountError.response }
            let previous = cached
            let existing = previous?.server == server && previous?.session.user.username == session.user.username
            try save(CachedAccount(server: server, session: session, contacts: existing ? contacts : []))
            if registration == nil {
                try await loadContacts()
            }
        }
    }

    func refreshContacts() async {
        await perform { try await loadContacts() }
    }

    func addContact(_ username: String) async {
        await perform {
            guard var account = cached else { return }
            struct Lookup: Encodable { let username: String }
            let contact: ContactProfile = try await request("contacts", server: account.server,
                                                             token: account.session.token,
                                                             body: Lookup(username: username))
            account.contacts.removeAll { $0.username == contact.username }
            account.contacts.append(contact)
            account.contacts.sort { $0.username < $1.username }
            try save(account)
        }
    }

    func signOut() async {
        await perform {
            guard let account = cached else { return }
            let result = SecItemDelete(Self.keychainQuery as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else { throw AccountError.storage }
            cached = nil

            // The local account can always be cleared while offline.
            var request = URLRequest(url: account.server.appending(path: "api/v1/logout"), timeoutInterval: 8)
            request.httpMethod = "POST"
            request.setValue("Bearer \(account.session.token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    private func loadContacts() async throws {
        guard var account = cached else { return }
        account.contacts = try await request("contacts", server: account.server, token: account.session.token,
                                             body: Optional<String>.none)
        try save(account)
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await operation()
        } catch AccountError.rejected(401, _) where cached != nil {
            error = "Your server session expired. Sign out and sign in again to update contacts."
        } catch is URLError {
            error = "Could not reach the Hollow backend."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func request<Output: Decodable, Body: Encodable>(
        _ path: String, server: URL, token: String? = nil, body: Body?
    ) async throws -> Output {
        var request = URLRequest(url: server.appending(path: "api/v1/\(path)"), timeoutInterval: 15)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw AccountError.response }
        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
            throw AccountError.rejected(response.statusCode, detail ?? "The Hollow backend could not complete the request.")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Output.self, from: data)
    }

    private static func serverURL(_ input: String) throws -> URL {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)) else {
            throw AccountError.serverURL
        }
        return url
    }

    private static let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Hollow.Account",
        kSecAttrAccount as String: "current"
    ]

    private func save(_ account: CachedAccount) throws {
        let data = try JSONEncoder().encode(account)
        let attributes = [kSecValueData as String: data]
        var result = SecItemUpdate(Self.keychainQuery as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var query = Self.keychainQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            result = SecItemAdd(query as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw AccountError.storage }
        cached = account
    }
}
