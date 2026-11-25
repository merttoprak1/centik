import AppKit

/// Trackpad haptics. Pow's haptic effects are iOS-only, so the Mac shelf
/// uses AppKit's feedback performer directly.
enum Haptics {
    static func align() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    static func land() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
