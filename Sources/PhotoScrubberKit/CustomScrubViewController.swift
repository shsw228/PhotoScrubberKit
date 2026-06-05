import UIKit

open class CustomScrubViewController: UIViewController {

    public let scrubView: CustomScrubView

    public init(axis: ScrubAxis = .horizontal) {
        self.scrubView = CustomScrubView()
        super.init(nibName: nil, bundle: nil)
        self.scrubView.axis = axis
    }

    public required init?(coder: NSCoder) {
        self.scrubView = CustomScrubView()
        super.init(coder: coder)
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        scrubView.frame = view.bounds
        scrubView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scrubView)
    }
}
