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

public final class ScrubberStripView: UIScrollView {

    public var axis: ScrubAxis = .horizontal {
        didSet {
            guard oldValue != axis else { return }
            handleAxisChange()
        }
    }

    public var selectedThumbnailLength: CGFloat = 56 {
        didSet {
            guard oldValue != selectedThumbnailLength else { return }
            relayout()
        }
    }

    public var unselectedThumbnailLength: CGFloat = 16 {
        didSet {
            guard oldValue != unselectedThumbnailLength else { return }
            relayout()
        }
    }

    public var thumbnailBreadth: CGFloat = 56 {
        didSet {
            guard oldValue != thumbnailBreadth else { return }
            setNeedsLayout()
        }
    }

    public var thumbnailGap: CGFloat = 4 {
        didSet {
            guard oldValue != thumbnailGap else { return }
            relayout()
        }
    }

    public var selectedThumbnailPadding: CGFloat = 12 {
        didSet {
            guard oldValue != selectedThumbnailPadding else { return }
            relayout()
        }
    }

    public var snapsToNearestThumbnail: Bool = true

    public weak var thumbnailDataSource: (any ScrubberThumbnailDataSource)?
    public weak var stripDelegate: (any ScrubberStripViewDelegate)?

    @objc dynamic public private(set) var progress: CGFloat = 0

    private var thumbCount: Int = 0
    private var mountedThumbs: [Int: UIView] = [:]
    private var lastBoundsSize: CGSize = .zero
    private var isAnimatingMutation: Bool = false
    private let scrollDelegateProxy = ScrollDelegateProxy()

