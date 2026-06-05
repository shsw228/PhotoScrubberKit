import UIKit

@MainActor
public protocol CustomScrubViewDataSource: AnyObject {
    func numberOfPages(in scrubView: CustomScrubView) -> Int
    func scrubView(_ scrubView: CustomScrubView, viewForPageAt index: Int) -> UIView
}
