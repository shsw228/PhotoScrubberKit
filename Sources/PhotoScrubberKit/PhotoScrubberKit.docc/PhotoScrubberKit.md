# ``PhotoScrubberKit``

UIKit 製の Apple Photos.app 風スクラバー UI（メイン画像 + サムネイル帯の双方向連動）を提供する Swift Package。

## Overview

レイアウト（2 ビューの配置）は呼び出し側の責務で、ライブラリは 2 つの `UIView` と
結合ロジックだけを提供する。内部実装は `UICollectionView` ベースで、メインは paging、
ストリップは自作レイアウトで進行度に応じた stride 補間を行う。

典型的な使い方は ``PhotoScrubberCoupling`` にデータソースを設定し、
``PhotoScrubberCoupling/scrubView`` と ``PhotoScrubberCoupling/stripView`` を
任意のレイアウトに配置して ``PhotoScrubberCoupling/reloadData()`` を呼ぶだけ。

```swift
let coupling = PhotoScrubberCoupling()
coupling.dataSource = self
coupling.delegate = self      // optional
coupling.prefetcher = self    // optional
coupling.reloadData()
```

メイン単体でよい場合は ``CustomScrubView`` / ``CustomScrubViewController`` を、
サムネイル帯だけが必要なら ``ScrubberStripView`` を直接使える。

## Topics

### 連動コンテナ

- ``PhotoScrubberCoupling``
- ``PhotoScrubberDataSource``
- ``PhotoScrubberDelegate``
- ``PhotoScrubberPrefetching``
- ``PhotoScrubberItemKind``

### メインビュー

- ``CustomScrubView``
- ``CustomScrubViewController``
- ``CustomScrubViewDataSource``
- ``CustomScrubViewDelegate``

### サムネイル帯

- ``ScrubberStripView``
- ``ScrubberThumbnailDataSource``
- ``ScrubberStripViewDelegate``

### 共通

- ``ScrubAxis``
