import UIKit

public final class PhotoScrubberView: UIView {

    public enum StripPosition: Sendable {
        case top
        case bottom
        case leading
        case trailing
        case floatingTop
        case floatingBottom
        case floatingLeading
        case floatingTrailing

        var axis: ScrubAxis {
            switch self {
            case .top, .bottom, .floatingTop, .floatingBottom:
                return .horizontal
            case .leading, .trailing, .floatingLeading, .floatingTrailing:
                return .vertical
            }
        }

        var isFloating: Bool {
            switch self {
            case .floatingTop, .floatingBottom, .floatingLeading, .floatingTrailing:
                return true
            case .top, .bottom, .leading, .trailing:
                return false
            }
        }
    }

    public let coupling: PhotoScrubberCoupling

    public var stripPosition: StripPosition = .bottom {
        didSet {
            guard oldValue != stripPosition else { return }
            coupling.stripView.axis = stripPosition.axis
            setNeedsLayout()
        }
    }

    public var stripThickness: CGFloat = 80 {
        didSet {
            guard oldValue != stripThickness else { return }
            setNeedsLayout()
        }
    }

    public var scrubView: CustomScrubView { coupling.scrubView }
    public var stripView: ScrubberStripView { coupling.stripView }

    public override init(frame: CGRect) {
        self.coupling = PhotoScrubberCoupling()
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        self.coupling = PhotoScrubberCoupling()
        super.init(coder: coder)
        commonInit()
    }

    public init(coupling: PhotoScrubberCoupling) {
        self.coupling = coupling
        super.init(frame: .zero)
        commonInit()
    }

    private func commonInit() {
        coupling.stripView.axis = stripPosition.axis
        addSubview(scrubView)
        addSubview(stripView)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        let stripFrame: CGRect
        let scrubFrame: CGRect

        switch stripPosition {
        case .top:
            stripFrame = CGRect(x: 0, y: 0,
                                width: bounds.width, height: stripThickness)
            scrubFrame = CGRect(x: 0, y: stripThickness,
                                width: bounds.width,
                                height: max(0, bounds.height - stripThickness))
        case .bottom:
            scrubFrame = CGRect(x: 0, y: 0,
                                width: bounds.width,
                                height: max(0, bounds.height - stripThickness))
            stripFrame = CGRect(x: 0, y: bounds.height - stripThickness,
                                width: bounds.width, height: stripThickness)
        case .leading:
            stripFrame = CGRect(x: 0, y: 0,
                                width: stripThickness, height: bounds.height)
            scrubFrame = CGRect(x: stripThickness, y: 0,
                                width: max(0, bounds.width - stripThickness),
                                height: bounds.height)
        case .trailing:
            scrubFrame = CGRect(x: 0, y: 0,
                                width: max(0, bounds.width - stripThickness),
                                height: bounds.height)
            stripFrame = CGRect(x: bounds.width - stripThickness, y: 0,
                                width: stripThickness, height: bounds.height)
        case .floatingTop:
            scrubFrame = bounds
            stripFrame = CGRect(x: 0, y: 0,
                                width: bounds.width, height: stripThickness)
        case .floatingBottom:
            scrubFrame = bounds
            stripFrame = CGRect(x: 0, y: bounds.height - stripThickness,
                                width: bounds.width, height: stripThickness)
        case .floatingLeading:
            scrubFrame = bounds
            stripFrame = CGRect(x: 0, y: 0,
                                width: stripThickness, height: bounds.height)
        case .floatingTrailing:
            scrubFrame = bounds
            stripFrame = CGRect(x: bounds.width - stripThickness, y: 0,
                                width: stripThickness, height: bounds.height)
        }

        if scrubView.frame != scrubFrame { scrubView.frame = scrubFrame }
        if stripView.frame != stripFrame { stripView.frame = stripFrame }

        if stripPosition.isFloating {
            bringSubviewToFront(stripView)
        }
    }
}
