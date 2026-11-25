import AppKit

/// Where the shelf anchors. DynamicNotchKit keeps its own notch math internal,
/// so the collapsed hit target measures the hardware notch with public AppKit APIs.
enum NotchScreen {
    @MainActor
    static func target(mode: DisplayMode? = nil) -> NSScreen? {
        let effectiveMode = mode ?? AppPreferences.shared.displayMode
        let screens = NSScreen.screens
        if effectiveMode == .activeScreen {
            let mouse = NSEvent.mouseLocation
            if let underCursor = screens.first(where: { $0.frame.contains(mouse) }) {
                return underCursor
            }
        }
        if let notched = screens.first(where: { notchFrame(on: $0) != nil }) {
            return notched
        }
        if let builtIn = screens.first(where: isBuiltIn) {
            return builtIn
        }
        return NSScreen.main ?? screens.first
    }

    static func hasNotch(_ screen: NSScreen) -> Bool {
        notchFrame(on: screen) != nil
    }

    /// Hardware notch in global AppKit coordinates, or nil when the display has no camera housing.
    static func notchFrame(on screen: NSScreen) -> CGRect? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        let width = right.minX - left.maxX
        let height = max(screen.safeAreaInsets.top, left.height, right.height, 24)
        guard width > 40, width < 520, height < 80 else { return nil }

        let looksGlobal = left.maxX >= screen.frame.minX - 2 && right.minX <= screen.frame.maxX + 2
        let originX = looksGlobal ? left.maxX : screen.frame.minX + left.maxX
        return CGRect(x: originX, y: screen.frame.maxY - height, width: width, height: height)
    }

    /// Collapsed hit target. On a notched display this matches the notch.
    /// Otherwise it is a small fake-notch pill, flush with the top of the screen.
    static func collapsedFrame(on screen: NSScreen) -> CGRect {
        if let notch = notchFrame(on: screen) {
            return notch
        }
        let width: CGFloat = 168
        let peek: CGFloat = 11
        let height = max(menuBarHeight(on: screen), 24) + peek
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    static func catchRect(around frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX - 36,
            y: frame.minY - 64,
            width: frame.width + 72,
            height: frame.height + 64
        )
    }

    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let height = screen.frame.maxY - screen.visibleFrame.maxY
        return height > 1 ? height : 0
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}
