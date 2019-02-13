public final class ComposedDataSource: AggregateDataSource {

    public weak var updateDelegate: DataSourceUpdateDelegate?

    public var children: [DataSource] {
        return mappings.map { $0.dataSource }
    }

    private var mappings: [ComposedMappings] = []
    private var globalSectionToMapping: [Int: ComposedMappings] = [:]
    private var dataSourceToMappings: [DataSourceHashableWrapper: ComposedMappings] = [:]

    private var _numberOfSections: Int = 0
    public var numberOfSections: Int {
        _invalidate()
        return _numberOfSections
    }

    public func numberOfElements(in section: Int) -> Int {
        _invalidate()

        let mapping = self.mapping(for: section)
        let local = mapping.localSection(forGlobal: section)

        let numberOfSections = mapping.dataSource.numberOfSections
        assert(local < numberOfSections, "local section is out of bounds for composed data source")

        return mapping.dataSource.numberOfElements(in: local)
    }

    public init() { }

    public func setDataSources(_ dataSources: [DataSource], animated: Bool) {
        updateDelegate?.dataSource(self, willPerform: [])
        updateDelegate?.dataSource(self, performBatchUpdates: {
            removeAll()
            dataSources.forEach { append($0) }
        }, completion: { [unowned self, updateDelegate] _ in
            if !animated {
                updateDelegate?.dataSourceDidReload(self)
            }

            updateDelegate?.dataSource(self, didPerform: [])
        })
    }

    public func append(_ dataSource: DataSource) {
        insert(dataSource: dataSource, at: mappings.count)
    }

    public func insert(dataSource: DataSource, at index: Int) {
        let indexes = _insert(dataSource: dataSource, at: index)
        updateDelegate?.dataSource(self, didInsertSections: IndexSet(indexes))
    }

    private func _insert(dataSource: DataSource, at index: Int) -> [Int] {
        let wrapper = DataSourceHashableWrapper(dataSource)

        guard !dataSourceToMappings.keys.contains(wrapper) else {
            assertionFailure("\(wrapper.dataSource) has already been inserted")
            return []
        }

        guard (0...children.count).contains(index) else {
            assertionFailure("Index out of bounds for \(wrapper.dataSource)")
            return []
        }

        wrapper.dataSource.updateDelegate = self

        let mapping = ComposedMappings(wrapper.dataSource)
        mappings.insert(mapping, at: index)
        dataSourceToMappings[wrapper] = mapping

        _invalidate()
        return (0..<wrapper.dataSource.numberOfSections).map(mapping.globalSection(forLocal:))
    }

    public func remove(dataSource: DataSource) {
        let indexes = _remove(dataSource: dataSource)
        updateDelegate?.dataSource(self, didDeleteSections: IndexSet(indexes))
    }

    private func _remove(dataSource: DataSource) -> [Int] {
        let wrapper = DataSourceHashableWrapper(dataSource)

        guard let mapping = dataSourceToMappings[wrapper] else {
            fatalError("\(wrapper.dataSource) isn't a child of this dataSource")
        }

        let removedSections = (0..<wrapper.dataSource.numberOfSections)
            .map(mapping.globalSection(forLocal:))
        dataSourceToMappings[DataSourceHashableWrapper(wrapper.dataSource)] = nil

        if let index = mappings.index(where: { DataSourceHashableWrapper($0.dataSource) == wrapper }) {
            mappings.remove(at: index)
        }

        wrapper.dataSource.updateDelegate = nil

        _invalidate()
        return removedSections
    }

    public func removeAll() {
        updateDelegate?.dataSource(self, willPerform: [])
        updateDelegate?.dataSource(self, performBatchUpdates: {
            dataSourceToMappings.forEach {
                if $0.key.dataSource.updateDelegate === self {
                    $0.key.dataSource.updateDelegate = nil
                }

                let indexes = _remove(dataSource: $0.key.dataSource)
                updateDelegate?.dataSource(self, didDeleteSections: IndexSet(indexes))
            }
        }, completion: { [unowned self] _ in
            self.updateDelegate?.dataSource(self, didPerform: [])
        })
    }

    private func _invalidate() {
        _numberOfSections = 0
        globalSectionToMapping.removeAll()

        for mapping in mappings {
            mapping.invalidate(startingAt: _numberOfSections) { section in
                globalSectionToMapping[section] = mapping
            }

            _numberOfSections += mapping.numberOfSections
        }
    }

}

