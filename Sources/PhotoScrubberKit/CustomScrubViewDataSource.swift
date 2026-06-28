import UIKit

/// ``CustomScrubView`` にページ数と各ページの view を供給するデータソース。
///
/// ``PhotoScrubberCoupling`` 経由で使う場合は、代わりに
/// ``PhotoScrubberDataSource`` を実装する（本 protocol は内部で橋渡しされる）。
@MainActor
public protocol CustomScrubViewDataSource: AnyObject {
    /// ページ総数。
    func numberOfPages(in scrubView: CustomScrubView) -> Int
    /// `index` 番目のページに表示する view を返す。
    func scrubView(_ scrubView: CustomScrubView, viewForPageAt index: Int) -> UIView
}
