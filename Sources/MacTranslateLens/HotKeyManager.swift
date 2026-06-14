import AppKit
import Carbon.HIToolbox

/// A parsed hotkey combination, ready for both Carbon registration and menu display.
struct HotKeySpec {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyEquivalent: String
    let modifierMask: NSEvent.ModifierFlags
    let display: String
}

/// Registers a single system-wide hotkey using the Carbon Hot Key API.
///
/// `RegisterEventHotKey` works without Accessibility or Input Monitoring
/// permission, so triggering a clipboard translation never prompts the user —
/// unlike `NSEvent.addGlobalMonitorForEvents`, which requires Accessibility.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?

    /// Registers `spec` as a global hotkey. Returns false if the OS refused it
    /// (e.g. the combination is already claimed by another app).
    @discardableResult
    func register(_ spec: HotKeySpec, onPress: @escaping () -> Void) -> Bool {
        unregister()
        self.onPress = onPress

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.onPress?()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: 0x4D_54_4C_53 /* 'MTLS' */, id: 1)
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        onPress = nil
    }

    deinit {
        unregister()
    }

    // MARK: - Parsing

    private static let cmdMask: UInt32 = 0x0100
    private static let shiftMask: UInt32 = 0x0200
    private static let optionMask: UInt32 = 0x0800
    private static let controlMask: UInt32 = 0x1000

    /// Parses a spec like "ctrl+opt+cmd+t" or "cmd+shift+t".
    /// Accepts cmd/command/⌘, shift/⇧, opt/option/alt/⌥, ctrl/control/⌃, plus
    /// one key (a–z, 0–9, or "space"). Returns nil if no valid key is present.
    static func parse(_ spec: String) -> HotKeySpec? {
        var carbon: UInt32 = 0
        var mask: NSEvent.ModifierFlags = []
        var symbols = ""
        var keyChar: Character?
        var keyCode: UInt32?

        let tokens = spec
            .lowercased()
            .split(whereSeparator: { $0 == "+" || $0 == " " || $0 == "-" })
            .map(String.init)

        for token in tokens {
            switch token {
            case "cmd", "command", "⌘":
                carbon |= cmdMask; mask.insert(.command); symbols += "⌘"
            case "shift", "⇧":
                carbon |= shiftMask; mask.insert(.shift); symbols += "⇧"
            case "opt", "option", "alt", "⌥":
                carbon |= optionMask; mask.insert(.option); symbols += "⌥"
            case "ctrl", "control", "⌃":
                carbon |= controlMask; mask.insert(.control); symbols += "⌃"
            default:
                if let code = virtualKeyCode(for: token) {
                    keyCode = code
                    keyChar = token.first
                }
            }
        }

        guard let keyCode, let keyChar else { return nil }

        let keyDisplay = displayName(for: keyChar)
        return HotKeySpec(
            keyCode: keyCode,
            carbonModifiers: carbon,
            keyEquivalent: String(keyChar),
            modifierMask: mask,
            display: symbols + keyDisplay
        )
    }

    private static func displayName(for char: Character) -> String {
        char == " " ? "Space" : String(char).uppercased()
    }

    /// Maps a single-key token to its Carbon virtual key code.
    private static func virtualKeyCode(for token: String) -> UInt32? {
        if token == "space" { return UInt32(kVK_Space) }
        guard token.count == 1, let char = token.first else { return nil }

        let letters: [Character: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ]

        if let code = letters[char] {
            return UInt32(code)
        }
        return nil
    }
}
