import UIKit

/// ``PhotoScrubberCoupling`` にメイン画像／サムネイル両方のコンテンツを供給するデータソース。
///
/// メイン (``PhotoScrubberCoupling/scrubView``) とストリップ
/// (``PhotoScrubberCoupling/stripView``) は同じ item 数を共有する。両ビューの
/// `index` は常に同じ item を指す。
@MainActor
public protocol PhotoScrubberDataSource: AnyObject {
    /// スクラバーが表示する item 数。メイン・サムネイルで共通。
    func numberOfItems(in coupling: PhotoScrubberCoupling) -> Int
    /// メイン (paging) 側の `index` 番目に表示する view を返す。
    func photoScrubber(_ coupling: PhotoScrubberCoupling, mainViewAt index: Int) -> UIView
    /// サムネイル帯の `index` 番目に表示する view を返す。
    func photoScrubber(_ coupling: PhotoScrubberCoupling, thumbnailViewAt index: Int) -> UIView
}

/// スクラブ操作の進行・表示 item 変化を受け取るデリゲート。全メソッドが任意実装。
@MainActor
public protocol PhotoScrubberDelegate: AnyObject {
    /// メイン／ストリップいずれかのスクロールで進行度が変化したとき呼ばれる。
    ///
    /// `progress` は `0...(itemCount - 1)` の連続値（item index の小数表現）。
    func photoScrubber(_ coupling: PhotoScrubberCoupling, didUpdateProgress progress: CGFloat)
    /// 表示中の item が別の index に切り替わったとき呼ばれる。
    func photoScrubber(_ coupling: PhotoScrubberCoupling, didChangeVisibleItem index: Int)
}

public extension PhotoScrubberDelegate {
    func photoScrubber(_ coupling: PhotoScrubberCoupling, didUpdateProgress progress: CGFloat) {}
    func photoScrubber(_ coupling: PhotoScrubberCoupling, didChangeVisibleItem index: Int) {}
}

/// Apple Photos.app 風スクラバーの中核。メイン画像ビューとサムネイル帯を双方向に連動させる。
///
/// 一方をスクラブするともう一方が追従する。レイアウト（2 ビューの配置）は呼び出し側の責務で、
/// 本クラスは ``scrubView`` / ``stripView`` の 2 つの `UIView` と結合ロジックだけを提供する。
///
/// ## 使い方
/// 1. ``dataSource`` を設定し、必要なら ``delegate`` / ``prefetcher`` も設定する。
/// 2. ``scrubView`` と ``stripView`` を任意のレイアウトに配置する。
/// 3. ``reloadData()`` を呼ぶ。
///
/// データ変更は ``appendItem()`` / ``deleteItem(at:animated:)`` で両ビューへ一括反映される。
@MainActor
public final class PhotoScrubberCoupling {

    /// メイン (paging) のスクラブビュー。
    public let scrubView: CustomScrubView
    /// サムネイル帯のストリップビュー。
    public let stripView: ScrubberStripView

    /// item 数とメイン／サムネイル view を供給するデータソース。
    public weak var dataSource: (any PhotoScrubberDataSource)?
    /// 進行度・表示 item 変化の通知先（任意）。
    public weak var delegate: (any PhotoScrubberDelegate)?
    /// 周辺 item の事前ロード依頼先（任意）。
    public weak var prefetcher: (any PhotoScrubberPrefetching)?

    /// `didChangeVisibleItem` 発火時に現在 index ± `mainPrefetchRadius` を main 用 prefetch として通知。既定 `2`。
    public var mainPrefetchRadius: Int = 2

    /// 同上、thumbnail 用。既定 `5`。
    public var thumbnailPrefetchRadius: Int = 5

    private let forwardingProxy = ForwardingProxy()
    private var isProgrammaticUpdate = false

    /// スクラバーを生成する。
    ///
    /// - Parameters:
    ///   - scrubView: 既存のメインビューを使う場合に指定。`nil` なら内部で生成する。
    ///   - stripView: 既存のストリップビューを使う場合に指定。`nil` なら内部で生成する。
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

    /// データソースを読み直し、メイン・サムネイル両方を再構築する。
    public func reloadData() {
        scrubView.reloadData()
        stripView.reloadData()
    }

    /// 指定 index の item をメイン・サムネイル両方から削除する。
    ///
    /// 両ビューの削除を並行実行し、完了まで待つ。`async` なので呼び出し側で `await` する。
    /// - Parameters:
    ///   - index: 削除する item の index。
    ///   - animated: アニメーション付きで削除するか。
    public func deleteItem(at index: Int, animated: Bool) async {
        isProgrammaticUpdate = true
        async let mainDone: Void = scrubView.deletePage(at: index, animated: animated)
        async let stripDone: Void = stripView.deleteThumbnail(at: index, animated: animated)
        _ = await (mainDone, stripDone)
        isProgrammaticUpdate = false
    }

    /// 末尾に item を 1 つ追加し、メイン・サムネイル両方へ反映する。
    ///
    /// 追加後の item は ``dataSource`` から取得されるため、本メソッド呼び出し前に
    /// データソース側の件数を増やしておくこと。
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
