import AppKit
import Pow
import SwiftUI

struct ShelfChromeView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var model: ShelfChromeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var width: CGFloat {
        ShelfLayout.width(for: store.items.count)
    }

    private var itemTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .movingParts.boing(edge: .top),
            removal: .movingParts.poof
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ZStack {
                if store.items.isEmpty {
                    emptyState
                        .transition(.opacity)
                } else {
                    itemRow
                        .transition(.opacity)
                }
            }
            .frame(height: store.items.isEmpty ? 78 : 112, alignment: .top)
        }
        .frame(width: width)
        .padding(.bottom, 2)
        .scaleEffect(model.isDropTargeted && !reduceMotion ? 1.018 : 1, anchor: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: model.isDropTargeted)
        .animation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.74), value: store.items.map(\.id))
        .changeEffect(
            .pulse(
                shape: RoundedRectangle(cornerRadius: 22, style: .continuous),
                style: Color.white.opacity(0.9),
                drawingMode: .stroke,
                count: 1
            ),
            value: model.dropPulse,
            isEnabled: model.dropPulse > 0 && !reduceMotion
        )
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
        HStack(alignment: .firstTextBaseline) {
            Text(headerTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(model.isDropTargeted ? 0.92 : 0.48))
                .contentTransition(.opacity)
            Spacer(minLength: 8)
            if !store.items.isEmpty {
                Button("Clear") { store.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .help("Take everything off the shelf. Original files stay put.")
            }
        }
        .padding(.horizontal, 6)
        .animation(.easeOut(duration: 0.16), value: model.isDropTargeted)
    }

    private var headerTitle: String {
        if model.isDropTargeted { return "Release to add" }
        let count = store.items.count
        if count == 0 { return "Shelf" }
        return count == 1 ? "1 item" : "\(count) items"
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: model.isDropTargeted ? "arrow.down.circle" : "tray.and.arrow.down")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .symbolEffect(.bounce, value: model.isDropTargeted)
            Text(model.isDropTargeted ? "Release to keep them here" : "Drop files to keep them here")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.86))
            Text("They stay on the shelf until you drag them back")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var itemRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(store.items) { item in
                    ShelfItemView(store: store, model: model, item: item)
                        .transition(itemTransition)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .mask(edgeFade)
    }

    private var edgeFade: some View {
        let fade = width >= ShelfLayout.maxWidth - 1
        return HStack(spacing: 0) {
            if fade {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
            }
            Rectangle()
            if fade {
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
            }
        }
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
