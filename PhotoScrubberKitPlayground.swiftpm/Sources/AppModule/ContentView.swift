import SwiftUI
import PhotoScrubberKit

struct ContentView: View {
    @StateObject private var store = ScrubberStore()
    @State private var floating = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Layout は SwiftUI 側で決める。ライブラリは scrubView / stripView を素のまま渡してくる。
            if floating {
                ZStack(alignment: .bottom) {
                    UIViewBridge(view: store.coupling.scrubView)
                    UIViewBridge(view: store.coupling.stripView)
                        .frame(height: 96)
                        .padding(.bottom, 24)
                }
            } else {
                VStack(spacing: 0) {
                    UIViewBridge(view: store.coupling.scrubView)
                    UIViewBridge(view: store.coupling.stripView)
                        .frame(height: 96)
                }
            }

            VStack(spacing: 8) {
                header
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
        .task { store.setupIfNeeded() }
    }

    private var header: some View {
        HStack {
            Text(String(format: "item %d / %d", store.currentItem, max(store.itemSeeds.count - 1, 0)))
            Spacer()
            Text(String(format: "progress %.3f", store.progress))
        }
        .font(.system(.footnote, design: .monospaced).weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5), in: Capsule())
    }

    private var floatingToggle: some View {
        Toggle(isOn: $floating) {
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
            store.deleteCurrent()
        } label: {
            Label("Delete", systemImage: "trash")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.red.opacity(0.85), in: Capsule())
                .foregroundStyle(.white)
        }
        .disabled(store.itemSeeds.isEmpty)
    }

    private var appendButton: some View {
        Button {
            store.appendItem()
        } label: {
            Label("Append", systemImage: "plus")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.green.opacity(0.85), in: Capsule())
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    ContentView()
}
