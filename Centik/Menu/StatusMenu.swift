import AppKit
import SwiftUI

struct StatusMenu: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var login: LoginItemController

    var body: some View {
        Button("Show Shelf") {
            AppModel.shared.showShelf()
        }

        Button("Clear Shelf") {
            store.clear()
        }
        .disabled(store.items.isEmpty)
        .help("Take everything off the shelf. Files you already had stay where they are.")

        Toggle("Launch at Login", isOn: Binding(
            get: { login.isEnabled },
            set: { login.setEnabled($0) }
        ))

        if login.needsApproval {
            Button("Approve in System Settings…") {
                login.openSettings()
            }
        }

        if let statusMessage = login.statusMessage, !statusMessage.isEmpty {
            Text(statusMessage)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Quit Centik") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
