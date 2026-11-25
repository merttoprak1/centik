import AppKit
import SwiftUI

struct StatusMenu: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var login: LoginItemController
    @ObservedObject var prefs: AppPreferences = .shared

    var body: some View {
        Button(prefs.hotKeyEnabled ? "Show Shelf (\(prefs.hotKey.displayString))" : "Show Shelf") {
            AppModel.shared.showShelf()
        }

        Button("Clear Shelf") {
            store.clear()
        }
        .disabled(store.items.isEmpty)
        .help("Return files to their original folders and clear the shelf.")

        Divider()

        Button("Settings…") {
            AppModel.shared.openSettings()
        }
        .keyboardShortcut(",")

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

        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")

        Button("Quit Centik") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
