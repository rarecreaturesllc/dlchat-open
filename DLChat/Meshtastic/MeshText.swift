import Foundation

/// A Meshtastic chat Chat can show besides the DLChat groups: one of the radio's channels, or one radio directly.
enum MeshConversation: Hashable, Codable {
    case channel(UInt32)
    case direct(UInt32)

    var isDirect: Bool { if case .direct = self { true } else { false } }
}

/// One plain Meshtastic text message. Memory only, unless the person chose to keep Meshtastic chats
/// (`MeshArchive`): then also in the sealed Vault store.
struct MeshText: Identifiable, Equatable, Codable {
    enum State: Equatable, Codable {
        case received
        /// The radio has it and is sending.
        case sending
        /// Another radio repeated it (channel) or passed it on (direct); not yet confirmed by the recipient.
        case relayed
        /// The recipient's radio confirmed it (direct only).
        case delivered
        case failed(String)
    }

    var id = UUID()
    let packetID: UInt32
    let from: UInt32
    let text: String
    let at: Date
    let outgoing: Bool
    /// Sent or received with Meshtastic's public-key encryption.
    let isPrivate: Bool
    let hops: Int?
    var state: State
}
