import SwiftUI
import UIKit
import PhotoScrubberKit

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

    final class Coordinator: NSObject, PhotoScrubberDataSource, PhotoScrubberDelegate {
        var itemSeeds: [Int]
        @Binding var progress: CGFloat
        @Binding var currentItem: Int

        private var mainImageCache: [Int: UIImage] = [:]
        private var thumbImageCache: [Int: UIImage] = [:]

        init(itemSeeds: [Int], progress: Binding<CGFloat>, currentItem: Binding<Int>) {
            self.itemSeeds = itemSeeds
            self._progress = progress
            self._currentItem = currentItem
        }

        func numberOfItems(in coupling: PhotoScrubberCoupling) -> Int { itemSeeds.count }

        func photoScrubber(_ coupling: PhotoScrubberCoupling, mainViewAt index: Int) -> UIView {
            let seed = itemSeeds[index]
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

        private func loadMainImage(seed: Int) async -> UIImage? {
            if let cached = mainImageCache[seed] { return cached }
            guard let url = URL(string: "https://picsum.photos/seed/scrubkit-\(seed)/800/1200") else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let image = UIImage(data: data)
                if let image { mainImageCache[seed] = image }
                return image
            } catch {
                return nil
            }
        }

        private func loadThumbImage(seed: Int) async -> UIImage? {
            if let cached = thumbImageCache[seed] { return cached }
            guard let url = URL(string: "https://picsum.photos/seed/scrubkit-\(seed)/120/120") else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let image = UIImage(data: data)
                if let image { thumbImageCache[seed] = image }
                return image
            } catch {
                return nil
            }
        }
    }
}
