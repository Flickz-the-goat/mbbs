import Combine
import Foundation
import Supabase

struct ContactProfile: Codable, Identifiable {
    let username: String
    let name: String
    let deviceId: UUID

    var id: String { username }

    enum CodingKeys: String, CodingKey {
        case username, name
        case deviceId = "device_id"
    }
}

struct AccountProfile: Codable {
    let id: UUID
    let username: String
    let name: String
    let level: Int
    let deviceId: UUID

    enum CodingKeys: String, CodingKey {
        case id, username, name, level
        case deviceId = "device_id"
    }
}

private struct CachedAccount: Codable {
    let profile: AccountProfile
    var contacts: [ContactProfile]
}

private enum AccountError: LocalizedError {
    case username, name, wrongDevice, usernameTaken, deviceTaken, invalidLink

    var errorDescription: String? {
        switch self {
        case .username: "Use 3–24 lowercase letters, numbers, or underscores for your username."
        case .name: "Enter a name between 1 and 80 characters."
        case .wrongDevice: "This profile is linked to another Hollow device. Sign out to use a different account."
        case .usernameTaken: "That username is already taken."
        case .invalidLink: "This email link is invalid or expired. Request a new link in Hollow."
        case .deviceTaken: "This device is already linked to another Hollow account."
        }
    }
}

@MainActor
final class AccountModel: ObservableObject {
    @Published private var cached: CachedAccount?
    @Published private(set) var signedIn = false
    @Published private(set) var resettingPassword = false
    @Published private(set) var needsProfile = false
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?

    private static let confirmationURL = URL(string: "hollow-auth://callback/confirm")!
    private static let recoveryURL = URL(string: "hollow-auth://callback/recover")!

    private let client: SupabaseClient?
    private let cacheKey: String
    private var authObserver: Task<Void, Never>?

    var configured: Bool { client != nil }
    var user: AccountProfile? { cached?.profile }
    var contacts: [ContactProfile] { cached?.contacts ?? [] }

    init(bundle: Bundle = .main) {
        guard let input = bundle.object(forInfoDictionaryKey: "HollowSupabaseURL") as? String,
              let url = URL(string: input), url.scheme == "https", let host = url.host,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              let key = bundle.object(forInfoDictionaryKey: "HollowSupabasePublishableKey") as? String,
              key.hasPrefix("sb_publishable_"), key != "sb_publishable_REPLACE_ME" else {
            client = nil
            cacheKey = ""
            return
        }
        let client = SupabaseClient(
            supabaseURL: url, supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
        self.client = client
        cacheKey = "hollowSupabaseAccount.\(host)"
        signedIn = client.auth.currentUser != nil
        if let id = client.auth.currentUser?.id,
           let data = UserDefaults.standard.data(forKey: cacheKey),
           let account = try? JSONDecoder().decode(CachedAccount.self, from: data),
           account.profile.id == id {
            cached = account
        }
        authObserver = Task { [weak self] in
            for await (event, _) in client.auth.authStateChanges {
                if event == .signedOut, client.auth.currentSession == nil {
                    self?.clearAccount()
                }
            }
        }
    }

    deinit { authObserver?.cancel() }

    func restore(deviceID: UUID) async {
        guard signedIn, !resettingPassword, let client else { return }
        if let user, user.deviceId != deviceID {
            discardCache()
        }
        await perform { try await loadAccount(client, deviceID: deviceID) }
    }

    func authenticate(email: String, password: String, registering: Bool, deviceID: UUID) async {
        guard let client else { return }
        await perform {
            let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if registering {
                let response = try await client.auth.signUp(
                    email: email, password: password, redirectTo: Self.confirmationURL
                )
                guard response.session != nil else {
                    notice = "Open the confirmation link on this device, or confirm your email and return here to log in."
                    return
                }
            } else {
                try await client.auth.signIn(email: email, password: password)
            }
            signedIn = true
            try await loadAccount(client, deviceID: deviceID)
        }
    }

    func sendPasswordReset(email: String) async {
        guard let client else { return }
        await perform {
            try await client.auth.resetPasswordForEmail(
                email.trimmingCharacters(in: .whitespacesAndNewlines), redirectTo: Self.recoveryURL
            )
            notice = "If an account exists for that email, open the reset link on this device."
        }
    }

    func handleAuthLink(_ url: URL, deviceID: UUID?) async {
        guard let client, !signedIn, url.scheme == Self.confirmationURL.scheme,
              url.host == Self.confirmationURL.host else { return }
        let isRecovery = url.path == Self.recoveryURL.path
        guard isRecovery || url.path == Self.confirmationURL.path else { return }
        await perform {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            guard query?.contains(where: { $0.name == "code" && $0.value?.isEmpty == false }) == true else {
                throw AccountError.invalidLink
            }
            _ = try await client.auth.session(from: url)
            resettingPassword = isRecovery
            signedIn = true
            if !isRecovery, let deviceID {
                try await loadAccount(client, deviceID: deviceID)
            }
        }
    }

    func updatePassword(_ password: String, deviceID: UUID) async {
        guard let client, resettingPassword, password.count >= 8 else { return }
        await perform {
            try await client.auth.update(user: UserAttributes(password: password))
            resettingPassword = false
            try await loadAccount(client, deviceID: deviceID)
        }
    }

    func createProfile(username: String, name: String, level: Int, deviceID: UUID) async {
        guard let client else { return }
        await perform {
            let username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard username.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) != nil else { throw AccountError.username }
            guard (1...80).contains(name.unicodeScalars.count) else { throw AccountError.name }
            let session = try await client.auth.session
            let profile = AccountProfile(id: session.user.id, username: username, name: name,
                                         level: level, deviceId: deviceID)
            do {
                try await client.from("hollow_profiles").insert(profile).execute()
            } catch let error as PostgrestError where error.code == "23505" {
                // A retry may follow a successful insert whose response was lost.
                if let existing = try await fetchProfile(client, id: profile.id) {
                    try await applyProfile(existing, client: client, deviceID: deviceID)
                    return
                }
                if error.message.contains("hollow_profiles_username_key") { throw AccountError.usernameTaken }
                if error.message.contains("hollow_profiles_device_id_key") { throw AccountError.deviceTaken }
                throw error
            }
            try await applyProfile(profile, client: client, deviceID: deviceID)
        }
    }

