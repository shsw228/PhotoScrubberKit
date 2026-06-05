import SwiftUI
import UIKit
import OSLog
import PhotoScrubberKit

private let log = Logger(subsystem: "dev.hume.PhotoScrubberKitPlayground", category: "scrubber")

struct PhotoScrubberRepresentable: UIViewRepresentable {
    let itemSeeds: [Int]
    let stripPosition: PhotoScrubberView.StripPosition
    @Binding var progress: CGFloat
    @Binding var currentItem: Int
    @Binding var deleteRequest: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(itemSeeds: itemSeeds, progress: $progress, currentItem: $currentItem)
    }

    func makeUIView(context: Context) -> PhotoScrubberView {
        let view = PhotoScrubberView()
        view.backgroundColor = .black
        view.stripThickness = 88
        view.stripPosition = stripPosition
        view.stripView.selectedThumbnailLength = 56
        view.stripView.unselectedThumbnailLength = 16
        view.stripView.thumbnailBreadth = 56
        view.stripView.thumbnailGap = 4
        view.stripView.selectedThumbnailPadding = 16
        view.coupling.dataSource = context.coordinator
        view.coupling.delegate = context.coordinator
        view.coupling.prefetcher = context.coordinator
        Task {
            view.coupling.reloadData()
        }
        return view
    }

    func updateUIView(_ uiView: PhotoScrubberView, context: Context) {
        if uiView.stripPosition != stripPosition {
            uiView.stripPosition = stripPosition
        }

        if let index = deleteRequest {
            context.coordinator.itemSeeds = itemSeeds
            Task {
                await uiView.coupling.deleteItem(at: index, animated: true)
                deleteRequest = nil
            }
            return
        }

        let old = context.coordinator.itemSeeds
        guard old != itemSeeds else { return }

        if itemSeeds.count > old.count, itemSeeds.starts(with: old) {
            let delta = itemSeeds.count - old.count
            context.coordinator.itemSeeds = itemSeeds
            for _ in 0..<delta {
                uiView.coupling.appendItem()
            }
            return
        }

        context.coordinator.itemSeeds = itemSeeds
        uiView.coupling.reloadData()
    }

    final class Coordinator: NSObject, PhotoScrubberDataSource, PhotoScrubberDelegate, PhotoScrubberPrefetching {
        var itemSeeds: [Int]
        @Binding var progress: CGFloat
        @Binding var currentItem: Int

        private var mainImageCache: [Int: UIImage] = [:]
        private var thumbImageCache: [Int: UIImage] = [:]
        private var inflightMain: [Int: Task<UIImage?, Never>] = [:]
        private var inflightThumb: [Int: Task<UIImage?, Never>] = [:]

        init(itemSeeds: [Int], progress: Binding<CGFloat>, currentItem: Binding<Int>) {
            self.itemSeeds = itemSeeds
            self._progress = progress
            self._currentItem = currentItem
        }

        func numberOfItems(in coupling: PhotoScrubberCoupling) -> Int { itemSeeds.count }

        func photoScrubber(_ coupling: PhotoScrubberCoupling, mainViewAt index: Int) -> UIView {
            let seed = itemSeeds[index]
            let cached = mainImageCache[seed] != nil
            log.info("📷 mainViewAt index=\(index) seed=\(seed) cached=\(cached)")
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.backgroundColor = .black
            Task { [weak imageView, weak self] in
                guard let self else { return }
                imageView?.image = await self.loadMainImage(seed: seed)
            }
            return imageView
        }

        func photoScrubber(_ coupling: PhotoScrubberCoupling, thumbnailViewAt index: Int) -> UIView {
            let seed = itemSeeds[index]
            let cached = thumbImageCache[seed] != nil
            log.info("🖼  thumbViewAt index=\(index) seed=\(seed) cached=\(cached)")
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.backgroundColor = UIColor(white: 0.15, alpha: 1)
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 4
            Task { [weak imageView, weak self] in
                guard let self else { return }
                imageView?.image = await self.loadThumbImage(seed: seed)
            }
            return imageView
        }

        func photoScrubber(_ coupling: PhotoScrubberCoupling, didUpdateProgress progress: CGFloat) {
            Task { [weak self] in
                self?.progress = progress
            }
        }

        func photoScrubber(_ coupling: PhotoScrubberCoupling, didChangeVisibleItem index: Int) {
            Task { [weak self] in
                self?.currentItem = index
            }
        }

        func photoScrubber(_ coupling: PhotoScrubberCoupling, prefetchItemsFor indices: [Int], kind: PhotoScrubberItemKind) {
            let seeds = indices.compactMap { itemSeeds.indices.contains($0) ? itemSeeds[$0] : nil }
            log.notice("⬇️  prefetch kind=\(String(describing: kind)) indices=\(indices) seeds=\(seeds)")
            for seed in seeds {
                switch kind {
                case .main:
                    Task { [weak self] in _ = await self?.loadMainImage(seed: seed) }
                case .thumbnail:
                    Task { [weak self] in _ = await self?.loadThumbImage(seed: seed) }
                }
            }
        }

        private func loadMainImage(seed: Int) async -> UIImage? {
            if let cached = mainImageCache[seed] { return cached }
            if let existing = inflightMain[seed] {
                log.debug("⏸  main reuse-inflight seed=\(seed)")
                return await existing.value
            }
            let task = Task<UIImage?, Never> {
                guard let url = URL(string: "https://picsum.photos/seed/scrubkit-\(seed)/800/1200") else { return nil }
                log.debug("🌐 main GET seed=\(seed)")
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let image = UIImage(data: data)
                    if let image { log.debug("✅ main loaded seed=\(seed)") }
                    return image
                } catch {
                    log.error("❌ main failed seed=\(seed) error=\(error.localizedDescription)")
                    return nil
                }
            }
            inflightMain[seed] = task
            let image = await task.value
            inflightMain[seed] = nil
            if let image { mainImageCache[seed] = image }
            return image
        }

        private func loadThumbImage(seed: Int) async -> UIImage? {
            if let cached = thumbImageCache[seed] { return cached }
            if let existing = inflightThumb[seed] {
                log.debug("⏸  thumb reuse-inflight seed=\(seed)")
                return await existing.value
            }
            let task = Task<UIImage?, Never> {
                guard let url = URL(string: "https://picsum.photos/seed/scrubkit-\(seed)/120/120") else { return nil }
                log.debug("🌐 thumb GET seed=\(seed)")
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let image = UIImage(data: data)
                    if let image { log.debug("✅ thumb loaded seed=\(seed)") }
                    return image
                } catch {
                    log.error("❌ thumb failed seed=\(seed) error=\(error.localizedDescription)")
                    return nil
                }
            }
            inflightThumb[seed] = task
            let image = await task.value
            inflightThumb[seed] = nil
            if let image { thumbImageCache[seed] = image }
            return image
        }
    }
}
