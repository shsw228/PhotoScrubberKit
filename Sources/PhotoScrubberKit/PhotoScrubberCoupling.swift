import UIKit

@MainActor
public protocol PhotoScrubberDataSource: AnyObject {
    func numberOfItems(in coupling: PhotoScrubberCoupling) -> Int
    func photoScrubber(_ coupling: PhotoScrubberCoupling, mainViewAt index: Int) -> UIView
    func photoScrubber(_ coupling: PhotoScrubberCoupling, thumbnailViewAt index: Int) -> UIView
}

@MainActor
public protocol PhotoScrubberDelegate: AnyObject {
    func photoScrubber(_ coupling: PhotoScrubberCoupling, didUpdateProgress progress: CGFloat)
    func photoScrubber(_ coupling: PhotoScrubberCoupling, didChangeVisibleItem index: Int)
}

public extension PhotoScrubberDelegate {
    func photoScrubber(_ coupling: PhotoScrubberCoupling, didUpdateProgress progress: CGFloat) {}
    func photoScrubber(_ coupling: PhotoScrubberCoupling, didChangeVisibleItem index: Int) {}
}

@MainActor
public final class PhotoScrubberCoupling {

    public let scrubView: CustomScrubView
    public let stripView: ScrubberStripView

    public weak var dataSource: (any PhotoScrubberDataSource)?
    public weak var delegate: (any PhotoScrubberDelegate)?
    public weak var prefetcher: (any PhotoScrubberPrefetching)?

    /// `didChangeVisibleItem` 発火時に現在 index ± `mainPrefetchRadius` を main 用 prefetch として通知。
    public var mainPrefetchRadius: Int = 2

    /// 同上、thumbnail 用。
    public var thumbnailPrefetchRadius: Int = 5

    private let forwardingProxy = ForwardingProxy()
    private var isProgrammaticUpdate = false

    public init(scrubView: CustomScrubView? = nil,
                stripView: ScrubberStripView? = nil) {
        self.scrubView = scrubView ?? CustomScrubView()
        self.stripView = stripView ?? ScrubberStripView()
        forwardingProxy.owner = self
        self.scrubView.pageDataSource = forwardingProxy
        self.scrubView.pageDelegate = forwardingProxy
        self.stripView.thumbnailDataSource = forwardingProxy
        self.stripView.stripDelegate = forwardingProxy
    }

    public func reloadData() {
        scrubView.reloadData()
        stripView.reloadData()
    }

    public func deleteItem(at index: Int, animated: Bool) async {
        isProgrammaticUpdate = true
        async let mainDone: Void = scrubView.deletePage(at: index, animated: animated)
        async let stripDone: Void = stripView.deleteThumbnail(at: index, animated: animated)
        _ = await (mainDone, stripDone)
        isProgrammaticUpdate = false
    }

    public func appendItem() {
        scrubView.appendPage()
        stripView.appendThumbnail()
    }

    fileprivate func mainDidUpdateProgress(_ progress: CGFloat) {
        delegate?.photoScrubber(self, didUpdateProgress: progress)
        guard !isProgrammaticUpdate else { return }
        isProgrammaticUpdate = true
        stripView.setProgress(progress, animated: false)
        stripView.layoutIfNeeded()
        isProgrammaticUpdate = false
    }

    fileprivate func mainDidChangeVisibleItem(_ index: Int) {
        delegate?.photoScrubber(self, didChangeVisibleItem: index)
        firePrefetch(around: index)
    }

    private func firePrefetch(around index: Int) {
        guard let prefetcher else { return }
        let count = dataSource?.numberOfItems(in: self) ?? 0
        guard count > 0 else { return }
        let mainIndices = prefetchIndices(around: index, radius: mainPrefetchRadius, count: count)
        if !mainIndices.isEmpty {
            prefetcher.photoScrubber(self, prefetchItemsFor: mainIndices, kind: .main)
        }
        let thumbIndices = prefetchIndices(around: index, radius: thumbnailPrefetchRadius, count: count)
        if !thumbIndices.isEmpty {
            prefetcher.photoScrubber(self, prefetchItemsFor: thumbIndices, kind: .thumbnail)
        }
    }

    private func prefetchIndices(around index: Int, radius: Int, count: Int) -> [Int] {
        guard radius > 0, count > 0 else { return [] }
        let start = max(0, index - radius)
        let end = min(count - 1, index + radius)
        guard start <= end else { return [] }
        return Array(start...end).filter { $0 != index }
    }

    fileprivate func stripDidUpdateProgress(_ progress: CGFloat) {
        guard !isProgrammaticUpdate else { return }
        isProgrammaticUpdate = true
        scrubView.setProgress(progress, animated: false)
        scrubView.layoutIfNeeded()
        isProgrammaticUpdate = false
    }
}

// 4 つの内部 protocol への conformance を public な PhotoScrubberCoupling から
// 引き剥がすための private adapter。
// SwiftUI の `UIViewRepresentable.Coordinator` とは別物で、PhotoScrubberKit 内部の実装詳細。
@MainActor
private final class ForwardingProxy: NSObject, CustomScrubViewDataSource, ScrubberThumbnailDataSource, CustomScrubViewDelegate, ScrubberStripViewDelegate {

    weak var owner: PhotoScrubberCoupling?

    func numberOfPages(in scrubView: CustomScrubView) -> Int {
        guard let owner else { return 0 }
        return owner.dataSource?.numberOfItems(in: owner) ?? 0
    }

    func scrubView(_ scrubView: CustomScrubView, viewForPageAt index: Int) -> UIView {
        guard let owner else { return UIView() }
        return owner.dataSource?.photoScrubber(owner, mainViewAt: index) ?? UIView()
    }

    func numberOfThumbnails(in stripView: ScrubberStripView) -> Int {
        guard let owner else { return 0 }
        return owner.dataSource?.numberOfItems(in: owner) ?? 0
    }

    func stripView(_ stripView: ScrubberStripView, thumbnailViewAt index: Int) -> UIView {
        guard let owner else { return UIView() }
        return owner.dataSource?.photoScrubber(owner, thumbnailViewAt: index) ?? UIView()
    }

    func scrubView(_ scrubView: CustomScrubView, didUpdateProgress progress: CGFloat) {
        owner?.mainDidUpdateProgress(progress)
    }

    func scrubView(_ scrubView: CustomScrubView, didChangeVisiblePage index: Int) {
        owner?.mainDidChangeVisibleItem(index)
    }

    func stripView(_ stripView: ScrubberStripView, didUpdateProgress progress: CGFloat) {
        owner?.stripDidUpdateProgress(progress)
    }
}
