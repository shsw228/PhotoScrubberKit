import UIKit
import OSLog

private let log = Logger(subsystem: "PhotoScrubberKit", category: "rotation-check")

public enum ScrubAxis: Sendable {
    case horizontal
    case vertical
}

@MainActor
public final class CustomScrubView: UICollectionView {

    public var axis: ScrubAxis = .horizontal {
        didSet {
            guard oldValue != axis else { return }
            pagingLayout.scrollDirection = (axis == .horizontal) ? .horizontal : .vertical
            pagingLayout.invalidateLayout()
            setContentOffset(.zero, animated: false)
            currentPageIndex = 0
            lastReportedPage = -1
            progress = 0
        }
    }

    public weak var pageDataSource: (any CustomScrubViewDataSource)?
    public weak var pageDelegate: (any CustomScrubViewDelegate)?

    @objc dynamic public private(set) var progress: CGFloat = 0
    public private(set) var currentPageIndex: Int = 0

    public var visibleView: UIView? {
        guard itemCount > 0 else { return nil }
        let indexPath = IndexPath(item: currentPageIndex, section: 0)
        return (cellForItem(at: indexPath) as? PageCell)?.hostedView
    }

    fileprivate var itemCount: Int = 0
    private let pagingLayout = PagingLayout()
    private let scrollProxy = ScrollProxy()
    private var lastReportedPage: Int = -1
    private var lastObservedBoundsSize: CGSize = .zero

    public init() {
        super.init(frame: .zero, collectionViewLayout: pagingLayout)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isPagingEnabled = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        pagingLayout.scrollDirection = (axis == .horizontal) ? .horizontal : .vertical
        scrollProxy.owner = self
        delegate = scrollProxy
        dataSource = scrollProxy
        register(PageCell.self, forCellWithReuseIdentifier: PageCell.reuseID)
    }

    public override func reloadData() {
        itemCount = pageDataSource?.numberOfPages(in: self) ?? 0
        currentPageIndex = 0
        lastReportedPage = -1
        progress = 0
        super.reloadData()
    }

    public func setCurrentPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < itemCount else { return }
        let extent = pageExtent
        guard extent > 0 else { return }
        let point: CGPoint = (axis == .horizontal)
            ? CGPoint(x: CGFloat(index) * extent, y: 0)
            : CGPoint(x: 0, y: CGFloat(index) * extent)
        setContentOffset(point, animated: animated)
    }

    public func setProgress(_ progress: CGFloat, animated: Bool = false) {
        guard itemCount > 0 else { return }
        let extent = pageExtent
        guard extent > 0 else { return }
        let clamped = max(0, min(CGFloat(itemCount - 1), progress))
        let point: CGPoint = (axis == .horizontal)
            ? CGPoint(x: clamped * extent, y: 0)
            : CGPoint(x: 0, y: clamped * extent)
        setContentOffset(point, animated: animated)
    }

    public func appendPage() {
        itemCount += 1
        let indexPath = IndexPath(item: itemCount - 1, section: 0)
        insertItems(at: [indexPath])
    }

    public func deletePage(at index: Int, animated: Bool) async {
        guard index >= 0, index < itemCount else { return }
        let oldCurrent = currentPageIndex
        itemCount -= 1
        let indexPath = IndexPath(item: index, section: 0)

        var newCurrent = oldCurrent
        if oldCurrent > index {
            newCurrent = oldCurrent - 1
        } else if oldCurrent == index && oldCurrent >= itemCount {
            newCurrent = max(0, itemCount - 1)
        }

        if animated {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                performBatchUpdates({
                    self.deleteItems(at: [indexPath])
                }, completion: { _ in cont.resume() })
            }
        } else {
            performBatchUpdates({
                self.deleteItems(at: [indexPath])
            })
        }

        if newCurrent != oldCurrent, itemCount > 0 {
            let extent = pageExtent
            if extent > 0 {
                let point: CGPoint = (axis == .horizontal)
                    ? CGPoint(x: CGFloat(newCurrent) * extent, y: 0)
                    : CGPoint(x: 0, y: CGFloat(newCurrent) * extent)
                setContentOffset(point, animated: false)
            }
        }
        currentPageIndex = newCurrent
        lastReportedPage = newCurrent
    }

    public override func layoutSubviews() {
        // 回転等で bounds.size が変わると、UICollectionView の invalidationContext
        // が contentOffset を補正してくれるはずだが、内部 auto-clamp や handleScroll の
        // 発火タイミングで負けることがある。super 通過前の (oldOffset, oldExtent) から
        // 「当時のページ」を逆算し、super 通過後に強制で復元する。
        // currentPageIndex は handleScroll で書き換わる可能性があるので頼らない。
        let oldBoundsSize = lastObservedBoundsSize
        let isH = (axis == .horizontal)
        let oldOffsetAlong = isH ? contentOffset.x : contentOffset.y
        let oldExtent = isH ? oldBoundsSize.width : oldBoundsSize.height

        super.layoutSubviews()

        if oldBoundsSize != .zero,
           bounds.size != oldBoundsSize,
           oldExtent > 0,
           itemCount > 0 {
            let newExtent = pageExtent
            if newExtent > 0 {
                let pageIndex = Int((oldOffsetAlong / oldExtent).rounded())
                let clamped = max(0, min(itemCount - 1, pageIndex))
                let target: CGPoint = isH
                    ? CGPoint(x: CGFloat(clamped) * newExtent, y: 0)
                    : CGPoint(x: 0, y: CGFloat(clamped) * newExtent)
                let before = contentOffset
                if contentOffset != target {
                    log.notice("🔧 fallback restored: bounds \(NSCoder.string(for: oldBoundsSize)) → \(NSCoder.string(for: self.bounds.size)), offset \(NSCoder.string(for: before)) → \(NSCoder.string(for: target)) (page \(clamped))")
                    contentOffset = target
                } else {
                    log.notice("✅ fallback skip: already at target \(NSCoder.string(for: target)) (page \(clamped))")
                }
                currentPageIndex = clamped
                lastReportedPage = clamped
            }
        }
        lastObservedBoundsSize = bounds.size
    }

    fileprivate func makeCell(at indexPath: IndexPath, in cv: UICollectionView) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: PageCell.reuseID, for: indexPath) as! PageCell
        if let view = pageDataSource?.scrubView(self, viewForPageAt: indexPath.item) {
            cell.host(view)
        }
        return cell
    }

    fileprivate func handleScroll() {
        guard itemCount > 0 else { return }
        let extent = pageExtent
        guard extent > 0 else { return }
        let offset = (axis == .horizontal) ? contentOffset.x : contentOffset.y
        let upper = CGFloat(max(itemCount - 1, 0))
        let clamped = min(max(offset / extent, 0), upper)
        if clamped != progress {
            progress = clamped
            pageDelegate?.scrubView(self, didUpdateProgress: clamped)
        }
        let newIndex = max(0, min(itemCount - 1, Int(clamped.rounded())))
        if newIndex != lastReportedPage {
            lastReportedPage = newIndex
            currentPageIndex = newIndex
            pageDelegate?.scrubView(self, didChangeVisiblePage: newIndex)
        }
    }

    private var pageExtent: CGFloat {
        axis == .horizontal ? bounds.width : bounds.height
    }
}

