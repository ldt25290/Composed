public protocol DataReusableView: class {
    static var reuseIdentifier: String { get }
}

public extension DataReusableView {
    static var reuseIdentifier: String { return String(describing: self) }
}

extension UICollectionReusableView: DataReusableView { }

private extension UICollectionView {
    func register(nibType: DataReusableView.Type, reuseIdentifier: String, kind: String? = nil) {
        let nib = UINib(nibName: String(describing: nibType), bundle: Bundle(for: nibType))

        if let kind = kind {
            register(nib, forSupplementaryViewOfKind: kind, withReuseIdentifier: reuseIdentifier)
        } else {
            register(nib, forCellWithReuseIdentifier: reuseIdentifier)
        }
    }

    func register(classType: DataReusableView.Type, reuseIdentifier: String, kind: String? = nil) {
        if let kind = kind {
            register(classType, forSupplementaryViewOfKind: kind, withReuseIdentifier: reuseIdentifier)
        } else {
            register(classType, forCellWithReuseIdentifier: reuseIdentifier)
        }
    }
}

public protocol DataSourceViewDelegate: class {
    func collectionView(_ collectionView: UICollectionView, didScrollTo contentOffset: CGPoint)
    func collectionView(_ collectionView: UICollectionView, didSelectItem indexPath: IndexPath)
    func collectionView(_ collectionView: UICollectionView, didDeselectItem indexPath: IndexPath)
}

public extension DataSourceViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didScrollTo contentOffset: CGPoint) { }
    func collectionView(_ collectionView: UICollectionView, didSelectItem indexPath: IndexPath) { }
    func collectionView(_ collectionView: UICollectionView, didDeselectItem indexPath: IndexPath) { }
}

internal final class CollectionViewWrapper: NSObject, UICollectionViewDataSource, FlowLayoutDelegate {

    internal let collectionView: UICollectionView
    internal let dataSource: DataSource
    internal weak var delegate: DataSourceViewDelegate?

    internal init(collectionView: UICollectionView, dataSource: DataSource) {
        self.collectionView = collectionView
        self.dataSource = dataSource

        super.init()

        collectionView.delegate = self
        collectionView.dataSource = self
    }

    @objc internal func numberOfSections(in collectionView: UICollectionView) -> Int {
        return dataSource.numberOfSections
    }

    @objc public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataSource.numberOfElements(in: section)
    }

    internal func setEditing(_ editing: Bool, animated: Bool) {
        let globalHeader = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindGlobalHeader, at: UICollectionView.globalElementIndexPath)
        let globalFooter = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindGlobalFooter, at: UICollectionView.globalElementIndexPath)
        let headers = collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader)
        let footers = collectionView.visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionFooter)

        [[globalHeader, globalFooter]
            .lazy
            .compactMap { $0 }, headers, footers]
            .flatMap { $0 }
            .compactMap { $0 as? DataSourceCellEditing }
            .forEach { $0.setEditing(editing, animated: animated) }

        let itemIndexPaths = collectionView.indexPathsForVisibleItems

        for global in itemIndexPaths {
            let (localDataSource, local) = self.dataSource.dataSourceFor(global: global)

            guard let dataSource = localDataSource as? DataSourceEditing,
                dataSource.supportsEditing(for: local) else { continue }

            dataSource.setEditing(editing, animated: animated)

            let cell = collectionView.cellForItem(at: global) as? DataSourceCellEditing
            cell?.setEditing(editing, animated: animated)
        }
    }

}

extension CollectionViewWrapper {

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let (localDataSource, section) = self.dataSource.dataSourceFor(global: section)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        return dataSource.metrics(for: section).insets
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        let (localDataSource, section) = self.dataSource.dataSourceFor(global: section)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        return dataSource.metrics(for: section).horizontalSpacing
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        let (localDataSource, section) = self.dataSource.dataSourceFor(global: section)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        return dataSource.metrics(for: section).verticalSpacing
    }

}

extension CollectionViewWrapper {

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        let (localDataSource, section) = self.dataSource.dataSourceFor(global: section)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        guard let config = dataSource.headerConfiguration(for: section) else { return .zero }

        let width = collectionView.bounds.width
        let target = CGSize(width: width, height: 0)

