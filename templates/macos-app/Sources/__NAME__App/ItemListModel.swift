import Observation
import __NAME__Core

/// Holds what the window shows. All reading and writing goes through `ItemStore`.
@MainActor
@Observable
final class ItemListModel {
    private(set) var items: [Item] = []
    private(set) var errorMessage: String?
    private let store: ItemStore?

    init() {
        do {
            store = try AppDataLocation.makeStore()
        } catch {
            store = nil
            errorMessage = error.localizedDescription
        }
        reload()
    }

    func reload() {
        perform { _ in }
    }

    @discardableResult
    func add(title: String) -> Bool {
        perform { try $0.add(title: title) }
    }

    func setDone(_ item: Item, _ isDone: Bool) {
        perform { try $0.setDone(id: item.id, isDone) }
    }

    func remove(_ item: Item) {
        perform { try $0.remove(id: item.id) }
    }

    /// Runs `action`, then reads the list again. Returns false and shows the error if anything throws.
    @discardableResult
    private func perform(_ action: (ItemStore) throws -> Void) -> Bool {
        guard let store else {
            return false
        }
        do {
            try action(store)
            items = try store.list()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
