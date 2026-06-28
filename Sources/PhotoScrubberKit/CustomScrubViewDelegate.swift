import UIKit

/// ``CustomScrubView`` の進行度・表示ページ変化を受け取るデリゲート。全メソッドが任意実装。
@MainActor
public protocol CustomScrubViewDelegate: AnyObject {
    /// スクロールで進行度が変化したとき呼ばれる。`progress` は `0...(pageCount - 1)` の連続値。
    func scrubView(_ scrubView: CustomScrubView, didUpdateProgress progress: CGFloat)
    /// 表示中のページが別の index に切り替わったとき呼ばれる。
    func scrubView(_ scrubView: CustomScrubView, didChangeVisiblePage index: Int)
}

public extension CustomScrubViewDelegate {
    func scrubView(_ scrubView: CustomScrubView, didUpdateProgress progress: CGFloat) {}
    func scrubView(_ scrubView: CustomScrubView, didChangeVisiblePage index: Int) {}
}
