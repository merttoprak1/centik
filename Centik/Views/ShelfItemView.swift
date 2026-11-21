import AppKit
import Pow
import SwiftUI

struct ShelfItemView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var model: ShelfChromeModel
    let item: ShelfItem

    @StateObject private var loader = ThumbnailLoader()
    @State private var hovering = false
    @State private var shineTick = 0
    @State private var landingTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let thumb: CGFloat = 58

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                if hovering {
                    removeButton
                        .offset(x: 5, y: -5)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: 68, height: 64)

            Text(item.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(item.isMissing ? 0.45 : 0.88))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 78, height: 28, alignment: .top)
        }
        .frame(width: 84, alignment: .top)
        .scaleEffect(hovering && !reduceMotion ? 1.045 : 1, anchor: .bottom)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: hovering)
        .changeEffect(.shine(duration: 0.48), value: shineTick, isEnabled: shineTick > 0 && !reduceMotion)
        .changeEffect(.jump(height: 12), value: landingTick, isEnabled: landingTick > 0 && !reduceMotion)
        .onHover { inside in
            hovering = inside
            if inside { shineTick += 1 }
        }
        .onAppear { loader.load(item, side: thumb) }
        .onChange(of: item.resolvedURL) { _, _ in loader.load(item, side: thumb) }
        .onChange(of: item.isMissing) { _, _ in loader.load(item, side: thumb) }
        .onChange(of: model.landingID) { _, id in
            if id == item.id { landingTick += 1 }
        }
        .help(item.tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.isMissing ? "\(item.displayName), missing" : item.displayName)
        .accessibilityHint("Double-click to open. Drag to move the file out of the shelf.")
        .accessibilityAction(named: "Show in Finder") { store.reveal(item) }
        .accessibilityAction(named: "Remove") { store.remove(id: item.id) }
        .contextMenu {
            Button("Open") { store.open(item) }
                .disabled(item.isMissing)
            Button("Show in Finder") { store.reveal(item) }
                .disabled(item.isMissing)
            Divider()
            Button("Remove", role: .destructive) { store.remove(id: item.id) }
        }
        .modifier(DragIfPresent(enabled: item.resolvedURL != nil && !item.isMissing) {
            model.onInternalDragBegan?()
            return store.dragProvider(for: item)
        } preview: {
            thumbnail.frame(width: 56, height: 56)
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded { store.open(item) })
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(item.isMissing ? 0.04 : 0.08))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(hovering ? 0.28 : 0.12), lineWidth: 0.6)
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(item.isDirectory ? 8 : 5)
                    .opacity(item.isMissing ? 0.35 : 1)
            }
            if item.isMissing {
                Text("Missing")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.58))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
            }
        }
        .frame(width: thumb, height: thumb)
        .shadow(color: .black.opacity(hovering ? 0.45 : 0.28), radius: hovering ? 10 : 5, y: hovering ? 6 : 3)
    }

    private var removeButton: some View {
        Button {
            store.remove(id: item.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.black.opacity(0.72)))
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(item.displayName)")
    }
}

/// `onDrag` always installs a drag gesture. Skip it for missing files so a click still opens the menu.
private struct DragIfPresent<Preview: View>: ViewModifier {
    var enabled: Bool
    var provider: () -> NSItemProvider
    var preview: () -> Preview

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag(provider, preview: preview)
        } else {
            content
        }
    }
}
