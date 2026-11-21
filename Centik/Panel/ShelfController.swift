import AppKit
import DynamicNotchKit
import SwiftUI

final class ShelfChromeModel: ObservableObject {
    @Published var isDropTargeted = false
    @Published var dropPulse = 0
    @Published var burstToken = 0
    @Published var landingID: UUID?
    @Published var hasNotch = true
    @Published var notchHeight: CGFloat = 32
    var onContentFrame: ((CGRect) -> Void)?
    var onInternalDragBegan: (() -> Void)?
}

/// Opens and closes the DynamicNotchKit panel, and keeps the collapsed sensor in the notch.
/// All calls are on the main thread: AppKit drag callbacks, the menu, and the pointer timer.
final class ShelfController {
    let store: ShelfStore
    let model = ShelfChromeModel()

    private var notch: DynamicNotch<ShelfChromeView, EmptyView, EmptyView>?
    private var sensor: SensorPanel?
    private let promises = PromiseImporter()

    private var phase: Phase = .collapsed
    private var opening = false
    private var pinned = false
    private var visitedWhilePinned = false
    private var pointerInside = false
    private var externalDrag = false
    private var internalDrag = false
    private var menuTracking = false
    private var hitGate: CGRect?
    private var collapseWork: DispatchWorkItem?
    private var watch: Timer?
    private var globalDrag: Any?
    private var localDrag: Any?
    private var observers: [NSObjectProtocol] = []

    private enum Phase {
        case collapsed
        case expanded
    }

    init(store: ShelfStore) {
        self.store = store
    }

    func start() {
        model.onContentFrame = { [weak self] rect in
            self?.noteContentFrame(rect)
        }
        model.onInternalDragBegan = { [weak self] in
            self?.internalDrag = true
        }
        notch = DynamicNotch(
            hoverBehavior: [.increaseShadow],
            style: .auto
        ) {
            ShelfChromeView(store: store, model: model)
        }
        applyMotion()
        installMonitors()
        layoutSensor(orderFront: true)
    }

    func presentPinned() {
        pinned = true
        visitedWhilePinned = shelfContains(NSEvent.mouseLocation)
        expand()
    }

    func pointerEnteredSensor() {
        pointerInside = true
        if pinned { visitedWhilePinned = true }
        cancelCollapse()
        Haptics.align()
        expand()
    }

    func pointerExitedSensor() {
        if shelfContains(NSEvent.mouseLocation) {
            pointerInside = true
            return
        }
        pointerInside = false
        scheduleCollapse()
    }

    func shelfContains(_ screenPoint: NSPoint) -> Bool {
        if let hitGate, hitGate.insetBy(dx: -6, dy: -8).contains(screenPoint) {
            return true
        }
        if let sensor, sensor.isVisible, sensor.alphaValue > 0.05, sensor.frame.contains(screenPoint) {
            return true
        }
        if phase == .expanded, hitGate == nil, let screen = NotchScreen.target() {
            let band = CGRect(
                x: screen.frame.midX - 340,
                y: screen.frame.maxY - 280,
                width: 680,
                height: 280
            )
            return band.contains(screenPoint)
        }
        return false
    }

    var wantsExclusiveDrop: Bool {
        guard !internalDrag else { return false }
        return DropPayload.hasFileDrag(NSPasteboard(name: .drag))
    }

    func draggingEntered() -> NSDragOperation {
        guard !internalDrag else { return [] }
        externalDrag = true
        model.isDropTargeted = true
        expand()
        return .copy
    }

    func draggingUpdated() -> NSDragOperation {
        internalDrag ? [] : .copy
    }

    func draggingExited() {
        model.isDropTargeted = false
    }

    func performDrop(_ pasteboard: NSPasteboard) -> Bool {
        let urls = DropPayload.fileURLs(from: pasteboard)
        if !urls.isEmpty {
            accept(urls: urls)
            return true
        }
        if let image = DropPayload.image(from: pasteboard),
           let id = store.addImageData(image.0, fileExtension: image.1) {
            celebrate(newID: id)
            return true
        }
        return promises.receive(from: pasteboard) { [weak self] urls in
            self?.accept(urls: urls)
        }
    }

    func draggingEnded() {
        model.isDropTargeted = false
        externalDrag = false
        if phase == .expanded {
            fadeSensorOut()
            scheduleCollapse()
        }
    }

    private func expand() {
        guard let screen = NotchScreen.target(), let notch else { return }
        if phase == .expanded || opening {
            attachPassThrough()
            return
        }
        opening = true
        phase = .expanded
        applyMotion()
        Task { @MainActor in
            await notch.expand(on: screen)
            self.attachPassThrough()
            self.opening = false
            self.startWatch()
            self.store.refreshPresence()
            if !self.externalDrag {
                self.fadeSensorOut()
            }
            if !self.shelfContains(NSEvent.mouseLocation), !self.pinned, !self.externalDrag, !self.internalDrag {
                self.scheduleCollapse()
            }
        }
    }

    private func collapse() {
        guard phase == .expanded, !opening, let notch else { return }
        phase = .collapsed
        stopWatch()
        cancelCollapse()
        pinned = false
        visitedWhilePinned = false
        model.isDropTargeted = false
        Task { @MainActor in
            await notch.hide()
            self.layoutSensor(orderFront: true)
        }
    }

    private func accept(urls: [URL]) {
        let ids = store.add(urls: urls)
        guard let first = ids.first else { return }
        celebrate(newID: first)
    }

