import SwiftUI
import UIKit
import OSLog
import PhotoScrubberKit

private let log = Logger(subsystem: "dev.hume.PhotoScrubberKitPlayground", category: "scrubber")

@MainActor
final class ScrubberStore: NSObject, ObservableObject {

    @Published var itemSeeds: [Int] = Array(0..<12)
    @Published var progress: CGFloat = 0
    @Published var currentItem: Int = 0

    let coupling = PhotoScrubberCoupling()

    private var mainImageCache: [Int: UIImage] = [:]
    private var thumbImageCache: [Int: UIImage] = [:]
    private var inflightMain: [Int: Task<UIImage?, Never>] = [:]
    private var inflightThumb: [Int: Task<UIImage?, Never>] = [:]
    private var didSetup = false

    func setupIfNeeded() {
        guard !didSetup else { return }
        didSetup = true
        coupling.dataSource = self
        coupling.delegate = self
        coupling.prefetcher = self
        coupling.reloadData()
    }

    func deleteCurrent() {
        guard !itemSeeds.isEmpty else { return }
        let index = min(max(currentItem, 0), itemSeeds.count - 1)
        itemSeeds.remove(at: index)
        Task {
            await coupling.deleteItem(at: index, animated: true)
        }
    }

    func appendItem() {
        let next = (itemSeeds.max() ?? -1) + 1
        itemSeeds.append(next)
        coupling.appendItem()
    }
}

extension ScrubberStore: PhotoScrubberDataSource {
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
}

extension ScrubberStore: PhotoScrubberDelegate {
    func photoScrubber(_ coupling: PhotoScrubberCoupling, didUpdateProgress progress: CGFloat) {
        Task { [weak self] in self?.progress = progress }
    }

    func photoScrubber(_ coupling: PhotoScrubberCoupling, didChangeVisibleItem index: Int) {
        Task { [weak self] in self?.currentItem = index }
    }
}

extension ScrubberStore: PhotoScrubberPrefetching {
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
}

private extension ScrubberStore {
    func loadMainImage(seed: Int) async -> UIImage? {
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

    func loadThumbImage(seed: Int) async -> UIImage? {
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
