import DLCore
import Foundation

/// Sends read receipts for a group's chat while it is on screen (docs/design/read-receipts.md).
@MainActor
enum ReadReceipts {
    /// Reports the newest received messages not yet reported, by radio and relays (whichever are on).
    /// Does nothing unless this phone has receipts on for the group. Nothing is queued: a receipt no
    /// route takes is dropped, so it never goes out later, when it would say the wrong time.
    static func send(for group: ChatGroup, groups: GroupModel, online: OnlineModel, mesh: MeshtasticModel) {
        let radio = mesh.isOn && mesh.isReady
        guard groups.receiptGroups.contains(group.id), radio || online.isOn,
              let receipt = groups.takeReceipt(for: group),
              let wire = try? ReadReceipt.wire(reader: receipt.reader, refs: Array(receipt.refs.suffix(ReadReceipt.maxRefs)),
                                               keys: receipt.keys) else { return }
        if radio { mesh.send(wire) }
        if online.isOn { Task { await online.sendReceipt(wire: wire, groupID: group.id, keys: receipt.keys) } }
    }

    /// The line under a sent message: nil when receipts are off here or no one has said they read it.
    static func label(_ message: StoredMessage, on: Bool) -> String? {
        guard on, message.isOutgoing, let count = message.readBy?.count, count > 0 else { return nil }
        return count == 1 ? "Read by 1" : "Read by \(count)"
    }
}
