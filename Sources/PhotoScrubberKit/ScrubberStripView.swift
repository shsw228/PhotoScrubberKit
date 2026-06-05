import UIKit

@MainActor
public protocol ScrubberThumbnailDataSource: AnyObject {
    func numberOfThumbnails(in stripView: ScrubberStripView) -> Int
    func stripView(_ stripView: ScrubberStripView, thumbnailViewAt index: Int) -> UIView
}

@MainActor
public protocol ScrubberStripViewDelegate: AnyObject {
    func stripView(_ stripView: ScrubberStripView, didUpdateProgress progress: CGFloat)
}

public extension ScrubberStripViewDelegate {
    func stripView(_ stripView: ScrubberStripView, didUpdateProgress progress: CGFloat) {}
}

@MainActor
public final class ScrubberStripView: UICollectionView {

    public var axis: ScrubAxis = .horizontal {
        didSet {
            guard oldValue != axis else { return }
            stripLayout.scrollDirection = (axis == .horizontal) ? .horizontal : .vertical
            stripLayout.invalidateLayout()
            setContentOffset(.zero, animated: false)
            progress = 0
            relayoutContentInset()
        }
    }

    public var selectedThumbnailLength: CGFloat = 56 {
        didSet { propagate(\.selectedLength, value: selectedThumbnailLength, oldValue: oldValue) }
    }

    public var unselectedThumbnailLength: CGFloat = 16 {
        didSet { propagate(\.unselectedLength, value: unselectedThumbnailLength, oldValue: oldValue) }
    }

    public var thumbnailBreadth: CGFloat = 56 {
        didSet { propagate(\.breadth, value: thumbnailBreadth, oldValue: oldValue) }
    }

    public var thumbnailGap: CGFloat = 4 {
        didSet { propagate(\.gap, value: thumbnailGap, oldValue: oldValue) }
    }

    public var selectedThumbnailPadding: CGFloat = 12 {
        didSet { propagate(\.selectedPadding, value: selectedThumbnailPadding, oldValue: oldValue) }
    }

    public var snapsToNearestThumbnail: Bool = true {
        didSet { stripLayout.snapsToNearestItem = snapsToNearestThumbnail }
    }

    public weak var thumbnailDataSource: (any ScrubberThumbnailDataSource)?
    public weak var stripDelegate: (any ScrubberStripViewDelegate)?

    @objc dynamic public private(set) var progress: CGFloat = 0

    fileprivate var itemCount: Int = 0
    private let stripLayout = ScrubberStripLayout()
    private let scrollProxy = ScrollProxy()
    private var lastObservedBoundsSize: CGSize = .zero

    public init() {
        super.init(frame: .zero, collectionViewLayout: stripLayout)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .normal
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        clipsToBounds = false

        stripLayout.scrollDirection = (axis == .horizontal) ? .horizontal : .vertical
        stripLayout.selectedLength = selectedThumbnailLength
        stripLayout.unselectedLength = unselectedThumbnailLength
        stripLayout.breadth = thumbnailBreadth
        stripLayout.gap = thumbnailGap
        stripLayout.selectedPadding = selectedThumbnailPadding
        stripLayout.snapsToNearestItem = snapsToNearestThumbnail

        scrollProxy.owner = self
        delegate = scrollProxy
        dataSource = scrollProxy
        register(ThumbnailCell.self, forCellWithReuseIdentifier: ThumbnailCell.reuseID)
    }

    public override func reloadData() {
        itemCount = thumbnailDataSource?.numberOfThumbnails(in: self) ?? 0
        progress = 0
        super.reloadData()
        relayoutContentInset()
    }

    public func setProgress(_ progress: CGFloat, animated: Bool = false) {
        guard itemCount > 0 else { return }
        let mainExtent = pageExtent
        guard mainExtent > 0 else { return }
        let clamped = max(0, min(CGFloat(itemCount - 1), progress))
        let target = stripLayout.offsetForProgress(clamped, mainExtent: mainExtent)
        let point: CGPoint = isHorizontal
            ? CGPoint(x: target, y: 0)
            : CGPoint(x: 0, y: target)
        setContentOffset(point, animated: animated)
        // handleScroll は user-driven のみ反映するので、ここで明示更新。
        self.progress = clamped
    }

    public func appendThumbnail() {
        itemCount += 1
        let indexPath = IndexPath(item: itemCount - 1, section: 0)
        insertItems(at: [indexPath])
        relayoutContentInset()
    }

    public func deleteThumbnail(at index: Int, animated: Bool) async {
        guard index >= 0, index < itemCount else { return }
        itemCount -= 1
        let indexPath = IndexPath(item: index, section: 0)
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
        relayoutContentInset()
    }

