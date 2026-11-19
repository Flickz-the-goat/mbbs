import Foundation
import Combine
import SwiftData

@Model
final class StoredMeshState {
    var data: Data

    init(data: Data) { self.data = data }
}

private final class MeshStore {
    private let context: ModelContext
    private let record: StoredMeshState
    let initialState: MeshState

    init() throws {
        let container = try ModelContainer(for: StoredMeshState.self)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.context = context
        if let existing = try context.fetch(FetchDescriptor<StoredMeshState>()).first {
            record = existing
            initialState = try JSONDecoder().decode(MeshState.self, from: existing.data)
        } else {
            let state = MeshState(address: UUID())
            let record = StoredMeshState(data: try JSONEncoder().encode(state))
            initialState = state
            self.record = record
            context.insert(record)
            try context.save()
        }
    }

    func save(_ state: MeshState) throws {
        record.data = try JSONEncoder().encode(state)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

final class MessagingModel: ObservableObject {
    @Published private(set) var router: MeshRouter?
    @Published private(set) var status = "Bluetooth paused"
    @Published private(set) var storageError: String?
    @Published private(set) var sentToPeer: Set<UUID> = []
    @Published private(set) var now = Date.now

    private let transport: PeerTransport

    init(transport: PeerTransport = BluetoothTransport()) {
        self.transport = transport
        do {
            let store = try MeshStore()
            router = MeshRouter(state: store.initialState, save: store.save)
        } catch {
            storageError = "Could not open on-device message storage."
        }

        transport.onStatus = { [weak self] in self?.status = $0 }
        transport.onReceive = { [weak self] data in
            self?.apply { try $0.receive(data) } ?? false
        }
        transport.onSent = { [weak self] id in
            guard let self, self.messages.contains(where: {
                $0.id == id && $0.origin == self.address
            }) else { return }
            self.sentToPeer.insert(id)
        }
    }

    var address: UUID? { router?.state.address }

    var messages: [MeshPacket] {
        guard let router else { return [] }
        let address = router.state.address
        return router.state.packets.filter {
            $0.payload != nil && ($0.origin == address || $0.destination == address)
        }
    }

    func start() {
        guard router != nil else { return }
        transport.start()
        tick()
    }

    func stop() {
        transport.stop()
        status = "Bluetooth paused"
    }

    func tick() {
        now = .now
        transport.update(router?.outgoing(at: now) ?? [])
    }

    func send(_ text: String, to destination: UUID) -> Bool {
        apply { try $0.send(text, to: destination) }
    }

    func deliveryStatus(for packet: MeshPacket) -> String {
        if router?.isDelivered(packet) == true { return "Delivered" }
        if !packet.isLive(at: now) { return "Expired" }
        return sentToPeer.contains(packet.id) ? "Sent to peer" : "Queued"
    }

    private func apply(_ operation: (inout MeshRouter) throws -> Void) -> Bool {
        guard var router else { return false }
        do {
            try operation(&router)
            self.router = router
            storageError = nil
            tick()
            return true
        } catch {
            storageError = "Could not save a message on this device."
            return false
        }
    }
}
