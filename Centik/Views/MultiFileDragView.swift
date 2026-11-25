import AppKit
import SwiftUI

/// Native AppKit drag source supporting single and multi-file drags,
/// click/double-click forwarding, and an exact drag-completion callback.
struct MultiFileDragOverlay: NSViewRepresentable {
    var urlsProvider: () -> [(id: UUID, url: URL)]
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (([UUID], NSDragOperation) -> Void)?

    func makeNSView(context: Context) -> MultiFileDragNSView {
        let view = MultiFileDragNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: MultiFileDragNSView, context: Context) {
        view.urlsProvider = urlsProvider
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
    }
}

final class MultiFileDragNSView: NSView, NSDraggingSource {
    var urlsProvider: (() -> [(id: UUID, url: URL)])?
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (([UUID], NSDragOperation) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private var activeDraggedIDs: [UUID] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let startEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - startEvent.locationInWindow.x
        let dy = event.locationInWindow.y - startEvent.locationInWindow.y
        guard hypot(dx, dy) >= 4 else { return }

        let entries = urlsProvider?() ?? []
        guard !entries.isEmpty else { return }

        didStartDrag = true
        activeDraggedIDs = entries.map(\.id)
        onDragBegan?()

        let draggingItems: [NSDraggingItem] = entries.enumerated().map { index, entry in
            let item = NSDraggingItem(pasteboardWriter: entry.url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
            let iconSize: CGFloat = 52
            icon.size = NSSize(width: iconSize, height: iconSize)
            let offset = CGFloat(min(index, 4)) * 5
            let origin = NSPoint(
                x: bounds.midX - iconSize / 2 + offset,
                y: bounds.midY - iconSize / 2 - offset
            )
            item.setDraggingFrame(NSRect(origin: origin, size: NSSize(width: iconSize, height: iconSize)), contents: icon)
            return item
        }

        beginDraggingSession(with: draggingItems, event: startEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            didStartDrag = false
        }
        guard !didStartDrag else { return }
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onClick?(event.modifierFlags)
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            return [.move, .copy]
        case .withinApplication:
            return .copy
        @unknown default:
            return .copy
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let ids = activeDraggedIDs
        activeDraggedIDs = []
        onDragEnded?(ids, operation)
    }
}
