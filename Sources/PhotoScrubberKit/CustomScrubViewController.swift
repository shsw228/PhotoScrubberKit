import UIKit

/// ``CustomScrubView`` を `view` 全体に敷いた、メイン単体用のコンテナ ViewController。
///
/// サムネイル帯との連動が不要で、メインのスクラブビューだけを画面に置きたいときに使う。
/// サムネイル連動が必要なら ``PhotoScrubberCoupling`` を使う。
open class CustomScrubViewController: UIViewController {

    /// 管理対象のスクラブビュー。`viewDidLoad` で `view` に敷き込まれる。
    public let scrubView: CustomScrubView

    /// 指定したスクロール軸でコンテナを生成する。
    /// - Parameter axis: スクラブの方向。既定は ``ScrubAxis/horizontal``。
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
