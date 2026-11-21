import AppKit
import SwiftUI

/// Always-on hit target the size of the notch (or a small pill when there isn't one).
/// DynamicNotchKit removes its window when hidden, so this is what hover and an approaching drag can find.
final class SensorPanel: NSPanel {
    private let root = SensorRoot()

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        root.frame = NSRect(origin: .zero, size: frame.size)
        root.autoresizingMask = [.width, .height]
        contentView = root
    }

    required init?(coder: NSCoder) {
        fatalError("SensorPanel is created in code")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var controller: ShelfController? {
        get { root.controller }
        set { root.controller = newValue }
    }

    func updateChrome(hasNotch: Bool) {
        root.setHasNotch(hasNotch)
    }
}

final class SensorRoot: NSView {
    weak var controller: ShelfController?
    private var hosting: SensorHost?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(ShelfDragTypes.all)
    }

    required init?(coder: NSCoder) {
        fatalError("SensorRoot is created in code")
    }

    func setHasNotch(_ hasNotch: Bool) {
        if let hosting {
            hosting.rootView = SensorChrome(hasNotch: hasNotch)
            return
        }
        let host = SensorHost(rootView: SensorChrome(hasNotch: hasNotch))
        if #available(macOS 13.3, *) {
            host.safeAreaRegions = []
        }
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        hosting = host
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        controller?.pointerEnteredSensor()
    }

    override func mouseExited(with event: NSEvent) {
        controller?.pointerExitedSensor()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.draggingEntered() ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.draggingUpdated() ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.draggingExited()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.performDrop(sender.draggingPasteboard) ?? false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        controller?.draggingEnded()
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { false }
}

final class SensorHost: NSHostingView<SensorChrome> {
    override var safeAreaInsets: NSEdgeInsets { .init() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SensorChrome: View {
    var hasNotch: Bool

    var body: some View {
        let radius: CGFloat = hasNotch ? 16 : 12
        let shape = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: radius,
                bottomTrailing: radius,
                topTrailing: 0
            ),
            style: .continuous
        )
        shape
            .fill(Color.black)
            .overlay {
                if !hasNotch {
                    shape
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.7)
                        .padding(0.4)
                }
            }
            .ignoresSafeArea()
    }
}
