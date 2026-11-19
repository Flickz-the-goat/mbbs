import SwiftUI

struct MessagingView: View {
    @ObservedObject var model: MessagingModel
    let contacts: [ContactProfile]
    @Binding var path: [UUID]
    @State private var showingCompose = false
    @State private var recipient = ""

    private var destination: UUID? {
        guard let id = UUID(uuidString: recipient.trimmingCharacters(in: .whitespacesAndNewlines)),
              id != model.address else { return nil }
        return id
    }

    var body: some View {
        let messagesByPeer = Dictionary(grouping: model.messages) { packet in
            packet.origin == model.address ? packet.destination : packet.origin
        }
        let latestByPeer = messagesByPeer.compactMapValues { messages in
            messages.max { $0.createdAt < $1.createdAt }
        }
        let recentPeers = latestByPeer.sorted { first, second in
            if first.value.createdAt == second.value.createdAt {
                return first.key.uuidString < second.key.uuidString
            }
            return first.value.createdAt > second.value.createdAt
        }.map { $0.key }
        var seen = Set(recentPeers)
        let peers = recentPeers + contacts.map(\.deviceId).filter {
            $0 != model.address && seen.insert($0).inserted
        }

        NavigationStack(path: $path) {
            List {
                Section {
                    Label(model.status, systemImage: "antenna.radiowaves.left.and.right")
                    if let address = model.address {
                        ShareLink(item: address.uuidString) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Share your device ID", systemImage: "square.and.arrow.up")
                                Text(address.uuidString)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                    }
                    if let error = model.storageError { Text(error) }
                }
                Section("Conversations") {
                    if peers.isEmpty {
                        Text("Add contacts in Account or start a chat with a device ID.")
                            .foregroundStyle(Palette.muted)
                    }
                    ForEach(peers, id: \.self) { peer in
                        NavigationLink(value: peer) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(for: peer))
                                    .font(.headline)
                                if let payload = latestByPeer[peer]?.payload {
                                    Text(payload)
                                        .lineLimit(1)
                                        .foregroundStyle(Palette.muted)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                Button("New message", systemImage: "square.and.pencil") {
                    recipient = ""
                    showingCompose = true
                }
                .disabled(model.address == nil)
            }
            .navigationDestination(for: UUID.self) { peer in
                ConversationView(model: model, peer: peer, title: title(for: peer))
                    .id(peer)
            }
        }
        .sheet(isPresented: $showingCompose) {
            NavigationStack {
                Form {
                    TextField("Recipient device ID", text: $recipient)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle("New message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingCompose = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Open chat") {
                            guard let destination else { return }
                            path = [destination]
                            showingCompose = false
                        }
                        .disabled(destination == nil)
                    }
                }
            }
        }
    }

    private func title(for peer: UUID) -> String {
        contacts.first { $0.deviceId == peer }?.name ?? peer.uuidString
    }
}

private struct ConversationView: View {
    @ObservedObject var model: MessagingModel
    let peer: UUID
    let title: String
    @State private var entry = ""
    @FocusState private var composing: Bool

    private var message: String { entry.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let messages = model.messages.filter {
            $0.origin == peer || $0.destination == peer
        }.sorted { $0.createdAt < $1.createdAt }

        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            Text("No messages yet.")
                                .foregroundStyle(Palette.muted)
                        }
                        ForEach(messages, id: \.id) { packet in
                            bubble(packet)
                                .id(packet.id)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.last?.id, initial: true) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }

            composer
        }
        .background(Palette.ground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.storageError {
                Text(error).font(.caption)
            }
            if message.count > 240 || message.utf8.count > 960 {
                Text("Use up to 240 characters and 960 UTF-8 bytes.")
                    .font(.caption)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Write a message", text: $entry, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Palette.ground, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .focused($composing)
                    .onTapGesture { composing = true }

                Button("Send message", systemImage: "arrow.up.circle.fill") {
                    if model.send(message, to: peer) { entry = "" }
                }
                .labelStyle(.iconOnly)
                .font(.title)
                .frame(minWidth: 44, minHeight: 44)
                .disabled(model.address == nil || !MeshPacket.validText(message))
            }
        }
        .padding(12)
        .background(Palette.panel)
    }

    private func bubble(_ packet: MeshPacket) -> some View {
        let outgoing = packet.origin == model.address

        return HStack {
            if outgoing { Spacer(minLength: 40) }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 4) {
                Text(packet.payload ?? "")
                    .padding(10)
                    .foregroundStyle(outgoing ? Palette.ground : .white)
                    .background(outgoing ? Palette.signal : Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                if outgoing {
                    Text(model.deliveryStatus(for: packet))
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            if !outgoing { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
    }
}
