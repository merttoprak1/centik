import Foundation

/// Composition root shared by the menu bar and the notch panel.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let store = ShelfStore()
    let login = LoginItemController()
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
}