extension ComposedDataSource {

    private func localDataSourceAndIndexPath(for indexPath: IndexPath) -> (DataSource, IndexPath) {
        let dataSource = self.dataSource(forSection: indexPath.section)
        let mapping = self.mapping(for: indexPath.section)
        let local = mapping.localIndexPath(forGlobal: indexPath)
        return (dataSource, local)
    }

    private func localDataSourceAndSection(for section: Int) -> (DataSource, Int) {
        let dataSource = self.dataSource(forSection: section)
        let mapping = self.mapping(for: section)
        let local = mapping.localSection(forGlobal: section)
        return (dataSource, local)
    }

    public func dataSourceFor(global section: Int) -> (dataSource: DataSource, localSection: Int) {
        let mapping = self.mapping(for: section)
        let local = mapping.localSection(forGlobal: section)
        return (mapping.dataSource, local)
    }

    public func dataSourceFor(global indexPath: IndexPath) -> (dataSource: DataSource, localIndexPath: IndexPath) {
        let mapping = self.mapping(for: indexPath.section)
        let local = mapping.localIndexPath(forGlobal: indexPath)
        return (mapping.dataSource, local)
    }

}

public extension ComposedDataSource {

    public func indexPath(where predicate: @escaping (Any) -> Bool) -> IndexPath? {
        for child in children {
            if let indexPath = child.indexPath(where: predicate) {
                let mapping = self.mapping(for: child)
                return mapping.globalIndexPath(forLocal: indexPath)
            }
        }

        return nil
    }
    
}

private extension ComposedDataSource {

    func dataSource(forSection section: Int) -> DataSource {
        return mapping(for: section).dataSource
    }

    func mapping(for section: Int) -> ComposedMappings {
        return globalSectionToMapping[section]!
    }

    func mapping(for dataSource: DataSource) -> ComposedMappings {
        return dataSourceToMappings[DataSourceHashableWrapper(dataSource)]!
    }

    func globalSections(forLocalSections sections: IndexSet, inDataSource dataSource: DataSource) -> IndexSet {
        let mapping = self.mapping(for: dataSource)
        return IndexSet(sections.map { mapping.globalSection(forLocal: $0) })
    }

    func globalIndexPaths(forLocalIndexPaths indexPaths: [IndexPath], inDataSource dataSource: DataSource) -> [IndexPath] {
        let mapping = self.mapping(for: dataSource)
        return indexPaths.map { mapping.globalIndexPath(forLocal: $0) }
    }

}

extension ComposedDataSource: DataSourceUpdateDelegate {

    public func dataSource(_ dataSource: DataSource, didInsertSections sections: IndexSet) {
        let mapping = self.mapping(for: dataSource)
        let global = sections.map(mapping.globalSection(forLocal:))
        _invalidate()
        updateDelegate?.dataSource(self, didInsertSections: IndexSet(global))
    }

    public func dataSource(_ dataSource: DataSource, didDeleteSections sections: IndexSet) {
        let mapping = self.mapping(for: dataSource)
        let global = sections.map(mapping.globalSection(forLocal:))
        _invalidate()
        updateDelegate?.dataSource(self, didDeleteSections: IndexSet(global))
    }

    public func dataSource(_ dataSource: DataSource, didUpdateSections sections: IndexSet) {
        let mapping = self.mapping(for: dataSource)
        let global = sections.map(mapping.globalSection(forLocal:))
        updateDelegate?.dataSource(self, didUpdateSections: IndexSet(global))
        _invalidate()
    }

    public func dataSource(_ dataSource: DataSource, didMoveSection from: Int, to: Int) {
        let mapping = self.mapping(for: dataSource)
        let source = mapping.globalSection(forLocal: from)
        let target = mapping.globalSection(forLocal: to)
        _invalidate()
        updateDelegate?.dataSource(self, didMoveSection: source, to: target)
    }

    public func dataSource(_ dataSource: DataSource, didInsertIndexPaths indexPaths: [IndexPath]) {
        let mapping = self.mapping(for: dataSource)
        let global = mapping.globalIndexPaths(forLocal: indexPaths)
        updateDelegate?.dataSource(self, didInsertIndexPaths: global)
    }

    public func dataSource(_ dataSource: DataSource, didDeleteIndexPaths indexPaths: [IndexPath]) {
        let mapping = self.mapping(for: dataSource)
        let global = mapping.globalIndexPaths(forLocal: indexPaths)
        updateDelegate?.dataSource(self, didDeleteIndexPaths: global)
    }

