import SwiftUI
import PhotoScrubberKit

struct ContentView: View {
    enum Edge: Hashable { case top, bottom, leading, trailing }

    @State private var itemSeeds: [Int] = Array(0..<12)
    @State private var progress: CGFloat = 0
    @State private var currentItem: Int = 0
    @State private var deleteRequest: Int? = nil
    @State private var stripEdge: Edge = .bottom
    @State private var stripFloating: Bool = false

    private var stripPosition: PhotoScrubberView.StripPosition {
        switch (stripEdge, stripFloating) {
        case (.top, false):      return .top
        case (.bottom, false):   return .bottom
        case (.leading, false):  return .leading
        case (.trailing, false): return .trailing
        case (.top, true):       return .floatingTop
        case (.bottom, true):    return .floatingBottom
        case (.leading, true):   return .floatingLeading
        case (.trailing, true):  return .floatingTrailing
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PhotoScrubberRepresentable(
                itemSeeds: itemSeeds,
                stripPosition: stripPosition,
                progress: $progress,
                currentItem: $currentItem,
                deleteRequest: $deleteRequest
            )

            VStack(spacing: 8) {
                header
                edgePicker
                floatingToggle
                HStack(spacing: 12) {
                    deleteButton
                    appendButton
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var header: some View {
        HStack {
            Text(String(format: "item %d / %d", currentItem, max(itemSeeds.count - 1, 0)))
            Spacer()
            Text(String(format: "progress %.3f", progress))
        }
        .font(.system(.footnote, design: .monospaced).weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5), in: Capsule())
    }

    private var edgePicker: some View {
        Picker("Edge", selection: $stripEdge) {
            Text("Top").tag(Edge.top)
            Text("Bottom").tag(Edge.bottom)
            Text("Leading").tag(Edge.leading)
            Text("Trailing").tag(Edge.trailing)
        }
        .pickerStyle(.segmented)
        .colorScheme(.dark)
    }

    private var floatingToggle: some View {
        Toggle(isOn: $stripFloating) {
            Text("Floating")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5), in: Capsule())
        .tint(.teal)
    }

    private var deleteButton: some View {
        Button {
            deleteCurrent()
        } label: {
            Label("Delete", systemImage: "trash")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.red.opacity(0.85), in: Capsule())
                .foregroundStyle(.white)
        }
        .disabled(itemSeeds.isEmpty)
    }

    private var appendButton: some View {
        Button {
            appendItem()
        } label: {
            Label("Append", systemImage: "plus")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.green.opacity(0.85), in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private func deleteCurrent() {
        guard !itemSeeds.isEmpty else { return }
        let index = min(max(currentItem, 0), itemSeeds.count - 1)
        itemSeeds.remove(at: index)
        deleteRequest = index
    }

    private func appendItem() {
        let nextSeed = (itemSeeds.max() ?? -1) + 1
        itemSeeds.append(nextSeed)
    }
}

#Preview {
    ContentView()
}
