import Foundation

/// Composition root shared by the menu bar and the notch panel.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let store = ShelfStore()
    let login = LoginItemController()
    let prefs = AppPreferences.shared
    private let settingsWindow = SettingsWindowController()
    private(set) var shelf: ShelfController?

    private init() {}

    func start() {
        store.load()
        login.refresh()
        let shelf = ShelfController(store: store)
        self.shelf = shelf
        shelf.start()
    }

    func showShelf() {
        shelf?.presentPinned()
    }

    func openSettings() {
        settingsWindow.show(store: store, login: login, prefs: prefs)
    }
}
