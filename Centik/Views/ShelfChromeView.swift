import AppKit
import Pow
import SwiftUI

struct ShelfChromeView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var model: ShelfChromeModel
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragAllHovered = false
    @State private var zipHovered = false
    @State private var clearHovered = false
    @State private var scrollIndex = 0

    private var width: CGFloat {
        ShelfLayout.width(for: store.items.count)
    }

    private var itemTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .movingParts.boing(edge: .top).combined(with: .opacity),
            removal: .movingParts.poof
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ZStack {
                if store.items.isEmpty {
                    emptyState
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    itemRow
                        .scaleEffect(model.isDropTargeted && !reduceMotion ? 0.972 : 1, anchor: .center)
                        .opacity(model.isDropTargeted ? 0.84 : 1)
                        .transition(.opacity)
                }
            }
            .frame(height: store.items.isEmpty ? 80 : 114, alignment: .top)
        }
        .frame(width: width)
        .padding(.bottom, 2)
        .scaleEffect(model.isDropTargeted && !reduceMotion ? 1.018 : 1, anchor: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: model.isDropTargeted)
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.74), value: store.items.map(\.id))
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: model.toast?.id)
        .overlay {
            DropBurstView(token: model.burstToken)
                .frame(width: min(width, 240), height: 96)
                .opacity(model.burstToken == 0 ? 0 : 1)
        }
        .background {
            WindowFrameProbe { rect in
                model.onContentFrame?(rect)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Centik shelf")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .leading) {
                if let toast = model.toast {
                    HStack(spacing: 4.5) {
                        Image(systemName: toast.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                        Text(toast.message)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.5))
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85, anchor: .leading).combined(with: .opacity),
                        removal: .opacity
                    ))
                } else {
                    HStack(spacing: 5) {
                        if model.isDropTargeted {
                            Circle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 5, height: 5)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(headerTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(model.isDropTargeted ? 0.94 : 0.5))
                            .contentTransition(.numericText())
                    }
                    .transition(.opacity)
                }
            }

            Spacer(minLength: 8)

            if !store.validItems.isEmpty {
                dragAllHandle
                zipButton
            }
            if !store.items.isEmpty {
                Button("Clear") {
                    Haptics.tick()
                    let restored = store.clear()
                    if restored.count == 1, let folder = restored.first?.deletingLastPathComponent().lastPathComponent {
                        model.onToast?("arrow.uturn.backward", "Returned to \(folder)")
                    } else if restored.count > 1 {
                        model.onToast?("arrow.uturn.backward", "Returned \(restored.count) items")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(clearHovered ? 0.92 : 0.52))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.white.opacity(clearHovered ? 0.12 : 0)))
                .onHover { clearHovered = $0 }
                .animation(.easeOut(duration: 0.14), value: clearHovered)
                .help("Return files to their original folders and clear the shelf.")
            }
        }
        .padding(.horizontal, 6)
        .animation(.easeOut(duration: 0.16), value: model.isDropTargeted)
        .animation(.easeOut(duration: 0.16), value: store.selectedIDs.count)
    }

    private var dragAllHandle: some View {
        let targets = store.selectedValidItems.count > 1 ? store.selectedValidItems : store.validItems
        let label = store.selectedValidItems.count > 1 ? "Drag \(targets.count)" : "Drag All"
        return HStack(spacing: 4) {
            Image(systemName: "square.on.square")
                .font(.system(size: 9.5, weight: .semibold))
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .contentTransition(.numericText())
        }
        .foregroundStyle(Color.white.opacity(dragAllHovered ? 0.96 : 0.78))
        .padding(.horizontal, 7.5)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(Color.white.opacity(dragAllHovered ? 0.18 : 0.1)))
        .overlay(Capsule().stroke(Color.white.opacity(dragAllHovered ? 0.28 : 0.15), lineWidth: 0.5))
        .scaleEffect(dragAllHovered && !reduceMotion ? 1.03 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: dragAllHovered)
        .onHover { dragAllHovered = $0 }
        .overlay {
            MultiFileDragOverlay(
                urlsProvider: {
                    let current = store.selectedValidItems.count > 1 ? store.selectedValidItems : store.validItems
                    return current.compactMap { item in
                        guard let url = item.resolvedURL else { return nil }
                        return (item.id, url)
                    }
                },
                onDragBegan: { model.onInternalDragBegan?() },
                onDragEnded: { ids, operation in
                    model.onInternalDragEnded?(ids, operation)
                }
            )
        }
        .help("Drag all items out at once")
    }

    private var zipButton: some View {
        Button {
            let targets = store.selectedValidItems.isEmpty ? store.validItems : store.selectedValidItems
            Task { @MainActor in
                if let id = await store.zipItems(targets) {
                    model.onCelebrate?(id)
                    model.onToast?("doc.zipper", "Zipped \(targets.count == 1 ? "item" : "\(targets.count) items")")
                }
            }
        } label: {
            Group {
                if store.isZipping {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(zipHovered ? 0.95 : 0.6))
                }
            }
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Color.white.opacity(zipHovered ? 0.14 : 0)))
        }
        .buttonStyle(.plain)
        .disabled(store.isZipping)
        .onHover { zipHovered = $0 }
        .animation(.easeOut(duration: 0.14), value: zipHovered)
        .help(store.selectedValidItems.isEmpty ? "Compress all items into a Zip" : "Compress selected items into a Zip")
    }

    private var headerTitle: String {
        if store.selectedIDs.count > 1 { return "\(store.selectedIDs.count) selected" }
        let count = store.items.count
        if count == 0 { return "Shelf" }
        return count == 1 ? "1 item" : "\(count) items"
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: model.isDropTargeted ? "arrow.down.circle.fill" : "tray.and.arrow.down")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.white.opacity(model.isDropTargeted ? 0.96 : 0.72))
                .contentTransition(.symbolEffect(.replace))
                .offset(y: model.isDropTargeted && !reduceMotion ? 2 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: model.isDropTargeted)
                .frame(height: 24)

            Text(model.isDropTargeted ? "Release to keep them here" : "Drop files, links, or text")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(model.isDropTargeted ? 0.95 : 0.86))
                .contentTransition(.opacity)
            Text(prefs.hotKeyEnabled ? "\(prefs.hotKey.displayString) to toggle · Space to Quick Look" : "Space to Quick Look")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var itemRow: some View {
        let visibleSlots = 6
        let maxIndex = max(0, store.items.count - visibleSlots)
        let clampedIndex = min(scrollIndex, maxIndex)
        let canScrollLeft = maxIndex > 0 && clampedIndex > 0
        let canScrollRight = maxIndex > 0 && clampedIndex < maxIndex

        return ScrollViewReader { proxy in
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                            ShelfItemView(store: store, model: model, item: item, index: index)
                                .id(item.id)
                                .transition(itemTransition)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .mask(edgeFade(left: canScrollLeft, right: canScrollRight))

                HStack {
                    if canScrollLeft {
                        ScrollArrowButton(systemName: "chevron.left") {
                            let next = max(0, clampedIndex - 3)
                            scrollIndex = next
                            Haptics.tick()
                            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.82)) {
                                proxy.scrollTo(store.items[next].id, anchor: .leading)
                            }
                        }
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                    Spacer()
                    if canScrollRight {
                        ScrollArrowButton(systemName: "chevron.right") {
                            let next = min(maxIndex, clampedIndex + 3)
                            scrollIndex = next
                            Haptics.tick()
                            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.34, dampingFraction: 0.82)) {
                                proxy.scrollTo(store.items[next].id, anchor: .leading)
                            }
                        }
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 2)
                .offset(y: -14)
                .animation(.easeOut(duration: 0.18), value: canScrollLeft)
                .animation(.easeOut(duration: 0.18), value: canScrollRight)
            }
            .onChange(of: store.items.count) { _, newCount in
                let newMax = max(0, newCount - visibleSlots)
                if scrollIndex > newMax {
                    scrollIndex = newMax
                }
            }
        }
    }

    private func edgeFade(left: Bool, right: Bool) -> some View {
        HStack(spacing: 0) {
            if left {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 22)
            }
            Rectangle()
            if right {
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 22)
            }
        }
    }
}