        config.configure(config.prototype, section)
        return config.prototype.systemLayoutSizeFitting(
            target, withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        let (localDataSource, section) = self.dataSource.dataSourceFor(global: section)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        guard let config = dataSource.footerConfiguration(for: section) else { return .zero }

        let width = collectionView.bounds.width
        let target = CGSize(width: width, height: 0)

        config.configure(config.prototype, section)
        return config.prototype.systemLayoutSizeFitting(
            target, withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let global = self.dataSource as? GlobalDataSource
        let (localDataSource, indexPath) = self.dataSource.dataSourceFor(global: indexPath)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        let configuration: HeaderFooterConfiguration?

        switch kind {
        case UICollectionView.elementKindGlobalHeader:
            configuration = global?.globalHeaderConfiguration
        case UICollectionView.elementKindGlobalFooter:
            configuration = global?.globalFooterConfiguration
        case UICollectionView.elementKindSectionHeader:
            configuration = dataSource.headerConfiguration(for: indexPath.section)
        case UICollectionView.elementKindSectionFooter:
            configuration = dataSource.footerConfiguration(for: indexPath.section)
        default: fatalError("Unsupported")
        }

        guard let config = configuration else { fatalError() }

        let type = Swift.type(of: config.prototype)
        switch config.dequeueSource {
        case .nib:
            collectionView.register(nibType: type, reuseIdentifier: config.reuseIdentifier, kind: kind)
        case .class:
            collectionView.register(classType: type, reuseIdentifier: config.reuseIdentifier, kind: kind)
        }

        return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: config.reuseIdentifier, for: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView, forElementKind elementKind: String, at indexPath: IndexPath) {
        let global = dataSource as? GlobalDataSource
        let (localDataSource, indexPath) = self.dataSource.dataSourceFor(global: indexPath)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        switch elementKind {
        case UICollectionView.elementKindGlobalHeader:
            let config = global?.globalHeaderConfiguration
            config?.configure(view, indexPath.section)
        case UICollectionView.elementKindGlobalFooter:
            let config = global?.globalFooterConfiguration
            config?.configure(view, indexPath.section)
        case UICollectionView.elementKindSectionHeader:
            let config = dataSource.headerConfiguration(for: indexPath.section)
            config?.configure(view, indexPath.section)
        case UICollectionView.elementKindSectionFooter:
            let config = dataSource.footerConfiguration(for: indexPath.section)
            config?.configure(view, indexPath.section)
        default:
            break
        }
    }

}

extension CollectionViewWrapper {

    func heightForGlobalHeader(in collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout) -> CGFloat {
        guard let config = (dataSource as? GlobalDataSource)?.globalHeaderConfiguration else { return 0 }

        let width = collectionView.bounds.width
        let target = CGSize(width: width, height: 0)

        config.configure(config.prototype, UICollectionView.globalElementIndexPath.section)
        return config.prototype.systemLayoutSizeFitting(
            target, withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
    }

    func heightForGlobalFooter(in collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout) -> CGFloat {
        guard let config = (dataSource as? GlobalDataSource)?.globalFooterConfiguration else { return 0 }

        let width = collectionView.bounds.width
        let target = CGSize(width: width, height: 0)

        config.configure(config.prototype, UICollectionView.globalElementIndexPath.section)
        return config.prototype.systemLayoutSizeFitting(
            target, withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
    }

}

extension CollectionViewWrapper {

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let (localDataSource, indexPath) = self.dataSource.dataSourceFor(global: indexPath)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        let metrics = dataSource.metrics(for: indexPath.section)
        let interitemSpacing = CGFloat(metrics.columnCount - 1) * metrics.horizontalSpacing
        let availableWidth = collectionView.bounds.width - metrics.insets.left - metrics.insets.right - interitemSpacing
        let width = (availableWidth / CGFloat(metrics.columnCount)).rounded(.down)
        let target = CGSize(width: width, height: 0)
        let config = dataSource.cellConfiguration(for: indexPath)
        config.configure(config.prototype, indexPath)
        return config.prototype.systemLayoutSizeFitting(
            target, withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
    }

    internal func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let (localDataSource, indexPath) = self.dataSource.dataSourceFor(global: indexPath)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        let config = dataSource.cellConfiguration(for: indexPath)
        let type = Swift.type(of: config.prototype)

        switch config.dequeueSource {
        case .nib:
            collectionView.register(nibType: type, reuseIdentifier: config.reuseIdentifier)
        case .class:
            collectionView.register(classType: type, reuseIdentifier: config.reuseIdentifier)
        }

        return collectionView.dequeueReusableCell(withReuseIdentifier: config.reuseIdentifier, for: indexPath)
    }

    internal func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        let (localDataSource, indexPath) = self.dataSource.dataSourceFor(global: indexPath)

        guard let dataSource = localDataSource as? DataSource & DataSourceUIProviding else {
            fatalError("The dataSource: (\(String(describing: localDataSource))), must conform to \(String(describing: DataSourceUIProviding.self))")
        }

        guard let cell = cell as? DataSourceCell else { return }

        let config = dataSource.cellConfiguration(for: indexPath)
        config.configure(cell, indexPath)

        guard let editable = dataSource as? DataSourceEditing, editable.supportsEditing(for: indexPath) else { return }
        (cell as? DataSourceCellEditing)?.setEditing(editable.isEditing, animated: false)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let (localDataSource, localIndexPath) = self.dataSource.dataSourceFor(global: indexPath)
        guard let dataSource = localDataSource as? DataSourceSelecting,
            dataSource.supportsSelection(for: localIndexPath) else { return }
        dataSource.selectElement(for: localIndexPath)
        delegate?.collectionView(collectionView, didSelectItem: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        let (localDataSource, localIndexPath) = self.dataSource.dataSourceFor(global: indexPath)
        guard let dataSource = localDataSource as? DataSourceSelecting,
            dataSource.supportsSelection(for: localIndexPath) else { return }
        delegate?.collectionView(collectionView, didDeselectItem: indexPath)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        delegate?.collectionView(collectionView, didScrollTo: collectionView.contentOffset)
    }

}
