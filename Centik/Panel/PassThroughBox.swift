import AppKit
import UniformTypeIdentifiers

/// DynamicNotchKit's panel is much larger than the visible notch so the shape
/// can spring open and cast a shadow. This wrapper keeps clicks and drops on
/// the shelf itself and lets the rest of the screen through.
final class PassThroughBox: NSView {
    weak var controller: ShelfController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(ShelfDragTypes.all)
    }

    required init?(coder: NSCoder) {
        fatalError("PassThroughBox is created in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let inWindow = convert(local, to: nil)
        let onScreen = window.convertToScreen(NSRect(origin: inWindow, size: .zero)).origin
        guard controller?.shelfContains(onScreen) == true else { return nil }
        if controller?.wantsExclusiveDrop == true { return self }
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
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

enum ShelfDragTypes {
    static var all: [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = [
            .fileURL,
            .png,
            .tiff,
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes())
        return types
    }
}