private struct ScrollArrowButton: View {
    let systemName: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(hovered ? 0.98 : 0.78))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.black.opacity(hovered ? 0.9 : 0.74)))
                .overlay(Circle().stroke(Color.white.opacity(hovered ? 0.36 : 0.2), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                .scaleEffect(hovered ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: hovered)
    }
}

enum ShelfLayout {
    static let maxWidth: CGFloat = 520
    static let minWidth: CGFloat = 300

    static func width(for count: Int) -> CGFloat {
        if count == 0 { return 320 }
        let natural = 12 + CGFloat(count) * 86
        return min(maxWidth, max(minWidth, natural))
    }
}

struct WindowFrameProbe: NSViewRepresentable {
    var onFrame: (CGRect) -> Void

    func makeNSView(context: Context) -> ProbeNSView {
        ProbeNSView(onFrame: onFrame)
    }

    func updateNSView(_ view: ProbeNSView, context: Context) {
        view.onFrame = onFrame
    }
}

final class ProbeNSView: NSView {
    var onFrame: (CGRect) -> Void

    init(onFrame: @escaping (CGRect) -> Void) {
        self.onFrame = onFrame
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("ProbeNSView is created in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard let window, bounds.width > 1, bounds.height > 1 else { return }
        let onScreen = window.convertToScreen(convert(bounds, to: nil))
        onFrame(onScreen)
    }
}
