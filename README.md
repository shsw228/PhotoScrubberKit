# PhotoScrubberKit

UIKit 製の Apple Photos.app 風スクラバー UI（メイン画像 + サムネイル帯の双方向連動）を提供する Swift Package。
**レイアウトは呼び出し側の責務**。ライブラリは 2 つの UIView と結合ロジックを提供するだけ。

内部実装は `UICollectionView` ベース（メインは paging、ストリップは自作レイアウトで stride 補間）。

## Requirements
- iOS 16+
- Swift 5.9+

## Installation

```swift
.package(url: "https://github.com/shsw228/PhotoScrubberKit", from: "0.3.0")
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

coupling.apply(/* set up data */)
coupling.reloadData()
```

### dataSource
```swift
func numberOfItems(in coupling: PhotoScrubberCoupling) -> Int
func photoScrubber(_ coupling: PhotoScrubberCoupling, mainViewAt index: Int) -> UIView
func photoScrubber(_ coupling: PhotoScrubberCoupling, thumbnailViewAt index: Int) -> UIView
```

### delegate (optional)
```swift
func photoScrubber(_ coupling: PhotoScrubberCoupling, didUpdateProgress: CGFloat)
func photoScrubber(_ coupling: PhotoScrubberCoupling, didChangeVisibleItem: Int)
```

### prefetcher (optional)
`PhotoScrubberPrefetching` を実装すると、`didChangeVisibleItem` 発火時に現在 ± N の周辺アイテム index を `prefetchItemsFor:kind:` で受け取れる。kind は `.main` / `.thumbnail`。

```swift
func photoScrubber(_ coupling: PhotoScrubberCoupling,
                   prefetchItemsFor indices: [Int],
                   kind: PhotoScrubberItemKind)
```

範囲は `coupling.mainPrefetchRadius` (既定 2) / `coupling.thumbnailPrefetchRadius` (既定 5) で調整可能。

### UIKit でそのまま使う場合
`coupling.scrubView` / `coupling.stripView` を `addSubview` して frame を組む。

## Demo

`PhotoScrubberKitPlayground.swiftpm` を Xcode で開いて実機/シミュレータで Run。SwiftUI で VStack/ZStack を切り替えるサンプル付き。

## License

MIT
