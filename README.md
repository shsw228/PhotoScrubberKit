# PhotoScrubberKit

UIKit 製の **Apple Photos.app スクラバー風 UI** を public API のみで再現する Swift Package。

## 背景・動機
- 元ネタ: [Seb Vidal のツイート](https://x.com/SebJVidal/status/2062635133069308264) と引用元 @ertembiyik
- 内容: `UIPageViewController` は内部で `_UIQueuingScrollView` という非公開 `UIScrollView` サブクラスを使い、常に最大 3 ビューだけをヒエラルキーに保持しつつ無限スクロール風の体験を作っている。`_visibleView` / `_scrollView` を KVO することで Photos のスクラバー風カスタムアニメーションが駆動できる
- そのまま使うと private API 依存になるため、**同じ体験を public API だけで作る** ことが目的
- ターゲットユースケース: Photos.app のように「上に大きな写真ページ、下にサムネイル帯、両者を進行度で連動」させたいシナリオ

## 構成方針 — 3 層分離
| 層 | クラス | 役割 |
|---|---|---|
| 下層 | `CustomScrubView` / `ScrubberStripView` | 単独で使える UIKit View。それぞれ自分の dataSource / delegate / progress を持つ |
| 中層 | `PhotoScrubberCoupling` | 上の 2 View を双方向結合する pure オブジェクト。レイアウト無関心 |
| 上層 | `PhotoScrubberView` | Coupling を内包する薄い UIView。`stripPosition` でデフォルトレイアウトを提供 |

- レイアウトと結合ロジックを分離しているので、配置の自由度が高い:
  - **既定 (UIKit シンプル)**: `PhotoScrubberView` を使う + `stripPosition` で top/bottom/floatingTop/floatingBottom 切替
  - **UIKit カスタム配置**: `PhotoScrubberCoupling` を直接インスタンス化し、`coupling.scrubView` / `coupling.stripView` を任意の親 View に好きな制約で配置
  - **SwiftUI 独自配置**: `@State` で coupling を保持して、2 つの `UIViewRepresentable` でそれぞれ wrap し、ZStack / VStack / HStack 自由に組む
- UIKit 完結、有限ページのみ
- ページスナップ系（メイン側）+ 最寄サムネスナップ系（ストリップ側）を組み合わせ、Photos と同等の体験

## 公開 API

### 主要型
- `CustomScrubView: UIScrollView` — ページング ScrollView (`progress` KVO 可能、`visibleView`、3 ビュー recycling、横/縦切替)
- `CustomScrubViewController: UIViewController` — 上記の薄いコンテナ
- `ScrubberStripView: UIScrollView` — サムネを軸方向に並べた帯。`axis: ScrubAxis` で横/縦切替。中央セルは `selectedThumbnailLength × thumbnailBreadth`（正方形）、両側は `unselectedThumbnailLength × thumbnailBreadth`（軸に垂直方向が長い長方形）で、距離に応じて length を線形補間（Totteco 風 stride 補間）。中央寄り contentInset、指離し時に最寄サムネへスナップ（`snapsToNearestThumbnail` 既定 true）、サムネタップで最寄りサムネへアニメーションスクロール
- `PhotoScrubberCoupling` — メイン + ストリップを双方向結合する pure オブジェクト。レイアウト無関心
- `PhotoScrubberView: UIView` — Coupling 内包の薄い UIView。`stripPosition` で配置を選択:
  - 横ストリップ: `.top` / `.bottom` / `.floatingTop` / `.floatingBottom`
  - 縦ストリップ: `.leading` / `.trailing` / `.floatingLeading` / `.floatingTrailing`
  - `stripPosition` のセッターが自動で `stripView.axis` を `.horizontal` / `.vertical` に同期する
  - 厚みは axis 非依存の `stripThickness` で指定
- `ScrubAxis` — `.horizontal` / `.vertical` (`CustomScrubView` 用)

### データソース・デリゲート
- `CustomScrubViewDataSource` / `CustomScrubViewDelegate`
- `ScrubberThumbnailDataSource` / `ScrubberStripViewDelegate`
- `PhotoScrubberDataSource` / `PhotoScrubberDelegate` — メイン View とサムネを **別経路で** 提供

```swift
@MainActor
public protocol PhotoScrubberDataSource: AnyObject {
    func numberOfItems(in coupling: PhotoScrubberCoupling) -> Int
    func photoScrubber(_ coupling: PhotoScrubberCoupling, mainViewAt index: Int) -> UIView
    func photoScrubber(_ coupling: PhotoScrubberCoupling, thumbnailViewAt index: Int) -> UIView
}
```

### カスタム配置のサンプル

**UIKit で float**: `PhotoScrubberView` の `stripPosition = .floatingBottom` で完結。

**UIKit で完全カスタム**:
```swift
let coupling = PhotoScrubberCoupling()
coupling.dataSource = self
view.addSubview(coupling.scrubView)
view.addSubview(coupling.stripView)
// 任意の Auto Layout / frame で配置
coupling.reloadData()
```

**SwiftUI で完全カスタム**:
```swift
struct MyView: View {
    @State private var coupling = PhotoScrubberCoupling()  // class なので参照のみ
    var body: some View {
        ZStack {
            UIViewWrap(view: coupling.scrubView).ignoresSafeArea()
            VStack {
                Spacer()
                UIViewWrap(view: coupling.stripView)
                    .frame(height: 88)
                    .padding(.bottom, 40)
            }
        }
    }
}

struct UIViewWrap: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
```

### サムネ幅 + 中央 padding の補間（Totteco 風 stride 補間）
- **セル幅**: `width(i, p) = lerp(unselectedThumbnailWidth, selectedThumbnailWidth, max(0, 1 - |i - p|))`
  - 中央 (`|i - p| = 0`) で `selectedThumbnailWidth`（正方形）、1 pitch 以上離れた所で `unselectedThumbnailWidth`（縦長長方形）、中間は線形補間
- **セル間 gap**: `gap_after(i, p) = thumbnailGap + selectedThumbnailPadding * max(0, 1 - |i + 0.5 - p|)`
  - midpoint (= `i + 0.5`) の中央寄り度に応じて gap を追加で広げる → 中央セルの左右が広く padding を取った Photos / Totteco 風の見た目
  - midpoint 基準にすると、p が k と k+1 の中間でも gap が膨らみ続け、滑らかな遷移になる
- **contentSize の安定性**:
  - 幅は線形補間の不変量で常に `selected + (N-1)·unselected` で一定
  - midpoint proximity の総和も 1 で一定 → 中央付近 gap の追加分合計も `selectedThumbnailPadding` で一定（境界付近で 0.5×になる程度の小さな揺れあり）
  - `contentSize.width = selectedThumbnailWidth + (N-1)·pitch + selectedThumbnailPadding` を最大値で固定（境界ではわずかにバウンス余地が出るが許容）
- progress ↔ contentOffset.x は `pitch = unselectedThumbnailWidth + thumbnailGap` を単位とした **線形近似** を使用。中央 padding 由来の小さな非線形ズレ（最大 `selectedThumbnailPadding/2`）は実用上問題にならない範囲で無視

### 双方向結合の安全装置
- `PhotoScrubberView` 内で `isProgrammaticUpdate` フラグを持ち、片方→もう片方への反映時にフィードバックループを抑止
- 反映時は `layoutIfNeeded()` で同期 layout を強制し、フラグ有効期間中に内部 delegate を発火させてフラグ抑止を効かせる

## ディレクトリ構成
```
PhotoScrubberKit/
├── README.md
├── Package.swift
├── Sources/PhotoScrubberKit/
│   ├── CustomScrubView.swift
│   ├── CustomScrubViewController.swift
│   ├── CustomScrubViewDataSource.swift
│   ├── CustomScrubViewDelegate.swift
│   ├── ScrubberStripView.swift         (Thumbnail dataSource / delegate / 内部 UIScrollViewDelegate proxy を同居)
│   ├── PhotoScrubberCoupling.swift     (双方向結合の pure オブジェクト + PhotoScrubber dataSource / delegate を同居)
│   └── PhotoScrubberView.swift         (Coupling を内包したデフォルト配置の薄い UIView)
├── Tests/PhotoScrubberKitTests/
│   └── CustomScrubViewTests.swift
└── PhotoScrubberKitPlayground.swiftpm/
    ├── Package.swift                   (swift-tools-version: 6.2, defaultIsolation MainActor)
    └── Sources/AppModule/
        ├── PhotoScrubberKitPlaygroundApp.swift
        ├── ContentView.swift
        └── PhotoScrubberRepresentable.swift  (PhotoScrubberView の SwiftUI ラップ)
```

## 動作確認の手順
1. Xcode で `PhotoScrubberKitPlayground.swiftpm` をダブルクリックで開く
2. iOS シミュレータ（または実機）を選んで Run
3. 画面上で:
   - `picsum.photos` から大画像 (800x1200) とサムネ (120x120) を 12 枚ずつ取得（要ネット接続）
   - 上部のオーバーレイに `item X / 11   progress 0.xxx` が連続更新
   - メイン View をスワイプ → 下のストリップが追従、サムネ拡大が中央に流れる
   - ストリップをスクラブ → メイン View が同じく追従、ページ間も連続的に表示
   - ストリップは慣性 + バウンスのみ（スナップなし）でメインは isPagingEnabled の指離しスナップあり、という非対称が Photos の体感に近い
4. `.swiftpm` は `..` のローカル Swift Package を `.package(name: "PhotoScrubberKit", path: "../")` で参照。iPad Swift Playgrounds は local path 非対応なので、その用途には git 依存に差し替えが必要

## 現状
- Photos スクラバーの最小機能（双方向結合、サムネ中央拡大、非対称スナップ）まで実装
- まだ実機での体感確認はしていない

## 次の手
- [ ] 実機 / シミュレータで Playground を走らせて挙動を体感
- [ ] サムネ間隔・stripHeight・selectedThumbnailPadding の調整（実機での見栄え合わせ）
- [ ] 任意位置への挿入 (`insertItem(at:animated:)`) の追加
- [ ] メイン側の `isPagingEnabled` を切り替えて「メインも非スナップ」モードを試す
- [ ] サムネのデータソースが画像ロードを伴う場合の `prefetch` API
- [ ] テスト追加: `PhotoScrubberView` の双方向結合・delete/append・tap-to-scroll
- [ ] 独立リポジトリ化と SPM 公開

## 設計上の判断メモ
- **dataSource は UIView を返す**: Photos スクラバー的用途では UIView で十分。UIViewController を返す API は child VC 管理の責務が乗るので、必要になってから別 API として追加する
- **3 ビュー保持の根拠**: メイン側は表示中ページとその隣接（スワイプで即見えるもの）だけが必要
- **ストリップは visible+buffer 全 mount**: 帯状に見える分は全部出していないとサムネの中央寄せ拡大の見え方が破綻するため
- **UIScrollView.delegate を握らない理由**: 外部ユーザーが scrollViewDidScroll などを使う余地を残すため。スクロール進行は `layoutSubviews` で追う
- **メインとストリップの指離し時挙動**: メインは `isPagingEnabled` で整数ページへスナップ、ストリップは `scrollViewWillEndDragging` で target を最寄りサムネへ丸めることでスナップ。Photos の指離し → 最寄り選択の挙動に合わせている
- **ScrubberStripView は内部で `UIScrollViewDelegate` を握る**: スナップに `scrollViewWillEndDragging` が必要なため。外部ユーザーがスクロール情報を取りたい場合は `ScrubberStripViewDelegate` (= `didUpdateProgress`) を使う想定
- **`@MainActor` 化された protocol**: UIKit に閉じた dataSource / delegate のため意味的に MainActor 隔離が正しい

## 関連
- [[../music-visualizer/README|Music Visualizer]] — 進行度連動 UI が必要になるかもしれない隣接案件