private final class PagingLayout: UICollectionViewFlowLayout {

    override init() {
        super.init()
        minimumLineSpacing = 0
        minimumInteritemSpacing = 0
        sectionInset = .zero
        scrollDirection = .horizontal
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func prepare() {
        if let cv = collectionView, cv.bounds.size != .zero {
            itemSize = cv.bounds.size
        }
        super.prepare()
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        if let cv = collectionView, cv.bounds.size != newBounds.size { return true }
        return false
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        guard let cv = collectionView, cv.bounds.size != newBounds.size else { return context }
        let isH = scrollDirection == .horizontal
        let oldExtent = isH ? cv.bounds.width : cv.bounds.height
        let newExtent = isH ? newBounds.width : newBounds.height
        guard oldExtent > 0, newExtent > 0 else { return context }
        let oldOffsetAlong = isH ? cv.contentOffset.x : cv.contentOffset.y
        let targetIndex = (oldOffsetAlong / oldExtent).rounded()
        let newOffsetAlong = targetIndex * newExtent
        let adjustment = newOffsetAlong - oldOffsetAlong
        context.contentOffsetAdjustment = isH
            ? CGPoint(x: adjustment, y: 0)
            : CGPoint(x: 0, y: adjustment)
        log.notice("📐 invalidationContext: bounds \(NSCoder.string(for: cv.bounds.size)) → \(NSCoder.string(for: newBounds.size)), idx=\(Int(targetIndex)), adjustment=\(adjustment)")
        return context
    }
}

private final class PageCell: UICollectionViewCell {
    static let reuseID = "PhotoScrubberKit.PageCell"

    weak var hostedView: UIView?

    func host(_ view: UIView) {
        hostedView?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        hostedView = view
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hostedView?.removeFromSuperview()
        hostedView = nil
    }
}

@MainActor
private final class ScrollProxy: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
    weak var owner: CustomScrubView?

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        owner?.itemCount ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        owner?.makeCell(at: indexPath, in: collectionView) ?? UICollectionViewCell()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        owner?.handleScroll()
    }
}