    public override func layoutSubviews() {
        // 回転で bounds.size が変わると UIKit が contentOffset を暗黙アニメで触ってくる。
        // super 通過前の progress (handleScroll を user-driven gate して安定化済み) で
        // 新 bounds 上の正位置に強制復元する。
        let oldBoundsSize = lastObservedBoundsSize
        let preservedProgress = progress
        super.layoutSubviews()
        if oldBoundsSize != .zero, bounds.size != oldBoundsSize {
            relayoutContentInset()
            if itemCount > 0 {
                let mainExtent = pageExtent
                if mainExtent > 0 {
                    let target = stripLayout.offsetForProgress(preservedProgress, mainExtent: mainExtent)
                    let point: CGPoint = isHorizontal
                        ? CGPoint(x: target, y: 0)
                        : CGPoint(x: 0, y: target)
                    if contentOffset != point {
                        contentOffset = point
                    }
                }
            }
        }
        lastObservedBoundsSize = bounds.size
    }

    fileprivate func makeCell(at indexPath: IndexPath, in cv: UICollectionView) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: ThumbnailCell.reuseID, for: indexPath) as! ThumbnailCell
        if let view = thumbnailDataSource?.stripView(self, thumbnailViewAt: indexPath.item) {
            cell.host(view)
        }
        return cell
    }

    fileprivate func handleScroll() {
        guard itemCount > 0 else { return }
        let mainExtent = pageExtent
        guard mainExtent > 0 else { return }
        // user-driven 時のみ progress / delegate を更新。回転時の暗黙 contentOffset 変化を無視する。
        let isUserDriven = isTracking || isDragging || isDecelerating
        guard isUserDriven else { return }
        let offset = isHorizontal ? contentOffset.x : contentOffset.y
        let newProgress = stripLayout.progressForOffset(offset, itemCount: itemCount, mainExtent: mainExtent)
        if newProgress != progress {
            progress = newProgress
            stripDelegate?.stripView(self, didUpdateProgress: newProgress)
        }
    }

    fileprivate func handleSelect(at indexPath: IndexPath) {
        guard indexPath.item < itemCount else { return }
        setProgress(CGFloat(indexPath.item), animated: true)
        stripDelegate?.stripView(self, didUpdateProgress: CGFloat(indexPath.item))
    }

    private var isHorizontal: Bool { axis == .horizontal }

    private var pageExtent: CGFloat {
        isHorizontal ? bounds.width : bounds.height
    }

    private func relayoutContentInset() {
        let mainExtent = pageExtent
        guard mainExtent > 0 else { return }
        let inset = max(0, (mainExtent - selectedThumbnailLength) / 2)
        contentInset = isHorizontal
            ? UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            : UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
    }

    private func propagate<V: Equatable>(_ keyPath: ReferenceWritableKeyPath<ScrubberStripLayout, V>, value: V, oldValue: V) {
        guard value != oldValue else { return }
        stripLayout[keyPath: keyPath] = value
        relayoutContentInset()
        stripLayout.invalidateLayout()
    }
}

// MARK: - ScrubberStripLayout

@MainActor
final class ScrubberStripLayout: UICollectionViewLayout {
    var scrollDirection: UICollectionView.ScrollDirection = .horizontal

    var selectedLength: CGFloat = 56
    var unselectedLength: CGFloat = 16
    var breadth: CGFloat = 56
    var gap: CGFloat = 4
    var selectedPadding: CGFloat = 12
    var snapsToNearestItem: Bool = true

    private var attributes: [UICollectionViewLayoutAttributes] = []
    private var totalContentSize: CGSize = .zero

    private var isHorizontal: Bool { scrollDirection == .horizontal }
    private var pitch: CGFloat { unselectedLength + gap }

    override var collectionViewContentSize: CGSize { totalContentSize }

