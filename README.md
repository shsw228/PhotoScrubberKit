# PhotoScrubberKit

UIKit 製の Apple Photos.app 風スクラバー UI（メイン画像 + サムネイル帯の双方向連動）を提供する Swift Package。

## Requirements
- iOS 16+
- Swift 5.9+

## Installation

```swift
.package(url: "https://github.com/shsw228/PhotoScrubberKit", from: "0.1.0")
```

## Usage

```swift
import PhotoScrubberKit

let scrubber = PhotoScrubberView()
scrubber.stripPosition = .bottom   // .top / .leading / .trailing / .floating*
scrubber.coupling.dataSource = self
scrubber.coupling.reloadData()
```

`PhotoScrubberDataSource` で `numberOfItems` / `mainViewAt` / `thumbnailViewAt` を返す。

カスタムレイアウト（SwiftUI 等）で組みたい場合は `PhotoScrubberCoupling` を直接インスタンス化して `scrubView` / `stripView` を好きな場所に配置する。

## Demo

`PhotoScrubberKitPlayground.swiftpm` を Xcode で開いて実機/シミュレータで Run。

## License

MIT
