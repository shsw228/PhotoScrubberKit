# PhotoScrubberKit

UIKit 製の Apple Photos.app 風スクラバー UI（メイン画像 + サムネイル帯の双方向連動）を提供する Swift Package。
**レイアウトは呼び出し側の責務**。ライブラリは 2 つの UIView と結合ロジックを提供するだけ。

## Requirements
- iOS 16+
- Swift 5.9+

## Installation

```swift
.package(url: "https://github.com/shsw228/PhotoScrubberKit", from: "0.2.0")
```

## Usage

```swift
import PhotoScrubberKit

let coupling = PhotoScrubberCoupling()
coupling.dataSource = self
coupling.delegate = self      // optional
coupling.prefetcher = self    // optional

// SwiftUI 側で自由に配置
VStack {
    UIViewBridge(view: coupling.scrubView)         // メイン (paging)
    UIViewBridge(view: coupling.stripView)         // サムネ帯
        .frame(height: 96)
}

// floating したければ ZStack で重ねるだけ
ZStack(alignment: .bottom) {
    UIViewBridge(view: coupling.scrubView)
    UIViewBridge(view: coupling.stripView)
        .frame(height: 96).padding(.bottom, 24)
}

coupling.reloadData()
```

`PhotoScrubberDataSource` で `numberOfItems` / `mainViewAt` / `thumbnailViewAt` を返す。
`PhotoScrubberPrefetching` を実装すれば現在 ± N の周辺アイテムを fetch する hint が来る。

UIKit でそのまま使う場合は `coupling.scrubView` / `coupling.stripView` を `addSubview` して frame を組む。

## Demo

`PhotoScrubberKitPlayground.swiftpm` を Xcode で開いて実機/シミュレータで Run。SwiftUI で VStack/ZStack を切り替えるサンプル付き。

## License

MIT
