import SwiftUI
import UIKit

/// 既存の `UIView` インスタンスを SwiftUI ビュー階層に差し込むだけの薄いアダプタ。
/// `UIViewRepresentable.makeUIView` で新規生成せず、外で持ってる UIView を返す。
struct UIViewBridge<V: UIView>: UIViewRepresentable {
    let view: V
    func makeUIView(context: Context) -> V { view }
    func updateUIView(_ uiView: V, context: Context) {}
}
