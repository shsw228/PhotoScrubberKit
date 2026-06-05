import XCTest
@testable import PhotoScrubberKit

final class CustomScrubViewTests: XCTestCase {

    final class StubDataSource: CustomScrubViewDataSource {
        let count: Int
        var requestedIndices: [Int] = []
        init(count: Int) { self.count = count }
        func numberOfPages(in scrubView: CustomScrubView) -> Int { count }
        func scrubView(_ scrubView: CustomScrubView, viewForPageAt index: Int) -> UIView {
            requestedIndices.append(index)
            let v = UIView()
            v.tag = index
            return v
        }
    }

    final class SpyDelegate: CustomScrubViewDelegate {
        var progressValues: [CGFloat] = []
        var pageChanges: [Int] = []
        func scrubView(_ scrubView: CustomScrubView, didUpdateProgress progress: CGFloat) {
            progressValues.append(progress)
        }
        func scrubView(_ scrubView: CustomScrubView, didChangeVisiblePage index: Int) {
            pageChanges.append(index)
        }
    }

    func makeScrubView(pageCount: Int, axis: ScrubAxis = .horizontal) -> (CustomScrubView, StubDataSource, SpyDelegate) {
        let view = CustomScrubView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let ds = StubDataSource(count: pageCount)
        let del = SpyDelegate()
        view.axis = axis
        view.pageDataSource = ds
        view.pageDelegate = del
        view.reloadData()
        view.layoutIfNeeded()
        return (view, ds, del)
    }

    func testInitialMountIsThreeOrFewer() {
        let (view, _, _) = makeScrubView(pageCount: 10)
        let mounted = view.subviews.filter { $0.tag >= 0 && $0.tag < 10 }
        XCTAssertLessThanOrEqual(mounted.count, 3)
    }

    func testContentSizeHorizontal() {
        let (view, _, _) = makeScrubView(pageCount: 5)
        XCTAssertEqual(view.contentSize, CGSize(width: 320 * 5, height: 480))
    }

    func testContentSizeVertical() {
        let (view, _, _) = makeScrubView(pageCount: 5, axis: .vertical)
        XCTAssertEqual(view.contentSize, CGSize(width: 320, height: 480 * 5))
    }

    func testProgressUpdatesOnScroll() {
        let (view, _, del) = makeScrubView(pageCount: 5)
        view.contentOffset = CGPoint(x: 160, y: 0) // half-way to page 1
        view.layoutIfNeeded()
        XCTAssertEqual(view.progress, 0.5, accuracy: 0.001)
        XCTAssertTrue(del.progressValues.contains(where: { abs($0 - 0.5) < 0.001 }))
    }

    func testRecyclingWhenScrollingFar() {
        let (view, _, _) = makeScrubView(pageCount: 10)
        view.contentOffset = CGPoint(x: 320 * 5, y: 0) // jump to page 5
        view.layoutIfNeeded()
        let mountedTags = view.subviews.map(\.tag).filter { (0..<10).contains($0) }.sorted()
        XCTAssertEqual(mountedTags, [4, 5, 6])
        XCTAssertEqual(view.currentPageIndex, 5)
        XCTAssertEqual(view.visibleView?.tag, 5)
    }

    func testKVOOnProgress() {
        let (view, _, _) = makeScrubView(pageCount: 3)
        var observed: [CGFloat] = []
        let token = view.observe(\.progress, options: [.new]) { _, change in
            if let v = change.newValue { observed.append(v) }
        }
        view.contentOffset = CGPoint(x: 320, y: 0)
        view.layoutIfNeeded()
        token.invalidate()
        XCTAssertTrue(observed.contains(where: { abs($0 - 1.0) < 0.001 }))
    }
}