    override func prepare() {
        super.prepare()
        guard let cv = collectionView, cv.numberOfSections > 0 else { return }
        let itemCount = cv.numberOfItems(inSection: 0)
        guard itemCount > 0 else {
            attributes = []
            totalContentSize = .zero
            return
        }

        let mainExtent = isHorizontal ? cv.bounds.width : cv.bounds.height
        let crossExtent = isHorizontal ? cv.bounds.height : cv.bounds.width
        guard mainExtent > 0 else { return }

        let mainOffset = isHorizontal ? cv.contentOffset.x : cv.contentOffset.y
        let progress = progressForOffset(mainOffset, itemCount: itemCount, mainExtent: mainExtent)

        let crossInset = (crossExtent - breadth) / 2
        var attrs: [UICollectionViewLayoutAttributes] = []
        attrs.reserveCapacity(itemCount)
        var x: CGFloat = 0
        for i in 0..<itemCount {
            let length = widthForItem(at: i, progress: progress)
            let attr = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: i, section: 0))
            attr.frame = isHorizontal
                ? CGRect(x: x, y: crossInset, width: length, height: breadth)
                : CGRect(x: crossInset, y: x, width: breadth, height: length)
            attrs.append(attr)
            x += length
            if i < itemCount - 1 {
                x += gapAfter(i, progress: progress)
            }
        }
        attributes = attrs

        let totalLength = selectedLength + CGFloat(itemCount - 1) * pitch + selectedPadding
        totalContentSize = isHorizontal
            ? CGSize(width: totalLength, height: crossExtent)
            : CGSize(width: crossExtent, height: totalLength)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard attributes.indices.contains(indexPath.item) else { return nil }
        return attributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        true  // 進行度連動レイアウトなので、スクロールごとに再計算
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        guard let cv = collectionView, cv.bounds.size != newBounds.size else { return context }
        let itemCount = cv.numberOfItems(inSection: 0)
        guard itemCount > 0 else { return context }
        let isH = isHorizontal
        let oldExtent = isH ? cv.bounds.width : cv.bounds.height
        let newExtent = isH ? newBounds.width : newBounds.height
        guard oldExtent > 0, newExtent > 0 else { return context }
        let oldOffsetAlong = isH ? cv.contentOffset.x : cv.contentOffset.y
        let targetProgress = progressForOffset(oldOffsetAlong, itemCount: itemCount, mainExtent: oldExtent)
        let newOffsetAlong = offsetForProgress(targetProgress, mainExtent: newExtent)
        let adjustment = newOffsetAlong - oldOffsetAlong
        context.contentOffsetAdjustment = isH
            ? CGPoint(x: adjustment, y: 0)
            : CGPoint(x: 0, y: adjustment)
        return context
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard snapsToNearestItem, let cv = collectionView, cv.numberOfSections > 0 else { return proposedContentOffset }
        let itemCount = cv.numberOfItems(inSection: 0)
        guard itemCount > 0 else { return proposedContentOffset }
        let mainExtent = isHorizontal ? cv.bounds.width : cv.bounds.height
        guard mainExtent > 0 else { return proposedContentOffset }
        let proposed = isHorizontal ? proposedContentOffset.x : proposedContentOffset.y
        let p = progressForOffset(proposed, itemCount: itemCount, mainExtent: mainExtent)
        let snappedIndex = max(0, min(itemCount - 1, Int(p.rounded())))
        let snappedOffset = offsetForProgress(CGFloat(snappedIndex), mainExtent: mainExtent)
        return isHorizontal
            ? CGPoint(x: snappedOffset, y: proposedContentOffset.y)
            : CGPoint(x: proposedContentOffset.x, y: snappedOffset)
    }

    func offsetForProgress(_ p: CGFloat, mainExtent: CGFloat) -> CGFloat {
        p * pitch + selectedLength / 2 - mainExtent / 2
    }

    func progressForOffset(_ offset: CGFloat, itemCount: Int, mainExtent: CGFloat) -> CGFloat {
        guard pitch > 0 else { return 0 }
        let raw = (offset + mainExtent / 2 - selectedLength / 2) / pitch
        return max(0, min(CGFloat(max(itemCount - 1, 0)), raw))
    }

    private func widthForItem(at index: Int, progress: CGFloat) -> CGFloat {
        let distance = abs(CGFloat(index) - progress)
        let proximity = max(0, 1 - distance)
        return unselectedLength + (selectedLength - unselectedLength) * proximity
    }

    private func gapAfter(_ index: Int, progress: CGFloat) -> CGFloat {
        let midpoint = CGFloat(index) + 0.5
        let proximity = max(0, 1 - abs(midpoint - progress))
        return gap + selectedPadding * proximity
    }
}

// MARK: - Cell

private final class ThumbnailCell: UICollectionViewCell {
    static let reuseID = "PhotoScrubberKit.ThumbnailCell"

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

// MARK: - ScrollProxy

@MainActor
private final class ScrollProxy: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
    weak var owner: ScrubberStripView?

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        owner?.itemCount ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        owner?.makeCell(at: indexPath, in: collectionView) ?? UICollectionViewCell()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        owner?.handleScroll()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        owner?.handleSelect(at: indexPath)
        collectionView.deselectItem(at: indexPath, animated: false)
    }
}
