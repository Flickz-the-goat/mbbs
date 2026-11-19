import SwiftUI

struct AccountView: View {
    @ObservedObject var model: AccountModel
    let deviceID: UUID?
    let messageContact: (UUID) -> Void

    @State private var email = ""
    @State private var registration = false
    @State private var username = ""
    @State private var name = ""
    @State private var password = ""
    @State private var replacementPassword = ""
    @State private var level: Level = .two
    @State private var contactUsername = ""

    var body: some View {
        Group {
            accountContent
        }
        .task(id: deviceID) {
            if let deviceID { await model.restore(deviceID: deviceID) }
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        if !model.configured {
            Screen(title: "Account", subtitle: "Supabase setup required") {
                Text("Set the Supabase project URL and publishable key in Hollow’s Info.plist.")
                    .hollowPanel()
            }
        } else if model.resettingPassword {
            Screen(title: "Reset password", subtitle: "Use at least eight characters.") {
                SecureField("New password", text: $replacementPassword)
                    .textContentType(.newPassword)
                    .hollowPanel()
                Button("Update password") {
                    guard let deviceID else { return }
                    Task {
                        await model.updatePassword(replacementPassword, deviceID: deviceID)
                        if !model.resettingPassword { replacementPassword = "" }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.busy || deviceID == nil || replacementPassword.count < 8)
                Button("Cancel and sign out") {
                    replacementPassword = ""
                    Task { await model.signOut() }
                }
                .disabled(model.busy)
                status
            }
        } else if let user = model.user {
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
        } else if model.signedIn {
            Screen(title: "Account", subtitle: model.needsProfile ? "Set up your Hollow profile." : "Load your Hollow profile.") {
                if model.needsProfile {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Name", text: $name).textContentType(.name)
                        Picker("Hollow level", selection: $level) {
                            ForEach(Level.allCases) { Text($0.title).tag($0) }
                        }
                        if let deviceID { deviceAddress(deviceID) }
                        Button("Save profile") {
                            guard let deviceID else { return }
                            Task {
                                await model.createProfile(username: username, name: name,
                                                          level: level.rawValue, deviceID: deviceID)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.busy || deviceID == nil || username.isEmpty || name.isEmpty)
                    }
                    .hollowPanel()
                } else {
                    Button("Reload profile") {
                        if let deviceID { Task { await model.restore(deviceID: deviceID) } }
                    }
                    .disabled(model.busy || deviceID == nil)
                }
                status
                Button("Sign out") { Task { await model.signOut() } }
                    .disabled(model.busy)
                    .buttonStyle(.bordered)
            }
        } else {
            Screen(title: registration ? "Create account" : "Log in",
                   subtitle: "Sign in to save contacts and message them by username.") {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(registration ? .newPassword : .password)
                    if deviceID == nil {
                        Text("The device ID is unavailable.").foregroundStyle(Palette.muted)
                    }
                    Button(registration ? "Create account" : "Log in") {
                        guard let deviceID else { return }
                        Task {
                            await model.authenticate(email: email, password: password,
                                                     registering: registration, deviceID: deviceID)
                            if model.signedIn || model.notice != nil { password = "" }
                            if model.notice != nil { registration = false }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || deviceID == nil || email.isEmpty || password.isEmpty ||
                              (registration && password.count < 8))
                    if !registration {
                        Button("Send password reset email") {
                            Task { await model.sendPasswordReset(email: email) }
                        }
                        .disabled(model.busy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
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
            if let notice = model.notice { Text(notice).foregroundStyle(Palette.muted) }
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
