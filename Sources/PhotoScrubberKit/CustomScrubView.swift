import UIKit

/// スクラブのスクロール方向。
public enum ScrubAxis: Sendable {
    /// 横方向にページング／スクロールする。
    case horizontal
    /// 縦方向にページング／スクロールする。
    case vertical
}

/// メイン画像用の paging スクラブビュー。
///
/// `UICollectionView` ベースで 1 ページ = 1 item を全面表示する。スクロールに応じて
/// ``progress`` を更新し、``CustomScrubViewDelegate`` へ進行度・ページ変化を通知する。
/// 回転で bounds が変わっても表示ページを保持する。
///
/// 単体でも使えるが、サムネイル帯と連動させるなら ``PhotoScrubberCoupling`` を使う。
@MainActor
public final class CustomScrubView: UICollectionView {

    /// スクロール方向。変更すると先頭ページへリセットされる。既定は ``ScrubAxis/horizontal``。
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

    /// ページ数と各ページの view を供給するデータソース。
    public weak var pageDataSource: (any CustomScrubViewDataSource)?
    /// 進行度・表示ページ変化の通知先。
    public weak var pageDelegate: (any CustomScrubViewDelegate)?

    /// 現在の進行度。`0...(pageCount - 1)` の連続値。KVO 可能 (`@objc dynamic`)。
    @objc dynamic public private(set) var progress: CGFloat = 0
    /// 現在表示中のページ index。
    public private(set) var currentPageIndex: Int = 0

    /// 現在表示中ページにホストされている view。該当が無ければ `nil`。
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

    /// データソースを読み直し、先頭ページへリセットする。
    public override func reloadData() {
        itemCount = pageDataSource?.numberOfPages(in: self) ?? 0
        currentPageIndex = 0
        lastReportedPage = -1
        progress = 0
        super.reloadData()
    }

    /// 指定ページへ移動する。
    /// - Parameters:
    ///   - index: 移動先ページ index。範囲外なら無視される。
    ///   - animated: アニメーション付きで移動するか。
    public func setCurrentPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < itemCount else { return }
        let extent = pageExtent
        guard extent > 0 else { return }
        let point: CGPoint = (axis == .horizontal)
            ? CGPoint(x: CGFloat(index) * extent, y: 0)
            : CGPoint(x: 0, y: CGFloat(index) * extent)
        setContentOffset(point, animated: animated)
        updateCurrentPage(to: index)
    }

    /// 進行度を直接指定して位置を合わせる。主に連動相手からの同期に使う。
    /// - Parameters:
    ///   - progress: `0...(pageCount - 1)` の連続値。範囲外は丸められる。
    ///   - animated: アニメーション付きで移動するか。既定 `false`。
    public func setProgress(_ progress: CGFloat, animated: Bool = false) {
        guard itemCount > 0 else { return }
        let extent = pageExtent
        guard extent > 0 else { return }
        let clamped = max(0, min(CGFloat(itemCount - 1), progress))
        let point: CGPoint = (axis == .horizontal)
            ? CGPoint(x: clamped * extent, y: 0)
            : CGPoint(x: 0, y: clamped * extent)
        setContentOffset(point, animated: animated)
        let intIndex = max(0, min(itemCount - 1, Int(clamped.rounded())))
        updateCurrentPage(to: intIndex)
    }

    private func updateCurrentPage(to index: Int) {
        guard index != lastReportedPage else { return }
        lastReportedPage = index
        currentPageIndex = index
        pageDelegate?.scrubView(self, didChangeVisiblePage: index)
    }

    /// 末尾にページを 1 つ追加する。追加分の view は ``pageDataSource`` から取得される。
    public func appendPage() {
        itemCount += 1
        let indexPath = IndexPath(item: itemCount - 1, section: 0)
        insertItems(at: [indexPath])
    }

    /// 指定ページを削除し、必要なら表示ページを補正する。
    /// - Parameters:
    ///   - index: 削除するページ index。範囲外なら無視される。
    ///   - animated: アニメーション付きで削除するか。`true` の場合は完了まで `await` で待つ。
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
        // 回転等で bounds.size が変わると UIKit が contentOffset を暗黙アニメで
        // 補間しに来るので、super 通過前の `currentPageIndex` (handleScroll の
        // gate で安定化済み) を使って新 bounds 上の正位置に強制復元する。
        let oldBoundsSize = lastObservedBoundsSize
        let preservedPage = currentPageIndex
        super.layoutSubviews()
        if oldBoundsSize != .zero, bounds.size != oldBoundsSize, itemCount > 0 {
            let newExtent = pageExtent
            if newExtent > 0 {
                let target: CGPoint = (axis == .horizontal)
                    ? CGPoint(x: CGFloat(preservedPage) * newExtent, y: 0)
                    : CGPoint(x: 0, y: CGFloat(preservedPage) * newExtent)
                if contentOffset != target {
                    contentOffset = target
                }
                lastReportedPage = preservedPage
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
        // currentPageIndex はユーザー由来 / setProgress(animated:true) によるスクロール時のみ更新。
        // 回転で UIKit が contentOffset を暗黙アニメする間は更新しない (中間値を信じてしまうと
        // currentPageIndex が壊れる)。
        let isUserDriven = isTracking || isDragging || isDecelerating
        guard isUserDriven else { return }

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
