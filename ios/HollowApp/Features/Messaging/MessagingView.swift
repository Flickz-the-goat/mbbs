import SwiftUI

struct MessagingView: View {
    @ObservedObject var model: MessagingModel
    @State private var entry = ""
    @Binding var recipient: String
    @FocusState private var composing: Bool

    private var destination: UUID? {
        guard let id = UUID(uuidString: recipient.trimmingCharacters(in: .whitespacesAndNewlines)),
              id != model.address else { return nil }
        return id
    }

    private var message: String { entry.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Screen(title: "Messages", subtitle: "Send short messages over Bluetooth, even without internet.") {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.status, systemImage: "antenna.radiowaves.left.and.right")
                if let address = model.address {
                    Text("Your device ID")
                        .font(.caption)
                    Text(address.uuidString)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    ShareLink(item: address.uuidString) {
                        Label("Share device ID", systemImage: "square.and.arrow.up")
                    }
                }
                if let error = model.storageError {
                    Text(error)
                }
            }
            .foregroundStyle(Palette.muted)
            .hollowPanel()

            ForEach(model.messages, id: \.id) { packet in
                let incoming = packet.destination == model.address
                VStack(alignment: .leading, spacing: 6) {
                    Text(incoming ? "From \(packet.origin.uuidString)" : "To \(packet.destination.uuidString)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Palette.muted)
                    Text(packet.payload ?? "")
                    if !incoming {
                        Text(model.deliveryStatus(for: packet))
                            .font(.caption)
                            .foregroundStyle(Palette.signal)
                    }
                }
                .hollowPanel()
                .accessibilityElement(children: .combine)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Recipient device ID", text: $recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !recipient.isEmpty, destination == nil {
                    Text("Enter another Hollow device’s full ID.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                TextField("Write a message", text: $entry, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($composing)
                if message.count > 240 || message.utf8.count > 960 {
                    Text("Use up to 240 characters and 960 UTF-8 bytes.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                Button("Send message", systemImage: "paperplane") {
                    guard let destination, model.send(message, to: destination) else { return }
                    entry = ""
                    composing = false
                }
                .buttonStyle(.bordered)
                .disabled(model.address == nil || destination == nil || !MeshPacket.validText(message))
            }
            .hollowPanel()
        }
    }
}
