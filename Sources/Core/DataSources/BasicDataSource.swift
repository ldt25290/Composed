import Foundation

open class BasicDataSource<Store>: CollectionDataSource where Store: DataStore {

    public let store: Store

    public weak var updateDelegate: DataSourceUpdateDelegate?

    public var isEmpty: Bool {
        return store.isEmpty
    }

    public init(store: Store) {
        self.store = store
        self.store.delegate = self
    }

    public var numberOfSections: Int {
        return store.numberOfSections
    }

    public func numberOfElements(in section: Int) -> Int {
        return store.numberOfElements(in: section)
    }

    public func indexPath(where predicate: @escaping (Any) -> Bool) -> IndexPath? {
        return store.indexPath(where: predicate)
    }

    public func element(at indexPath: IndexPath) -> Store.Element {
        return store.element(at: indexPath)
    }

    public func localSection(for section: Int) -> (dataSource: DataSource, localSection: Int) {
        return (self, section)
    }

}
