import UIKit

public enum PhotoScrubberItemKind: Sendable {
    case main
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
    func photoScrubber(_ coupling: PhotoScrubberCoupling,
                       prefetchItemsFor indices: [Int],
                       kind: PhotoScrubberItemKind)
}
