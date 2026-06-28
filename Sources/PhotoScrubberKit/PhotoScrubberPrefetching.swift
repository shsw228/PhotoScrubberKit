import UIKit

/// prefetch 依頼がメイン・サムネイルどちらの view に対するものかを表す。
public enum PhotoScrubberItemKind: Sendable {
    /// メイン (paging) 側の view。
    case main
    /// サムネイル帯の view。
    case thumbnail
}

/// PhotoScrubberView が「もうすぐ画面に入ってきそうな item」の事前ロードを
/// caller に依頼するための protocol。`coupling.prefetcher` に設定する。
///
/// UICollectionView の標準 prefetch とは違い、library 側のヒューリスティック
/// (`didChangeVisibleItem` 発火時に現在 index ± N) で indices を組み立てて
/// 通知する。caller 側で expansion や cancel を制御してよい。
@MainActor
public protocol PhotoScrubberPrefetching: AnyObject {
    /// 周辺 item の事前ロードを依頼する。
    ///
    /// - Parameters:
    ///   - coupling: 依頼元のスクラバー。
    ///   - indices: 事前ロード対象の item index 群（現在 index ± radius、現在 index は除く）。
    ///   - kind: 依頼対象がメインかサムネイルか。半径は
    ///     ``PhotoScrubberCoupling/mainPrefetchRadius`` /
    ///     ``PhotoScrubberCoupling/thumbnailPrefetchRadius`` で調整する。
    func photoScrubber(_ coupling: PhotoScrubberCoupling,
                       prefetchItemsFor indices: [Int],
                       kind: PhotoScrubberItemKind)
}
