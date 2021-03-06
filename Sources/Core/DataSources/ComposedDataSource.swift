import Foundation

open class ComposedDataSource: AggregateDataSource {

    public var descendants: [DataSource] {
        var descendants: [DataSource] = []

        for child in children {
            if let aggregate = child as? AggregateDataSource {
                descendants.append(contentsOf: [child] + aggregate.descendants)
            } else if let embed = child as? EmbeddingDataSource {
                descendants.append(contentsOf: embed.descendants)
            } else {
                descendants.append(child)
            }
        }

        return descendants
    }

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

    public final func numberOfElements(in section: Int) -> Int {
        _invalidate()

        let mapping = self.mapping(for: section)
        let local = mapping.localSection(forGlobal: section)

        let numberOfSections = mapping.dataSource.numberOfSections
        assert(local < numberOfSections, "local section is out of public bounds for composed data source")

        return mapping.dataSource.numberOfElements(in: local)
    }

    public init(children: [DataSource] = []) {
        children.reversed().forEach { _insert(dataSource: $0, at: 0) }
    }

    public final func replace(_ dataSources: [DataSource], animated: Bool) {
        removeAll()
        dataSources.reversed().forEach { _insert(dataSource: $0, at: 0) }
        let details = ComposedChangeDetails(hasIncrementalChanges: false)
        updateDelegate?.dataSource(self, performUpdates: details)
    }

    public func append(_ dataSource: DataSource) {
        insert(dataSource: dataSource, at: mappings.count)
    }

    public final func insert(dataSource: DataSource, at index: Int) {
        let indexes = _insert(dataSource: dataSource, at: index)
        var details = ComposedChangeDetails()
        details.insertedSections = IndexSet(indexes)
        updateDelegate?.dataSource(self, performUpdates: details)
    }

    @discardableResult
    private final func _insert(dataSource: DataSource, at index: Int) -> [Int] {
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

    public final func remove(dataSource: DataSource) {
        let indexes = _remove(dataSource: dataSource)
        _invalidate()
        var details = ComposedChangeDetails()
        details.removedSections = IndexSet(indexes)
        updateDelegate?.dataSource(self, performUpdates: details)
    }

    @discardableResult
    private func _remove(dataSource: DataSource) -> [Int] {
        let wrapper = DataSourceHashableWrapper(dataSource)

        guard let mapping = dataSourceToMappings[wrapper] else {
            fatalError("\(wrapper.dataSource) is not a child of this dataSource")
        }

        let removedSections = (0..<dataSource.numberOfSections)
            .map(mapping.globalSection(forLocal:))
        dataSourceToMappings[wrapper] = nil

        if let index = mappings.firstIndex(where: { DataSourceHashableWrapper($0.dataSource) == wrapper }) {
            mappings.remove(at: index)
        }

        wrapper.dataSource.updateDelegate = nil

        return removedSections
    }

    public final func removeAll() {
        let indexes = dataSourceToMappings.keys.flatMap {
            _remove(dataSource: $0.dataSource)
        }

        _invalidate()

        var details = ComposedChangeDetails()
        details.removedSections = IndexSet(indexes)
        updateDelegate?.dataSource(self, performUpdates: details)
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

    public final func localSection(for section: Int) -> (dataSource: DataSource, localSection: Int) {
        let mapping = self.mapping(for: section)
        let local = mapping.localSection(forGlobal: section)
        return mapping.dataSource.localSection(for: local)
    }

}

public extension ComposedDataSource {

    func indexPath(where predicate: @escaping (Any) -> Bool) -> IndexPath? {
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

internal extension ComposedChangeDetails {
    
    init(other details: ComposedChangeDetails, mapping: ComposedMappings) {
        hasIncrementalChanges = details.hasIncrementalChanges
        insertedSections = IndexSet(details.insertedSections.map(mapping.globalSection(forLocal:)))
        insertedIndexPaths = details.insertedIndexPaths.map(mapping.globalIndexPath(forLocal:))
        removedSections = IndexSet(details.removedSections.map(mapping.globalSection(forLocal:)))
        removedIndexPaths = details.removedIndexPaths.map(mapping.globalIndexPath(forLocal:))
        updatedSections = IndexSet(details.updatedSections.map(mapping.globalSection(forLocal:)))
        updatedIndexPaths = details.updatedIndexPaths.map(mapping.globalIndexPath(forLocal:))
        movedSections = details.movedSections.map(mapping.globalSections(forLocal:))
        movedIndexPaths = details.movedIndexPaths.map(mapping.globalIndexPaths(forLocal:))
    }
    
}

extension ComposedDataSource: DataSourceUpdateDelegate {

    public func dataSource(_ dataSource: DataSource, performUpdates changeDetails: ComposedChangeDetails) {
        let mapping = self.mapping(for: dataSource)
        
        if !changeDetails.insertedSections.isEmpty {
            // if we're inserting sections we need to invalidate BEFORE the update
            _invalidate()
        }

        let details = ComposedChangeDetails(other: changeDetails, mapping: mapping)
        updateDelegate?.dataSource(self, performUpdates: details)

        if !changeDetails.removedSections.isEmpty {
            // if we're removing sections we need to invalidate AFTER the update
            _invalidate()
        }
    }

    public final func dataSource(_ dataSource: DataSource, invalidateWith context: DataSourceInvalidationContext) {
        var globalContext = DataSourceInvalidationContext.make(from: context)

        let elementIndexPaths = globalIndexPaths(forLocalIndexPaths: Array(context.invalidatedElementIndexPaths), inDataSource: dataSource)
        globalContext.invalidateElements(at: elementIndexPaths)

        let headerIndexes = globalSections(forLocalSections: context.invalidatedHeaderIndexes, inDataSource: dataSource)
        globalContext.invalidateHeaders(in: headerIndexes)

        let footerIndexes = globalSections(forLocalSections: context.invalidatedFooterIndexes, inDataSource: dataSource)
        globalContext.invalidateHeaders(in: footerIndexes)

        updateDelegate?.dataSource(self, invalidateWith: globalContext)
    }

    public func dataSource(_ dataSource: DataSource, sectionFor local: Int) -> (dataSource: DataSource, globalSection: Int) {
        let mapping = self.mapping(for: dataSource)
        let global = mapping.globalSection(forLocal: local)
        return updateDelegate?.dataSource(self, sectionFor: global) ?? (self, global)
    }

}
