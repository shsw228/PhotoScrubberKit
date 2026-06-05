import UIKit

@MainActor
public protocol CustomScrubViewDelegate: AnyObject {
    func scrubView(_ scrubView: CustomScrubView, didUpdateProgress progress: CGFloat)
    func scrubView(_ scrubView: CustomScrubView, didChangeVisiblePage index: Int)
}

public extension CustomScrubViewDelegate {
    func scrubView(_ scrubView: CustomScrubView, didUpdateProgress progress: CGFloat) {}
    func scrubView(_ scrubView: CustomScrubView, didChangeVisiblePage index: Int) {}
}
