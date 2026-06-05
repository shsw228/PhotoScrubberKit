import UIKit

public enum ScrubAxis: Sendable {
    case horizontal
    case vertical
}

public final class CustomScrubView: UIScrollView {

    public var axis: ScrubAxis = .horizontal {
        didSet {
            guard oldValue != axis else { return }
            handleAxisChange()
        }
    }

    public weak var pageDataSource: (any CustomScrubViewDataSource)?
    public weak var pageDelegate: (any CustomScrubViewDelegate)?

    @objc dynamic public private(set) var progress: CGFloat = 0
    public private(set) var visibleView: UIView?
    public private(set) var currentPageIndex: Int = 0

    private var numberOfPages: Int = 0
    private var mountedPages: [Int: UIView] = [:]
    private var lastReportedPage: Int = -1
    private var lastBoundsSize: CGSize = .zero
    private var isAnimatingMutation: Bool = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
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
    }

    public func reloadData() {
        for view in mountedPages.values {
            view.removeFromSuperview()
        }
        mountedPages.removeAll()
        lastReportedPage = -1
        visibleView = nil
        currentPageIndex = 0
        numberOfPages = pageDataSource?.numberOfPages(in: self) ?? 0
        updateContentSize()
        setNeedsLayout()
        layoutIfNeeded()
    }

    public func setCurrentPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < numberOfPages else { return }
        let extent = pageExtent
        guard extent > 0 else { return }
        switch axis {
        case .horizontal:
            setContentOffset(CGPoint(x: CGFloat(index) * extent, y: 0), animated: animated)
        case .vertical:
            setContentOffset(CGPoint(x: 0, y: CGFloat(index) * extent), animated: animated)
        }
    }

    public func setProgress(_ progress: CGFloat, animated: Bool = false) {
        guard numberOfPages > 0 else { return }
        let extent = pageExtent
        guard extent > 0 else { return }
        let clamped = max(0, min(CGFloat(numberOfPages - 1), progress))
        switch axis {
        case .horizontal:
            setContentOffset(CGPoint(x: clamped * extent, y: 0), animated: animated)
        case .vertical:
            setContentOffset(CGPoint(x: 0, y: clamped * extent), animated: animated)
        }
    }

    public func appendPage() {
        numberOfPages += 1
        updateContentSize()
        setNeedsLayout()
        layoutIfNeeded()
    }

    public func deletePage(at index: Int, animated: Bool) async {
        guard index >= 0, index < numberOfPages else { return }
        let extent = pageExtent
        guard extent > 0 else { return }

        let isHorizontal = (axis == .horizontal)
        let newCount = numberOfPages - 1
        let deletedView = mountedPages[index]

        var newMounted: [Int: UIView] = [:]
        for (i, view) in mountedPages where i != index {
            newMounted[i > index ? i - 1 : i] = view
        }

        var newCurrentIndex = currentPageIndex
        var targetOffset = contentOffset
        if currentPageIndex > index {
            newCurrentIndex = currentPageIndex - 1
            if isHorizontal { targetOffset.x -= extent } else { targetOffset.y -= extent }
        } else if currentPageIndex == index && currentPageIndex >= newCount {
            newCurrentIndex = max(0, newCount - 1)
            if isHorizontal {
                targetOffset = CGPoint(x: CGFloat(newCurrentIndex) * extent, y: 0)
            } else {
                targetOffset = CGPoint(x: 0, y: CGFloat(newCurrentIndex) * extent)
            }
        }

        let targetContentSize: CGSize = isHorizontal
            ? CGSize(width: extent * CGFloat(max(newCount, 0)), height: bounds.height)
            : CGSize(width: bounds.width, height: extent * CGFloat(max(newCount, 0)))

        isAnimatingMutation = true

        let animate: @MainActor () -> Void = {
            deletedView?.alpha = 0
            deletedView?.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            for (newIdx, view) in newMounted {
                view.frame = self.frame(forPageAt: newIdx)
            }
            self.contentOffset = targetOffset
            self.contentSize = targetContentSize
        }

        if animated {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                UIView.animate(withDuration: 0.3,
                               delay: 0,
                               options: [.curveEaseInOut, .beginFromCurrentState],
                               animations: animate,
                               completion: { _ in cont.resume() })
            }
        } else {
            animate()
        }

        deletedView?.removeFromSuperview()
        deletedView?.alpha = 1
        deletedView?.transform = .identity
        mountedPages = newMounted
        numberOfPages = newCount
        currentPageIndex = newCurrentIndex
        lastReportedPage = newCurrentIndex
        visibleView = newMounted[newCurrentIndex]
        isAnimatingMutation = false
        setNeedsLayout()
        layoutIfNeeded()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            updateContentSize()
            if numberOfPages > 0 {
                let extent = pageExtent
                switch axis {
                case .horizontal:
                    contentOffset = CGPoint(x: CGFloat(currentPageIndex) * extent, y: 0)
                case .vertical:
                    contentOffset = CGPoint(x: 0, y: CGFloat(currentPageIndex) * extent)
                }
            }
        }

        guard !isAnimatingMutation else { return }

        let extent = pageExtent
        guard extent > 0, numberOfPages > 0 else { return }

        let offset = (axis == .horizontal) ? contentOffset.x : contentOffset.y
        let upperBound = CGFloat(max(numberOfPages - 1, 0))
        let clamped = min(max(offset / extent, 0), upperBound)

        if clamped != progress {
            progress = clamped
            pageDelegate?.scrubView(self, didUpdateProgress: clamped)
        }

        let centerIndex = max(0, min(numberOfPages - 1, Int(clamped.rounded())))
        let keep = Set([centerIndex - 1, centerIndex, centerIndex + 1]
            .filter { (0..<numberOfPages).contains($0) })

        for (idx, view) in mountedPages where !keep.contains(idx) {
            view.removeFromSuperview()
            mountedPages.removeValue(forKey: idx)
        }

        for idx in keep where mountedPages[idx] == nil {
            guard let dataSource = pageDataSource else { continue }
            let view = dataSource.scrubView(self, viewForPageAt: idx)
            view.frame = frame(forPageAt: idx)
            addSubview(view)
            mountedPages[idx] = view
        }

        for (idx, view) in mountedPages {
            let expected = frame(forPageAt: idx)
            if view.frame != expected {
                view.frame = expected
            }
        }

        if centerIndex != lastReportedPage {
            lastReportedPage = centerIndex
            currentPageIndex = centerIndex
            visibleView = mountedPages[centerIndex]
            pageDelegate?.scrubView(self, didChangeVisiblePage: centerIndex)
        } else {
            visibleView = mountedPages[centerIndex]
        }
    }

    private var pageExtent: CGFloat {
        axis == .horizontal ? bounds.width : bounds.height
    }

    private func updateContentSize() {
        guard numberOfPages > 0 else {
            contentSize = .zero
            return
        }
        switch axis {
        case .horizontal:
            contentSize = CGSize(width: bounds.width * CGFloat(numberOfPages),
                                 height: bounds.height)
        case .vertical:
            contentSize = CGSize(width: bounds.width,
                                 height: bounds.height * CGFloat(numberOfPages))
        }
    }

    private func handleAxisChange() {
        for view in mountedPages.values {
            view.removeFromSuperview()
        }
        mountedPages.removeAll()
        lastReportedPage = -1
        updateContentSize()
        setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }

    private func frame(forPageAt index: Int) -> CGRect {
        switch axis {
        case .horizontal:
            return CGRect(x: bounds.width * CGFloat(index), y: 0,
                          width: bounds.width, height: bounds.height)
        case .vertical:
            return CGRect(x: 0, y: bounds.height * CGFloat(index),
                          width: bounds.width, height: bounds.height)
        }
    }
}