    private func celebrate(newID: UUID?) {
        model.dropPulse += 1
        model.burstToken += 1
        model.landingID = newID
        model.isDropTargeted = false
        Haptics.land()
        let token = newID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            if self.model.landingID == token {
                self.model.landingID = nil
            }
        }
    }

    private func noteContentFrame(_ rect: CGRect) {
        guard rect.width > 24, rect.height > 16 else { return }
        var gate = rect.insetBy(dx: -42, dy: -28)
        gate.size.height += model.notchHeight + 16
        if let hitGate, abs(hitGate.minX - gate.minX) < 0.5,
           abs(hitGate.minY - gate.minY) < 0.5,
           abs(hitGate.width - gate.width) < 0.5,
           abs(hitGate.height - gate.height) < 0.5 {
            return
        }
        hitGate = gate
    }

    private func applyMotion() {
        guard let notch else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            notch.transitionConfiguration = DynamicNotchTransitionConfiguration(
                openingAnimation: .easeOut(duration: 0.16),
                closingAnimation: .easeIn(duration: 0.12),
                skipIntermediateHides: true
            )
        } else {
            notch.transitionConfiguration = DynamicNotchTransitionConfiguration(
                openingAnimation: .spring(response: 0.46, dampingFraction: 0.76),
                closingAnimation: .spring(response: 0.32, dampingFraction: 0.9),
                skipIntermediateHides: true
            )
        }
    }

    private func attachPassThrough() {
        guard let window = notch?.windowController?.window else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle])
        window.isExcludedFromWindowsMenu = true
        window.hasShadow = false
        if let box = window.contentView as? PassThroughBox {
            box.controller = self
            return
        }
        guard let existing = window.contentView else { return }
        let box = PassThroughBox(frame: existing.bounds)
        box.controller = self
        existing.translatesAutoresizingMaskIntoConstraints = true
        existing.frame = box.bounds
        existing.autoresizingMask = [.width, .height]
        box.autoresizingMask = [.width, .height]
        box.addSubview(existing)
        window.contentView = box
    }

    private func layoutSensor(orderFront: Bool) {
        guard let screen = NotchScreen.target() else {
            sensor?.orderOut(nil)
            return
        }
        let frame = NotchScreen.collapsedFrame(on: screen)
        let notched = NotchScreen.hasNotch(screen)
        model.hasNotch = notched
        model.notchHeight = notched ? frame.height : max(NotchScreen.menuBarHeight(on: screen), 24)
        let panel: SensorPanel
        if let sensor {
            panel = sensor
            panel.setFrame(frame, display: true, animate: false)
        } else {
            panel = SensorPanel(frame: frame)
            panel.controller = self
            sensor = panel
        }
        panel.updateChrome(hasNotch: notched)
        panel.alphaValue = 1
        if orderFront {
            panel.orderFrontRegardless()
        }
    }

    private func fadeSensorOut() {
        guard let sensor, sensor.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            sensor.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                if self.phase == .expanded {
                    sensor.orderOut(nil)
                }
                sensor.alphaValue = 1
            }
        }
    }

    private func evaluatePointer() {
        let inside = shelfContains(NSEvent.mouseLocation)
        if inside {
            if !pointerInside, phase == .expanded {
                Haptics.align()
            }
            pointerInside = true
            if pinned { visitedWhilePinned = true }
            cancelCollapse()
        } else if pointerInside {
            pointerInside = false
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        guard phase == .expanded, !opening else { return }
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.collapseIfIdle()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func collapseIfIdle() {
        guard phase == .expanded, !opening else { return }
        if pinned, !visitedWhilePinned { return }
        if pointerInside || externalDrag || internalDrag || menuTracking || model.isDropTargeted { return }
        if shelfContains(NSEvent.mouseLocation) {
            pointerInside = true
            return
        }
        collapse()
    }

    private func startWatch() {
        guard watch == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.evaluatePointer()
        }
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
    }

    private func stopWatch() {
        watch?.invalidate()
        watch = nil
    }

    private func handlePointerDrag(type: NSEvent.EventType, location: NSPoint) {
        if type == .leftMouseUp {
            let wasDragging = externalDrag || internalDrag
            externalDrag = false
            internalDrag = false
            if wasDragging, phase == .expanded {
                fadeSensorOut()
                scheduleCollapse()
            }
            return
        }
        guard !internalDrag, DropPayload.hasFileDrag(NSPasteboard(name: .drag)) else { return }
        let nearSensor = sensor.map { NotchScreen.catchRect(around: $0.frame).contains(location) } ?? false
        if nearSensor || shelfContains(location) {
            externalDrag = true
            expand()
        }
    }

    private func screensChanged() {
        let showSensor = phase != .expanded
        layoutSensor(orderFront: showSensor)
        guard phase == .expanded, let screen = NotchScreen.target(), let notch else { return }
        Task { @MainActor in
            await notch.hide()
            self.phase = .collapsed
            self.opening = false
            self.hitGate = nil
            self.expand()
        }
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        globalDrag = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePointerDrag(type: type, location: location)
            }
        }
        localDrag = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePointerDrag(type: type, location: location)
            }
            return event
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.menuTracking = true }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.menuTracking = false
                self?.scheduleCollapse()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        })
    }
}

/// Keeps file-promise receivers alive until the source app has written the files.
final class PromiseImporter: NSObject {
    private var receivers: [NSFilePromiseReceiver] = []
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    @discardableResult
    func receive(from pasteboard: NSPasteboard, completion: @escaping ([URL]) -> Void) -> Bool {
        guard let found = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
              !found.isEmpty else {
            return false
        }
        receivers.append(contentsOf: found)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("CentikDrop-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            completion([])
            return true
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for receiver in found {
            group.enter()
            receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: queue) { url, error in
                if error == nil {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            completion(urls)
            self?.receivers.removeAll { candidate in
                found.contains { $0 === candidate }
            }
        }
        return true
    }
}