    public override init(frame: CGRect) {
        super.init(frame: frame)
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
        clipsToBounds = false
        scrollDelegateProxy.owner = self
        delegate = scrollDelegateProxy
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    fileprivate func handleEndDragging(targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard snapsToNearestThumbnail, thumbCount > 0 else { return }
        let projected = isHorizontal ? targetContentOffset.pointee.x : targetContentOffset.pointee.y
        let projectedProgress = progressForOffset(projected)
        let snappedIndex = max(0, min(thumbCount - 1, Int(projectedProgress.rounded())))
        let snapped = offsetForProgress(CGFloat(snappedIndex))
        if isHorizontal {
            targetContentOffset.pointee.x = snapped
        } else {
            targetContentOffset.pointee.y = snapped
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isAnimatingMutation, thumbCount > 0 else { return }
        let location = gesture.location(in: self)
        let locationMain = isHorizontal ? location.x : location.y
        let frames = computeFrames(thumbCount: thumbCount, progress: progress)
        var bestIndex = 0
        var bestDistance: CGFloat = .infinity
        for (index, frame) in frames {
            let mid = isHorizontal ? frame.midX : frame.midY
            let distance = abs(mid - locationMain)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        setProgress(CGFloat(bestIndex), animated: true)
    }

    public func reloadData() {
        for view in mountedThumbs.values {
            view.removeFromSuperview()
        }
        mountedThumbs.removeAll()
        thumbCount = thumbnailDataSource?.numberOfThumbnails(in: self) ?? 0
        relayout()
        setNeedsLayout()
        layoutIfNeeded()
    }

    public func setProgress(_ progress: CGFloat, animated: Bool = false) {
        guard thumbCount > 0 else { return }
        let clamped = max(0, min(CGFloat(thumbCount - 1), progress))
        let target = offsetForProgress(clamped)
        let point = isHorizontal ? CGPoint(x: target, y: 0) : CGPoint(x: 0, y: target)
        setContentOffset(point, animated: animated)
        // handleScroll は user-driven のみ反映するので、ここで明示的に progress を更新する。
        self.progress = clamped
    }

    public func appendThumbnail() {
        thumbCount += 1
        relayout()
        setNeedsLayout()
        layoutIfNeeded()
    }

    public func deleteThumbnail(at index: Int, animated: Bool) async {
        guard index >= 0, index < thumbCount else { return }

        let centerIdx = Int(progress.rounded())
        let newCount = thumbCount - 1
        let deletedView = mountedThumbs[index]

        var newMounted: [Int: UIView] = [:]
        for (i, view) in mountedThumbs where i != index {
            newMounted[i > index ? i - 1 : i] = view
        }

        let shiftOffset: CGFloat = (index < centerIdx) ? -pitch : 0
        let targetMainOffset = currentMainOffset + shiftOffset
        let newProgress = max(0, min(CGFloat(max(newCount - 1, 0)),
                                     progressForOffset(targetMainOffset)))
        let targetContentLength = contentLength(forCount: newCount)
        let newFrames = computeFrames(thumbCount: newCount, progress: newProgress)

        isAnimatingMutation = true

        let animate: @MainActor () -> Void = {
            deletedView?.alpha = 0
            deletedView?.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            for (newIdx, view) in newMounted {
                if let target = newFrames[newIdx] {
                    view.frame = target
                }
            }
            if self.isHorizontal {
                self.contentOffset = CGPoint(x: targetMainOffset, y: 0)
                self.contentSize = CGSize(width: targetContentLength, height: self.bounds.height)
            } else {
                self.contentOffset = CGPoint(x: 0, y: targetMainOffset)
                self.contentSize = CGSize(width: self.bounds.width, height: targetContentLength)
            }
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
        mountedThumbs = newMounted
        thumbCount = newCount
        isAnimatingMutation = false
        setNeedsLayout()
        layoutIfNeeded()
    }

    private var isHorizontal: Bool { axis == .horizontal }
    private var mainExtent: CGFloat { isHorizontal ? bounds.width : bounds.height }
    private var crossExtent: CGFloat { isHorizontal ? bounds.height : bounds.width }
    private var currentMainOffset: CGFloat { isHorizontal ? contentOffset.x : contentOffset.y }

    private var pitch: CGFloat { unselectedThumbnailLength + thumbnailGap }

    private func contentLength(forCount n: Int) -> CGFloat {
        guard n > 0 else { return 0 }
        return selectedThumbnailLength + CGFloat(n - 1) * pitch + selectedThumbnailPadding
    }

    private func gapAfter(_ index: Int, progress: CGFloat) -> CGFloat {
        let midpoint = CGFloat(index) + 0.5
        let proximity = max(0, 1 - abs(midpoint - progress))
        return thumbnailGap + selectedThumbnailPadding * proximity
    }

    private func offsetForProgress(_ p: CGFloat) -> CGFloat {
        p * pitch + selectedThumbnailLength / 2 - mainExtent / 2
    }

    private func progressForOffset(_ offset: CGFloat) -> CGFloat {
        (offset + mainExtent / 2 - selectedThumbnailLength / 2) / pitch
    }

    private func lengthForThumb(at index: Int, progress: CGFloat) -> CGFloat {
        let distance = abs(CGFloat(index) - progress)
        let proximity = max(0, 1 - distance)
        return unselectedThumbnailLength + (selectedThumbnailLength - unselectedThumbnailLength) * proximity
    }

    private func computeFrames(thumbCount: Int, progress: CGFloat) -> [Int: CGRect] {
        var frames: [Int: CGRect] = [:]
        guard thumbCount > 0 else { return frames }
        let crossOffset = (crossExtent - thumbnailBreadth) / 2
        var main: CGFloat = 0
        for i in 0..<thumbCount {
            let length = lengthForThumb(at: i, progress: progress)
            let frame: CGRect
            if isHorizontal {
                frame = CGRect(x: main, y: crossOffset, width: length, height: thumbnailBreadth)
            } else {
                frame = CGRect(x: crossOffset, y: main, width: thumbnailBreadth, height: length)
            }
            frames[i] = frame
            main += length
            if i < thumbCount - 1 {
                main += gapAfter(i, progress: progress)
            }
        }
        return frames
    }

    private func relayout() {
        guard mainExtent > 0 else { return }
        let inset = max(0, (mainExtent - selectedThumbnailLength) / 2)
        let total = contentLength(forCount: thumbCount)
        if isHorizontal {
            contentInset = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            contentSize = CGSize(width: total, height: bounds.height)
        } else {
            contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
            contentSize = CGSize(width: bounds.width, height: total)
        }
    }

    private func handleAxisChange() {
        for view in mountedThumbs.values {
            view.removeFromSuperview()
        }
        mountedThumbs.removeAll()
        relayout()
        setContentOffset(.zero, animated: false)
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            relayout()
            if thumbCount > 0 {
                let target = offsetForProgress(progress)
                contentOffset = isHorizontal
                    ? CGPoint(x: target, y: 0)
                    : CGPoint(x: 0, y: target)
            }
        }

        guard !isAnimatingMutation else { return }
        guard pitch > 0, thumbCount > 0 else { return }

        let raw = progressForOffset(currentMainOffset)
        let clamped = max(0, min(CGFloat(thumbCount - 1), raw))
        // 回転中など UIKit 由来の bounds/contentOffset 変化で progress を書き換えると
        // mirror 経由で main の currentPageIndex まで壊れるので、ユーザー操作起因の
        // スクロール時のみ progress / delegate を更新する。
        let isUserDriven = isTracking || isDragging || isDecelerating
        if isUserDriven, clamped != progress {
            progress = clamped
            stripDelegate?.stripView(self, didUpdateProgress: clamped)
        }

        let frames = computeFrames(thumbCount: thumbCount, progress: clamped)

        let visibleMin = currentMainOffset - selectedThumbnailLength
        let visibleMax = currentMainOffset + mainExtent + selectedThumbnailLength
        var visibleIndices: [Int] = []
        for i in 0..<thumbCount {
            guard let f = frames[i] else { continue }
            let frameMin = isHorizontal ? f.minX : f.minY
            let frameMax = isHorizontal ? f.maxX : f.maxY
            if frameMax >= visibleMin && frameMin <= visibleMax {
                visibleIndices.append(i)
            }
        }
        let keep = Set(visibleIndices)

        for (idx, view) in mountedThumbs where !keep.contains(idx) {
            view.removeFromSuperview()
            mountedThumbs.removeValue(forKey: idx)
        }

        for i in visibleIndices where mountedThumbs[i] == nil {
            guard let ds = thumbnailDataSource else { continue }
            let view = ds.stripView(self, thumbnailViewAt: i)
            view.transform = .identity
            addSubview(view)
            mountedThumbs[i] = view
        }

        for i in visibleIndices {
            if let view = mountedThumbs[i], let f = frames[i] {
                if view.frame != f {
                    view.frame = f
                }
            }
        }

        let centerIndex = Int(clamped.rounded())
        if let centerThumb = mountedThumbs[centerIndex] {
            bringSubviewToFront(centerThumb)
        }
    }
}

@MainActor
private final class ScrollDelegateProxy: NSObject, UIScrollViewDelegate {
    weak var owner: ScrubberStripView?

    func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                   withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        owner?.handleEndDragging(targetContentOffset: targetContentOffset)
    }
}
