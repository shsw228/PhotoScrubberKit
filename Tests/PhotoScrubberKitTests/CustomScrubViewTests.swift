import XCTest
@testable import PhotoScrubberKit

@MainActor
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
        let view = CustomScrubView()
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let ds = StubDataSource(count: pageCount)
        let del = SpyDelegate()
        view.axis = axis
        view.pageDataSource = ds
        view.pageDelegate = del
        view.reloadData()
        view.layoutIfNeeded()
        return (view, ds, del)
    }

    func testContentSizeHorizontal() {
        let (view, ds, _) = makeScrubView(pageCount: 5)
        XCTAssertEqual(view.contentSize.width, 320 * 5, accuracy: 0.1)
        XCTAssertEqual(view.contentSize.height, 480, accuracy: 0.1)
        withExtendedLifetime(ds) {}
    }

    func testContentSizeVertical() {
        let (view, ds, _) = makeScrubView(pageCount: 5, axis: .vertical)
        XCTAssertEqual(view.contentSize.width, 320, accuracy: 0.1)
        XCTAssertEqual(view.contentSize.height, 480 * 5, accuracy: 0.1)
        withExtendedLifetime(ds) {}
    }

    func testProgressUpdatesOnScroll() {
        let (view, ds, del) = makeScrubView(pageCount: 5)
        view.contentOffset = CGPoint(x: 160, y: 0)
        view.layoutIfNeeded()
        XCTAssertEqual(view.progress, 0.5, accuracy: 0.001)
        XCTAssertTrue(del.progressValues.contains(where: { abs($0 - 0.5) < 0.001 }))
        withExtendedLifetime(ds) {}
    }

    func testCurrentPageIndexAfterSetCurrentPage() {
        let (view, ds, _) = makeScrubView(pageCount: 10)
        view.setCurrentPage(5, animated: false)
        view.layoutIfNeeded()
        XCTAssertEqual(view.currentPageIndex, 5)
        XCTAssertNotNil(view.visibleView)
        XCTAssertEqual(view.visibleView?.tag, 5)
        withExtendedLifetime(ds) {}
    }

    func testKVOOnProgress() {
        let (view, ds, _) = makeScrubView(pageCount: 3)
        var observed: [CGFloat] = []
        let token = view.observe(\.progress, options: [.new]) { _, change in
            if let v = change.newValue { observed.append(v) }
        }
        view.contentOffset = CGPoint(x: 320, y: 0)
        view.layoutIfNeeded()
        token.invalidate()
        XCTAssertTrue(observed.contains(where: { abs($0 - 1.0) < 0.001 }))
        withExtendedLifetime(ds) {}
    }

    func testAppendPage() {
        let (view, ds, _) = makeScrubView(pageCount: 3)
        view.appendPage()
        view.layoutIfNeeded()
        XCTAssertEqual(view.contentSize.width, 320 * 4, accuracy: 0.1)
        withExtendedLifetime(ds) {}
    }
}
