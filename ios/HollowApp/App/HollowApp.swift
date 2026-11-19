import SwiftUI

@main
struct HollowApp: App {
    var body: some Scene {
        WindowGroup {
            HollowTabs()
                .preferredColorScheme(.dark)
        }
    }
}

private struct HollowTabs: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var messaging = MessagingModel()
    @StateObject private var account = AccountModel()
    @State private var tab = Tab.account
    @State private var conversations: [UUID] = []

    private enum Tab { case account, messages, power, food, blackout }

    var body: some View {
        TabView(selection: $tab) {
            MessagingView(model: messaging, contacts: account.contacts, path: $conversations)
                .tag(Tab.messages)
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
            PowerView()
                .tag(Tab.power)
                .tabItem { Label("Power", systemImage: "bolt") }
            FoodView(
                assignment: (account.user?.id ?? messaging.address).map(DemoFoodAssignment.init),
                isGuest: account.user == nil
            )
            .tag(Tab.food)
            .tabItem { Label("Food", systemImage: "shippingbox") }
            AccountView(model: account, deviceID: messaging.address) { id in
                conversations = [id]
                tab = .messages
            }
            .tag(Tab.account)
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
            BlackoutView(messaging: messaging, contacts: account.contacts)
                .tag(Tab.blackout)
                .tabItem { Label("Blackout", systemImage: "bolt.slash") }
        }
        .onOpenURL { url in
            guard url.scheme == "hollow-auth", url.host == "callback" else { return }
            tab = .account
            Task { await account.handleAuthLink(url, deviceID: messaging.address) }
        }
        .tint(Palette.signal)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                messaging.start()
            } else if phase == .background {
                messaging.stop()
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                    messaging.tick()
                } catch {
                    return
                }
            }
        }
    }
}
