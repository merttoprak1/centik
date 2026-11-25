import AppKit
import Carbon
import Foundation

enum DisplayMode: String, CaseIterable, Identifiable {
    case notchOrBuiltIn
    case activeScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notchOrBuiltIn: return "Notch / Built-in Display"
        case .activeScreen: return "Active Display (Follows Cursor)"
        }
    }
}

enum ShelfFileMode: String, CaseIterable, Identifiable {
    case move
    case bookmark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .move: return "Move to Shelf"
        case .bookmark: return "Keep in Place (Bookmark)"
        }
    }

    var subtitle: String {
        switch self {
        case .move: return "Files move off Desktop into Centik and return if you press × or Clear."
        case .bookmark: return "Original files stay where they are; Centik only holds references."
        }
    }
}

struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey))

    var displayString: String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
        parts += Self.keyName(for: keyCode)
        return parts
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func keyName(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        default: return "Key\(code)"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    @Published var showPillOnNonNotch: Bool {
        didSet { UserDefaults.standard.set(showPillOnNonNotch, forKey: Keys.showPillOnNonNotch) }
    }

    @Published var fileMode: ShelfFileMode {
        didSet { UserDefaults.standard.set(fileMode.rawValue, forKey: Keys.fileMode) }
    }

    @Published var hotKeyEnabled: Bool {
        didSet { UserDefaults.standard.set(hotKeyEnabled, forKey: Keys.hotKeyEnabled) }
    }

    @Published var hotKey: HotKeyCombo {
        didSet {
            UserDefaults.standard.set(Int(hotKey.keyCode), forKey: Keys.hotKeyCode)
            UserDefaults.standard.set(Int(hotKey.modifiers), forKey: Keys.hotKeyModifiers)
        }
    }

    private enum Keys {
        static let displayMode = "centik.displayMode"
        static let showPillOnNonNotch = "centik.showPillOnNonNotch"
        static let fileMode = "centik.fileMode"
        static let hotKeyEnabled = "centik.hotKeyEnabled"
        static let hotKeyCode = "centik.hotKeyCode"
        static let hotKeyModifiers = "centik.hotKeyModifiers"
    }

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Keys.displayMode), let mode = DisplayMode(rawValue: raw) {
            self.displayMode = mode
        } else {
            self.displayMode = .notchOrBuiltIn
        }

        if defaults.object(forKey: Keys.showPillOnNonNotch) != nil {
            self.showPillOnNonNotch = defaults.bool(forKey: Keys.showPillOnNonNotch)
        } else {
            self.showPillOnNonNotch = true
        }

        if let raw = defaults.string(forKey: Keys.fileMode), let mode = ShelfFileMode(rawValue: raw) {
            self.fileMode = mode
        } else {
            self.fileMode = .move
        }

        if defaults.object(forKey: Keys.hotKeyEnabled) != nil {
            self.hotKeyEnabled = defaults.bool(forKey: Keys.hotKeyEnabled)
        } else {
            self.hotKeyEnabled = true
        }

        if defaults.object(forKey: Keys.hotKeyCode) != nil && defaults.object(forKey: Keys.hotKeyModifiers) != nil {
            self.hotKey = HotKeyCombo(
                keyCode: UInt32(defaults.integer(forKey: Keys.hotKeyCode)),
                modifiers: UInt32(defaults.integer(forKey: Keys.hotKeyModifiers))
            )
        } else {
            self.hotKey = .defaultCombo
        }
    }
}