    public func dataSource(_ dataSource: DataSource, didUpdateIndexPaths indexPaths: [IndexPath]) {
        let mapping = self.mapping(for: dataSource)
        let global = mapping.globalIndexPaths(forLocal: indexPaths)
        updateDelegate?.dataSource(self, didUpdateIndexPaths: global)
    }

    public func dataSource(_ dataSource: DataSource, didMoveFromIndexPath from: IndexPath, toIndexPath to: IndexPath) {
        let mapping = self.mapping(for: dataSource)
        let source = mapping.globalIndexPath(forLocal: from)
        let target = mapping.globalIndexPath(forLocal: to)
        updateDelegate?.dataSource(self, didMoveFromIndexPath: source, toIndexPath: target)
    }

    public func dataSource(_ dataSource: DataSource, performBatchUpdates updates: () -> Void, completion: ((Bool) -> Void)?) {
        updateDelegate?.dataSource(self, performBatchUpdates: updates, completion: completion)
    }

    public func dataSourceDidReload(_ dataSource: DataSource) {
        updateDelegate?.dataSourceDidReload(self)
    }

    public func dataSource(_ dataSource: DataSource, willPerform updates: [DataSourceUpdate]) {
        updateDelegate?.dataSource(self, willPerform: globalUpdates(fromLocal: updates, in: dataSource))
    }

    public func dataSource(_ dataSource: DataSource, didPerform updates: [DataSourceUpdate]) {
        updateDelegate?.dataSource(self, didPerform: globalUpdates(fromLocal: updates, in: dataSource))
    }

    public func dataSource(_ dataSource: DataSource, invalidateWith context: DataSourceUIInvalidationContext) {
        var globalContext = DataSourceUIInvalidationContext()
        globalContext.invalidateGlobalHeader = context.invalidateGlobalHeader
        globalContext.invalidateGlobalFooter = context.invalidateGlobalFooter

        let elementIndexPaths = globalIndexPaths(forLocalIndexPaths: Array(context.invalidatedElementIndexPaths), inDataSource: dataSource)
        globalContext.invalidateElements(at: elementIndexPaths)

        let headerIndexes = globalSections(forLocalSections: context.invalidatedHeaderIndexes, inDataSource: dataSource)
        globalContext.invalidateHeaders(in: headerIndexes)

        let footerIndexes = globalSections(forLocalSections: context.invalidatedFooterIndexes, inDataSource: dataSource)
        globalContext.invalidateHeaders(in: footerIndexes)

        updateDelegate?.dataSource(self, invalidateWith: globalContext)
    }

}

extension ComposedDataSource {

    private func globalUpdates(fromLocal updates: [DataSourceUpdate], in dataSource: DataSource) -> [DataSourceUpdate] {
        let mapping = self.mapping(for: dataSource)
        var updates: [DataSourceUpdate] = []

        for operation in updates {
            switch operation {
            case let .deleteSections(indexes):
                let global = indexes.map { mapping.globalSection(forLocal: $0) }
                updates.append(.deleteSections(global))
            case let .insertSections(indexes):
                let global = indexes.map { mapping.globalSection(forLocal: $0) }
                updates.append(.insertSections(global))
            case let .updateSections(indexes):
                let global = indexes.map { mapping.globalSection(forLocal: $0) }
                updates.append(.updateSections(global))
            case let .moveSections(indexes):
                let global = indexes.map { (source: mapping.globalSection(forLocal: $0),
                                            target: mapping.globalSection(forLocal: $1)) }
                updates.append(.moveSections(global))
            case let .deleteIndexPaths(indexPaths):
                let global = indexPaths.map { mapping.globalIndexPath(forLocal: $0) }
                updates.append(.deleteIndexPaths(global))
            case let .insertIndexPaths(indexPaths):
                let global = indexPaths.map { mapping.globalIndexPath(forLocal: $0) }
                updates.append(.insertIndexPaths(global))
            case let .updateIndexPaths(indexPaths):
                let global = indexPaths.map { mapping.globalIndexPath(forLocal: $0) }
                updates.append(.updateIndexPaths(global))
            case let .moveIndexPaths(indexPaths):
                let global = indexPaths.map { (source: mapping.globalIndexPath(forLocal: $0),
                                               target: mapping.globalIndexPath(forLocal: $1)) }
                updates.append(.moveIndexPaths(global))
            }
        }

        return updates
    }

}