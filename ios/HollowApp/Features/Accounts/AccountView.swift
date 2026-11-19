import SwiftUI

struct AccountView: View {
    @ObservedObject var model: AccountModel
    let deviceID: UUID?
    let messageContact: (UUID) -> Void

    @AppStorage("hollowServerURL") private var server = ""
    @State private var registration = false
    @State private var username = ""
    @State private var name = ""
    @State private var password = ""
    @State private var level: Level = .two
    @State private var contactUsername = ""

    var body: some View {
        if let user = model.user {
            Screen(title: "Account", subtitle: "@\(user.username) · Level \(user.level)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(user.name).font(.headline)
                    deviceAddress(user.deviceId)
                }
                .hollowPanel()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Contacts").font(.headline)
                    TextField("Contact username", text: $contactUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("Add contact", systemImage: "person.badge.plus") {
                            Task { await model.addContact(contactUsername) }
                        }
                        .disabled(contactUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await model.refreshContacts() }
                        }
                    }
                    if model.contacts.isEmpty { Text("No saved contacts.").foregroundStyle(Palette.muted) }
                    ForEach(model.contacts) { contact in
                        Button {
                            messageContact(contact.deviceId)
                        } label: {
                            Label("\(contact.name) · @\(contact.username)", systemImage: "bubble.left")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.busy)
                .hollowPanel()
                status
                Button("Sign out") { Task { await model.signOut() } }
                    .disabled(model.busy)
                    .buttonStyle(.bordered)
            }
        } else {
            Screen(title: registration ? "Create account" : "Log in",
                   subtitle: "Sign in to save contacts and message them by username.") {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Backend URL", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if registration {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                        Picker("Hollow level", selection: $level) {
                            ForEach(Level.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    SecureField("Password", text: $password)
                        .textContentType(registration ? .newPassword : .password)
                    if let deviceID {
                        deviceAddress(deviceID)
                    } else {
                        Text("The device ID is unavailable.").foregroundStyle(Palette.muted)
                    }
                    Button(registration ? "Create account" : "Log in") {
                        guard let deviceID else { return }
                        Task {
                            await model.signIn(server: server, username: username, password: password,
                                               deviceID: deviceID, registration: registration ? (name, level.rawValue) : nil)
                            if model.user != nil { password = "" }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || deviceID == nil || username.isEmpty || password.count < 8 ||
                              (registration && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    Button(registration ? "Already have an account? Log in" : "Create an account") {
                        registration.toggle()
                    }
                    .disabled(model.busy)
                }
                .hollowPanel()
                status
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading) {
            if model.busy { ProgressView() }
            if let error = model.error { Text(error).foregroundStyle(Palette.signal) }
        }
    }

    private func deviceAddress(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Device ID").font(.caption)
            Text(id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
        }
        .foregroundStyle(Palette.muted)
    }
}