    func refreshContacts() async {
        guard let client, let user else { return }
        await perform { try await applyProfile(user, client: client, deviceID: user.deviceId) }
    }

    func addContact(_ username: String) async {
        guard let client, let user else { return }
        await perform {
            let result: [ContactProfile] = try await client.rpc(
                "hollow_add_contact", params: ["contact_username": username]
            ).execute().value
            guard let contact = result.first, var account = cached, account.profile.id == user.id,
                  client.auth.currentUser?.id == user.id else { return }
            account.contacts.removeAll { $0.username == contact.username }
            account.contacts.append(contact)
            account.contacts.sort { $0.username < $1.username }
            save(account)
        }
    }

    func signOut() async {
        guard let client else { return }
        await perform {
            defer { clearAccount() }
            do {
                try await client.auth.signOut(scope: .local)
            } catch is URLError {
                // The SDK removes the local session before attempting revocation.
                return
            }
        }
    }

    private func loadAccount(_ client: SupabaseClient, deviceID: UUID) async throws {
        let session = try await client.auth.session
        if let profile = try await fetchProfile(client, id: session.user.id) {
            try await applyProfile(profile, client: client, deviceID: deviceID)
        } else if client.auth.currentUser?.id == session.user.id {
            discardCache()
            needsProfile = true
        }
    }

    private func fetchProfile(_ client: SupabaseClient, id: UUID) async throws -> AccountProfile? {
        let profiles: [AccountProfile] = try await client.from("hollow_profiles")
            .select().eq("id", value: id.uuidString).execute().value
        return profiles.first
    }

    private func applyProfile(_ profile: AccountProfile, client: SupabaseClient, deviceID: UUID) async throws {
        guard client.auth.currentUser?.id == profile.id else { return }
        needsProfile = false
        guard profile.deviceId == deviceID else {
            discardCache()
            throw AccountError.wrongDevice
        }
        if cached?.profile.id != profile.id {
            save(CachedAccount(profile: profile, contacts: []))
        }
        let contacts: [ContactProfile] = try await client.rpc("hollow_list_contacts").execute().value
        guard client.auth.currentUser?.id == profile.id else { return }
        save(CachedAccount(profile: profile, contacts: contacts))
    }

    private func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do {
            try await operation()
        } catch is CancellationError {
            return
        } catch let error as PostgrestError {
            self.error = error.message
        } catch is URLError {
            error = "Could not reach Supabase. Saved contacts are available offline."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save(_ account: CachedAccount) {
        cached = account
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func discardCache() {
        cached = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    private func clearAccount() {
        discardCache()
        signedIn = false
        needsProfile = false
        resettingPassword = false
    }
}
