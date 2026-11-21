import AppKit

enum MenuBarIcon {
    /// Template image so the menu bar tint follows the system appearance.
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            let notch = NSBezierPath(bottomRoundedRect: NSRect(x: 2.5, y: 9.2, width: 13, height: 7.2), radius: 3.1)
            notch.fill()
            for index in 0..<3 {
                let tile = NSRect(x: 3.15 + CGFloat(index) * 4.25, y: 3.15, width: 3.35, height: 3.7)
                NSBezierPath(roundedRect: tile, xRadius: 0.8, yRadius: 0.8).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Centik"
        return image
    }()
}

private extension NSBezierPath {
    /// AppKit y-up. Top edge is square so the mark sits against the menu bar.
    convenience init(bottomRoundedRect rect: NSRect, radius: CGFloat) {
        self.init()
        let r = min(radius, rect.width / 2, rect.height)
        move(to: NSPoint(x: rect.minX, y: rect.maxY))
        line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        line(to: NSPoint(x: rect.maxX, y: rect.minY + r))
        appendArc(from: NSPoint(x: rect.maxX, y: rect.minY), to: NSPoint(x: rect.maxX - r, y: rect.minY), radius: r)
        line(to: NSPoint(x: rect.minX + r, y: rect.minY))
        appendArc(from: NSPoint(x: rect.minX, y: rect.minY), to: NSPoint(x: rect.minX, y: rect.minY + r), radius: r)
        close()
    }
}
