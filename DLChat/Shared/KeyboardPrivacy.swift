import SwiftUI

/// Autocorrect is on only in the Chat message boxes (group Chat, Meshtastic chats and Internet Messages), owner
/// decision 2026-11-09 ("1C"). Every other field keeps `autocorrectionDisabled()`: Send, Receive,
/// the phrase, PINs, picture passwords, room words, relay addresses, names, search and the
/// debug-log note. A "correction" would corrupt exact strings, and the keyboard would learn secrets.
///
/// The cost, accepted by the owner: with autocorrect on, the iOS keyboard remembers words typed in
/// Chat (its learned dictionary and QuickType suggestions). That memory lives outside DLChat's
/// sealed store, Wipe cannot reach it, and only iOS Settings > General > Transfer or Reset iPhone >
/// Reset > Reset Keyboard Dictionary clears it. PINs are `SecureField`s, which iOS also keeps out of
/// keyboard learning.
extension View {
    /// A Chat message box: autocorrect on, capital at the start of each sentence.
    func chatKeyboard() -> some View {
        textInputAutocapitalization(.sentences).autocorrectionDisabled(false)
    }
}
