import Foundation
import Observation

/// What this phone shows of the radio's channels and nodes. Phone-side only: nothing here is ever written
/// to the radio, so hiding or muting never changes what the radio sends, hears or forwards.
@MainActor @Observable
final class MeshPrefs {
    static let shared = MeshPrefs()

    private(set) var hiddenChannels: Set<UInt32> = MeshPrefs.load("mesh.hiddenChannels")
    private(set) var mutedChannels: Set<UInt32> = MeshPrefs.load("mesh.mutedChannels")
    private(set) var mutedNodes: Set<UInt32> = MeshPrefs.load("mesh.mutedNodes")
    /// Ignored radios are not listed and their messages are dropped on arrival.
    private(set) var ignoredNodes: Set<UInt32> = MeshPrefs.load("mesh.ignoredNodes")

    func setHidden(_ on: Bool, channel: UInt32) { Self.flip(&hiddenChannels, channel, on, "mesh.hiddenChannels") }
    func setMuted(_ on: Bool, channel: UInt32) { Self.flip(&mutedChannels, channel, on, "mesh.mutedChannels") }
    func setMuted(_ on: Bool, node: UInt32) { Self.flip(&mutedNodes, node, on, "mesh.mutedNodes") }
    func setIgnored(_ on: Bool, node: UInt32) { Self.flip(&ignoredNodes, node, on, "mesh.ignoredNodes") }

    func isMuted(_ conversation: MeshConversation) -> Bool {
        switch conversation {
        case .channel(let i): mutedChannels.contains(i)
        case .direct(let n): mutedNodes.contains(n)
        }
    }

    /// Part of a full wipe: the phone forgets every choice.
    func wipe() {
        hiddenChannels = []; mutedChannels = []; mutedNodes = []; ignoredNodes = []
        for key in ["mesh.hiddenChannels", "mesh.mutedChannels", "mesh.mutedNodes", "mesh.ignoredNodes"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func load(_ key: String) -> Set<UInt32> {
        Set((UserDefaults.standard.array(forKey: key) as? [Int] ?? []).compactMap(UInt32.init(exactly:)))
    }

    private static func flip(_ set: inout Set<UInt32>, _ value: UInt32, _ on: Bool, _ key: String) {
        if on { set.insert(value) } else { set.remove(value) }
        UserDefaults.standard.set(set.map(Int.init).sorted(), forKey: key)
    }
}
