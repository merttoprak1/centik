import AppKit
import Pow
import SwiftUI

struct ShelfItemView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var model: ShelfChromeModel
    let item: ShelfItem
    var index: Int = 0

    @StateObject private var loader = ThumbnailLoader()
    @State private var hovering = false
    @State private var revealed = false
    @State private var shineTick = 0
    @State private var landingTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let thumb: CGFloat = 58

    private var isSelected: Bool {
        store.selectedIDs.contains(item.id)
    }

    private var actionItems: [ShelfItem] {
        store.itemsForAction(targeting: item)
    }

    private var actionURLs: [URL] {
        actionItems.compactMap { $0.isMissing ? nil : $0.resolvedURL }
    }

    private var extensionBadge: String? {
        guard !item.isDirectory, !item.isMissing, let ext = item.resolvedURL?.pathExtension, !ext.isEmpty else {
            return nil
        }
        let upper = ext.uppercased()
        if upper == "WEBLOC" { return "URL" }
        return String(upper.prefix(4))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .overlay {
                        if item.resolvedURL != nil && !item.isMissing {
                            MultiFileDragOverlay(
                                urlsProvider: { store.dragEntries(startingFrom: item) },
                                onClick: { modifiers in
                                    Haptics.tick()
                                    store.select(item, modifiers: modifiers)
                                },
                                onDoubleClick: { store.open(item) },
                                onDragBegan: { model.onInternalDragBegan?() },
                                onDragEnded: { ids, operation in
                                    model.onInternalDragEnded?(ids, operation)
                                }
                            )
                        }
                    }
                    .padding(.top, 8)
                    .padding(.trailing, 8)
                if hovering {
                    removeButton
                        .zIndex(1)
                        .transition(.scale(scale: 0.55).combined(with: .opacity))
                }
            }
            .frame(width: 72, height: 70, alignment: .bottomLeading)

            Text(item.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(Color.white.opacity(item.isMissing ? 0.45 : (isSelected || hovering ? 0.98 : 0.84)))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 78, height: 28, alignment: .top)
        }
        .frame(width: 84, alignment: .top)
        .offset(y: (hovering && !reduceMotion ? -3.5 : 0) + (revealed || reduceMotion ? 0 : -10))
        .scaleEffect((hovering && !reduceMotion ? 1.055 : 1) * (revealed || reduceMotion ? 1 : 0.9), anchor: .bottom)
        .opacity(revealed || reduceMotion ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: hovering)
        .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isSelected)
        .changeEffect(.shine(duration: 0.48), value: shineTick, isEnabled: shineTick > 0 && !reduceMotion)
        .changeEffect(.jump(height: 11), value: landingTick, isEnabled: landingTick > 0 && !reduceMotion)
        .onHover { inside in
            hovering = inside
            if inside {
                shineTick += 1
                model.hoveredItemID = item.id
            } else if model.hoveredItemID == item.id {
                model.hoveredItemID = nil
            }
        }
        .onAppear {
            loader.load(item, side: thumb)
            triggerCascadeReveal()
        }
        .onChange(of: model.isExpanded) { _, expanded in
            if expanded {
                triggerCascadeReveal()
            } else {
                revealed = false
            }
        }
        .onChange(of: item.resolvedURL) { _, _ in loader.load(item, side: thumb) }
        .onChange(of: item.isMissing) { _, _ in loader.load(item, side: thumb) }
        .onChange(of: model.landingID) { _, id in
            if id == item.id { landingTick += 1 }
        }
        .help(item.tooltip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.isMissing ? "\(item.displayName), missing" : item.displayName)
        .accessibilityHint("Double-click to open. Drag to move the file out of the shelf.")
        .accessibilityAction(named: "Quick Look") { store.quickLook([item]) }
        .accessibilityAction(named: "Show in Finder") { store.reveal(item) }
        .accessibilityAction(named: "Remove") { store.remove(id: item.id) }
        .contextMenu {
            let targets = actionItems
            let urls = actionURLs
            let multi = targets.count > 1

            Button("Open") { store.open(item) }
                .disabled(item.isMissing)
            Button("Quick Look") { store.quickLook(targets) }
                .disabled(urls.isEmpty)
            Button("Show in Finder") { store.reveal(item) }
                .disabled(item.isMissing)

            Divider()

            if !urls.isEmpty {
                ShareLink(multi ? "Share \(urls.count) Items…" : "Share…", items: urls)
            }
            Button(multi ? "Copy \(urls.count) Files" : "Copy File") {
                store.copyFiles(targets)
                shineTick += 1
                model.onToast?("doc.on.doc.fill", multi ? "Copied \(urls.count) files" : "Copied file")
            }
            .disabled(urls.isEmpty)
            Button(multi ? "Copy Paths" : "Copy Path") {
                store.copyPaths(targets)
                shineTick += 1
                model.onToast?("link", multi ? "Copied \(urls.count) paths" : "Path copied")
            }
            .disabled(urls.isEmpty)
            Button(multi ? "Compress \(urls.count) Items" : "Compress") {
                Task { @MainActor in
                    if let id = await store.zipItems(targets) {
                        model.onCelebrate?(id)
                        model.onToast?("doc.zipper", multi ? "Zipped \(urls.count) items" : "Zipped item")
                    }
                }
            }
            .disabled(urls.isEmpty || store.isZipping)

            Divider()

            Button(multi ? "Return \(targets.count) Items" : (item.movedFromPath != nil ? "Return to \(item.originalFolderName ?? "Folder")" : "Remove"), role: .destructive) {
                let restored = store.remove(ids: targets.map(\.id))
                if restored.count == 1, let folder = restored.first?.deletingLastPathComponent().lastPathComponent {
                    model.onToast?("arrow.uturn.backward", "Returned to \(folder)")
                } else if restored.count > 1 {
                    model.onToast?("arrow.uturn.backward", "Returned \(restored.count) items")
                }
            }
        }
    }

    private func triggerCascadeReveal() {
        if reduceMotion {
            revealed = true
            return
        }
        let delay = Double(min(index, 6)) * 0.032
        withAnimation(.spring(response: 0.36, dampingFraction: 0.76).delay(delay)) {
            revealed = true
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(item.isMissing ? 0.05 : (isSelected ? 0.19 : (hovering ? 0.14 : 0.095))),
                            Color.white.opacity(item.isMissing ? 0.025 : (isSelected ? 0.11 : 0.045))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor.opacity(0.95))
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(hovering ? 0.38 : 0.18),
                                    Color.white.opacity(hovering ? 0.1 : 0.05)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        ),
                    lineWidth: isSelected ? 1.5 : 0.7
                )
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
            } else if hovering, let ext = extensionBadge {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(ext)
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.black.opacity(0.76)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.5))
                            .padding(3.5)
                    }
                }
                .transition(.scale(scale: 0.75).combined(with: .opacity))
            }
        }
        .frame(width: thumb, height: thumb)
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.32) : .black.opacity(hovering ? 0.5 : 0.28),
            radius: hovering || isSelected ? 11 : 5,
            y: hovering ? 7 : 3
        )
    }

    private var removeButton: some View {
        Button {
            Haptics.tick()
            let restored = store.remove(id: item.id)
            if let folder = restored.first?.deletingLastPathComponent().lastPathComponent {
                model.onToast?("arrow.uturn.backward", "Returned to \(folder)")
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.black.opacity(0.82)))
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 0.6))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(item.displayName)")
    }
}
