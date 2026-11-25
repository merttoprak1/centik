import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

struct ShelfToast: Equatable {
    let id = UUID()
    let icon: String
    let message: String
}

@MainActor
final class ShelfChromeModel: ObservableObject {
    @Published var isDropTargeted = false
    @Published var isExpanded = false
    @Published var burstToken = 0
    @Published var openToken = 0
    @Published var landingID: UUID?
    @Published var hoveredItemID: UUID?
    @Published var toast: ShelfToast?
    @Published var hasNotch = true
    @Published var notchHeight: CGFloat = 32
    var onContentFrame: ((CGRect) -> Void)?
    var onInternalDragBegan: (() -> Void)?
    var onInternalDragEnded: (([UUID], NSDragOperation) -> Void)?
    var onCelebrate: ((UUID?) -> Void)?
    var onToast: ((String, String) -> Void)?
}

/// Opens and closes the DynamicNotchKit panel, and keeps the collapsed sensor in the notch.
/// All calls are on the main thread: AppKit drag callbacks, the menu, and the pointer timer.
@MainActor
final class ShelfController {
    let store: ShelfStore
    let model = ShelfChromeModel()

    private var notch: DynamicNotch<ShelfChromeView, EmptyView, EmptyView>?
    private var sensor: SensorPanel?
    private let promises = PromiseImporter()
    private let hotKey = GlobalHotKey()

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
    private var localKey: Any?
    private var armedURLs: [URL] = []
    private var lastConsumedDragChangeCount = NSPasteboard(name: .drag).changeCount
    private var recentDrop: (paths: [String], at: Date)?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var screenFollowTimer: Timer?
    private var lastSensorScreenNumber: UInt32?

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
        model.onInternalDragEnded = { [weak self] ids, operation in
            guard let self else { return }
            self.internalDrag = false
            self.store.handleDragCompleted(ids: ids, operation: operation)
            if self.phase == .expanded {
                self.scheduleCollapse()
            }
        }
        model.onCelebrate = { [weak self] id in
            self?.celebrate(newID: id)
        }
        model.onToast = { [weak self] icon, message in
            self?.showToast(icon: icon, message: message)
        }
        notch = DynamicNotch(
            hoverBehavior: [.increaseShadow],
            style: .auto
        ) {
            ShelfChromeView(store: self.store, model: self.model)
        }
        applyMotion()
        installMonitors()
        bindPreferences()
        applyHotKey()
        layoutSensor(orderFront: true)
    }

    private func bindPreferences() {
        let prefs = AppPreferences.shared
        prefs.$hotKey
            .combineLatest(prefs.$hotKeyEnabled)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.applyHotKey()
            }
            .store(in: &cancellables)

        prefs.$displayMode
            .combineLatest(prefs.$showPillOnNonNotch)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.updateScreenFollowTimer()
                self.layoutSensor(orderFront: self.phase != .expanded)
            }
            .store(in: &cancellables)

        updateScreenFollowTimer()
    }

    private func applyHotKey() {
        let prefs = AppPreferences.shared
        if prefs.hotKeyEnabled {
            hotKey.register(combo: prefs.hotKey) { [weak self] in
                self?.togglePinned()
            }
        } else {
            hotKey.unregister()
        }
    }

    private func updateScreenFollowTimer() {
        screenFollowTimer?.invalidate()
        screenFollowTimer = nil
        guard AppPreferences.shared.displayMode == .activeScreen else { return }
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .collapsed else { return }
                guard let screen = NotchScreen.target() else { return }
                let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
                let screenNum = (screen.deviceDescription[key] as? NSNumber)?.uint32Value
                if screenNum != self.lastSensorScreenNumber {
                    self.layoutSensor(orderFront: true)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        screenFollowTimer = timer
    }

    func togglePinned() {
        if phase == .expanded {
            collapse()
        } else {
            presentPinned()
        }
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
        guard externalDrag, !internalDrag else { return false }
        return DropPayload.hasFileDrag(NSPasteboard(name: .drag))
    }

    func draggingEntered() -> NSDragOperation {
        guard !internalDrag else { return [] }
        externalDrag = true
        model.isDropTargeted = true
        expand()
        return AppPreferences.shared.fileMode == .move ? .move : .copy
    }

    func draggingUpdated() -> NSDragOperation {
        guard !internalDrag else { return [] }
        return AppPreferences.shared.fileMode == .move ? .move : .copy
    }

    func draggingExited() {
        model.isDropTargeted = false
    }

    func performDrop(_ pasteboard: NSPasteboard) -> Bool {
        lastConsumedDragChangeCount = NSPasteboard(name: .drag).changeCount
        let urls = DropPayload.fileURLs(from: pasteboard)
        if !urls.isEmpty {
            accept(urls: urls)
            return true
        }
        if let image = DropPayload.image(from: pasteboard) {
            Task { @MainActor in
                if let id = await self.store.addImageData(image.0, fileExtension: image.1) {
                    self.celebrate(newID: id)
                }
            }
            return true
        }
        if promises.receive(from: pasteboard, completion: { [weak self] urls, tempDirectory in
            self?.accept(urls: urls, cleanupDirectory: tempDirectory)
        }) {
            return true
        }
        if let web = DropPayload.webURL(from: pasteboard) {
            Task { @MainActor in
                if let id = await self.store.addWebURL(web.url, title: web.title) {
                    self.celebrate(newID: id)
                }
            }
            return true
        }
        if let text = DropPayload.text(from: pasteboard) {
            Task { @MainActor in
                if let id = await self.store.addText(text) {
                    self.celebrate(newID: id)
                }
            }
            return true
        }
        return false
    }

    func draggingEnded() {
        lastConsumedDragChangeCount = NSPasteboard(name: .drag).changeCount
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
        model.isExpanded = false
        model.openToken += 1
        applyMotion()
        Task { @MainActor in
            async let shown: Void = notch.expand(on: screen)
            for _ in 0..<30 {
                if self.notch?.windowController?.window != nil {
                    self.attachPassThrough()
                    break
                }
                try? await Task.sleep(for: .milliseconds(8))
            }
            self.model.isExpanded = true
            await shown
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
        model.isExpanded = false
        model.hoveredItemID = nil
        model.toast = nil
        store.clearSelection()
        Task { @MainActor in
            await notch.hide()
            self.layoutSensor(orderFront: true)
        }
    }

    private func accept(urls: [URL], cleanupDirectory: URL? = nil) {
        let paths = urls.map { $0.standardizedFileURL.path }
        if let recentDrop, recentDrop.paths == paths, Date().timeIntervalSince(recentDrop.at) < 1 {
            if let cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanupDirectory)
            }
            return
        }
        recentDrop = (paths, Date())

        let volumes = urls.filter { (try? $0.resourceValues(forKeys: [.isVolumeKey]).isVolume) == true }
        let acceptable = urls.filter { (try? $0.resourceValues(forKeys: [.isVolumeKey]).isVolume) != true }

        if !volumes.isEmpty {
            model.isDropTargeted = false
            showToast(
                icon: "externaldrive.badge.xmark",
                message: volumes.count == 1 ? "Can't move a disk" : "Can't move disks"
            )
        }

        guard !acceptable.isEmpty else {
            if let cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanupDirectory)
            }
            return
        }

        Task { @MainActor in
            let ids = await self.store.add(urls: acceptable)
            if let cleanupDirectory {
                try? FileManager.default.removeItem(at: cleanupDirectory)
            }
            guard let first = ids.first else { return }
            self.celebrate(newID: first, count: ids.count)
        }
    }

    private func celebrate(newID: UUID?, count: Int = 1) {
        model.burstToken += 1
        model.landingID = newID
        model.isDropTargeted = false
        Haptics.land()
        if count > 1 {
            showToast(icon: "checkmark.circle.fill", message: "Added \(count) items")
        }
        let token = newID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            if self.model.landingID == token {
                self.model.landingID = nil
            }
        }
    }

    private func showToast(icon: String, message: String) {
        let toast = ShelfToast(icon: icon, message: message)
        model.toast = toast
        Haptics.tick()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            if self.model.toast?.id == toast.id {
                withAnimation(.easeOut(duration: 0.22)) {
                    self.model.toast = nil
                }
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
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)) - 1)
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
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        lastSensorScreenNumber = (screen.deviceDescription[key] as? NSNumber)?.uint32Value
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
        panel.updateChrome(hasNotch: notched, showPill: AppPreferences.shared.showPillOnNonNotch)
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
            MainActor.assumeIsolated { self?.collapseIfIdle() }
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
        if pointerInside || externalDrag || internalDrag || menuTracking || model.isDropTargeted || QuickLookController.shared.isVisible { return }
        if shelfContains(NSEvent.mouseLocation) {
            pointerInside = true
            return
        }
        collapse()
    }

    private func startWatch() {
        guard watch == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
    }

    private func stopWatch() {
        watch?.invalidate()
        watch = nil
    }

    private func handlePointerDrag(type: NSEvent.EventType, location: NSPoint, isLocal: Bool) {
        if type == .leftMouseUp {
            var urls = armedURLs
            armedURLs = []
            let wasExternal = externalDrag
            let wasInternal = internalDrag
            let dragPB = NSPasteboard(name: .drag)
            let isFreshDrag = dragPB.changeCount != lastConsumedDragChangeCount
            let overTarget = shelfContains(location) || (sensor.map { NotchScreen.catchRect(around: $0.frame).contains(location) } ?? false)
            if urls.isEmpty, wasExternal, isFreshDrag, overTarget {
                urls = DropPayload.fileURLs(from: dragPB)
            }
            if wasExternal {
                lastConsumedDragChangeCount = dragPB.changeCount
            }
            externalDrag = false
            internalDrag = false
            model.isDropTargeted = false
            if wasExternal, isFreshDrag, overTarget, !urls.isEmpty {
                accept(urls: urls)
                return
            }
            if (wasExternal || wasInternal), phase == .expanded {
                if wasExternal {
                    fadeSensorOut()
                }
                scheduleCollapse()
            }
            return
        }
        guard !isLocal, !internalDrag else { return }
        let dragPB = NSPasteboard(name: .drag)
        guard dragPB.changeCount != lastConsumedDragChangeCount,
              DropPayload.hasFileDrag(dragPB) else { return }
        let nearSensor = sensor.map { NotchScreen.catchRect(around: $0.frame).contains(location) } ?? false
        if nearSensor || shelfContains(location) {
            externalDrag = true
            let urls = DropPayload.fileURLs(from: dragPB)
            if !urls.isEmpty { armedURLs = urls }
            expand()
        } else {
            armedURLs = []
        }
    }

    private func screensChanged() {
        let showSensor = phase != .expanded
        layoutSensor(orderFront: showSensor)
        guard phase == .expanded, NotchScreen.target() != nil, let notch else { return }
        Task { @MainActor in
            await notch.hide()
            self.phase = .collapsed
            self.opening = false
            self.hitGate = nil
            self.expand()
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 49 where flags.isEmpty: // Space -> Quick Look
            let targets: [ShelfItem]
            if !store.selectedValidItems.isEmpty {
                targets = store.selectedValidItems
            } else if let hovered = model.hoveredItemID,
                      let item = store.items.first(where: { $0.id == hovered && !$0.isMissing }) {
                targets = [item]
            } else if let first = store.validItems.first {
                targets = [first]
            } else {
                return false
            }
            store.quickLook(targets)
            return true
        case 53: // Escape
            if QuickLookController.shared.isVisible {
                QuickLookController.shared.close()
                return true
            }
            if !store.selectedIDs.isEmpty {
                store.clearSelection()
                return true
            }
            collapse()
            return true
        case 0 where flags == .command: // Cmd+A
            store.selectAll()
            return true
        case 8 where flags == .command: // Cmd+C
            if !store.selectedValidItems.isEmpty {
                let count = store.selectedValidItems.count
                store.copyFiles(store.selectedValidItems)
                showToast(icon: "doc.on.doc.fill", message: count == 1 ? "Copied file" : "Copied \(count) files")
                return true
            } else if let hovered = model.hoveredItemID,
                      let item = store.items.first(where: { $0.id == hovered && !$0.isMissing }) {
                store.copyFiles([item])
                showToast(icon: "doc.on.doc.fill", message: "Copied file")
                return true
            }
            return false
        case 51 where flags.isEmpty, 117 where flags.isEmpty: // Backspace / Delete
            if !store.selectedIDs.isEmpty {
                store.remove(ids: Array(store.selectedIDs))
                return true
            }
            return false
        default:
            return false
        }
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        globalDrag = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePointerDrag(type: type, location: location, isLocal: false)
            }
        }
        localDrag = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handlePointerDrag(type: type, location: location, isLocal: true)
            }
            return event
        }
        localKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.phase == .expanded else { return event }
            return self.handleKeyDown(event) ? nil : event
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
    func receive(from pasteboard: NSPasteboard, completion: @escaping ([URL], URL?) -> Void) -> Bool {
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
            completion([], nil)
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
            completion(urls, destination)
            self?.receivers.removeAll { candidate in
                found.contains { $0 === candidate }
            }
        }
        return true
    }
}
