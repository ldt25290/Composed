import UIKit

/// A UICollectionViewFlowLayoutInvalidationContext subclass that adds support for global headers and footers.
///
/// This class should be used with `Composed.FlowLayout`
public final class FlowLayoutInvalidationContext: UICollectionViewFlowLayoutInvalidationContext {

    private var _invalidateGlobalHeader: Bool = false

    /// Invalidate the global header
    public var invalidateGlobalHeader: Bool {
        get { return _invalidateGlobalHeader }
        set {
            // we don't want to enable setting this to false once its true
            guard newValue else { return }
            _invalidateGlobalHeader = newValue
            invalidateFlowLayoutDelegateMetrics = true
        }
    }

    private var _invalidateGlobalFooter: Bool = false

    /// Invalidate the global footer
    public var invalidateGlobalFooter: Bool {
        get { return _invalidateGlobalFooter }
        set {
            // we don't want to enable setting this to false once its true
            guard newValue else { return }
            _invalidateGlobalFooter = newValue
            invalidateFlowLayoutDelegateMetrics = true
        }
    }

}
