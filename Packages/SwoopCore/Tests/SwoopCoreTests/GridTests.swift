import Testing
@testable import SwoopCore

@Suite("Grid layout")
struct GridLayoutTests {
    let m = GridMetrics(cellWidth: 100, cellHeight: 120, columnSpacing: 10, rowSpacing: 10,
                        horizontalPadding: 20, topPadding: 60, bottomPadding: 20)

    @Test func compactForFewResults() {
        let l = GridLayout.compute(count: 2, metrics: m, maxWidth: 2000, maxHeight: 1000, maxRows: 4, minWidth: 0)
        #expect(l.columns == 2 && l.rows == 1)
        #expect(l.panelWidth == 2 * 100 + 10 + 40)
        #expect(l.panelHeight == 60 + 120 + 20)
    }

    @Test func minWidthKeepsSearchUsable() {
        let l = GridLayout.compute(count: 1, metrics: m, maxWidth: 2000, maxHeight: 1000, maxRows: 4, minWidth: 360)
        #expect(l.panelWidth == 360)
    }

    @Test func wrapsAtMaxWidthWithoutClipping() {
        // usable = 1000-40 = 960 → floor((960+10)/110) = 8 columns
        let l = GridLayout.compute(count: 30, metrics: m, maxWidth: 1000, maxHeight: 5000, maxRows: 10, minWidth: 0)
        #expect(l.columns == 8 && l.rows == 4)
        #expect(l.panelWidth <= 1000)
    }

    @Test func scrollsBeyondMaxRows() {
        let l = GridLayout.compute(count: 100, metrics: m, maxWidth: 1000, maxHeight: 5000, maxRows: 3, minWidth: 0)
        #expect(l.visibleRows == 3 && l.isScrollable)
    }

    @Test func respectsScreenHeight() {
        let l = GridLayout.compute(count: 100, metrics: m, maxWidth: 1000, maxHeight: 400, maxRows: 10, minWidth: 0)
        // (400-80+10)/130 = 2 rows fit
        #expect(l.visibleRows == 2)
    }

    @Test func emptyResults() {
        let l = GridLayout.compute(count: 0, metrics: m, maxWidth: 1000, maxHeight: 1000, maxRows: 3, minWidth: 300)
        #expect(l.rows == 0 && l.visibleRows == 0 && l.panelHeight == 80)
    }
}

@Suite("Grid navigation")
struct GridNavigatorTests {
    // 11 columns, 26 items → rows of 11, 11, 4 (like reference image 2). Last row centered (offset 3.5).
    let nav = GridNavigator(count: 26, columns: 11)

    @Test func leftRightClampAtEnds() {
        #expect(nav.move(0, .left) == 0)
        #expect(nav.move(25, .right) == 25)
        #expect(nav.move(10, .right) == 11) // continues to next row
    }

    @Test func downIntoCenteredIncompleteRow() {
        // Item 15 is row 1 col 4 → visual 4. Last row offset 3.5 → local round(0.5) = 1 → index 23.
        #expect(nav.move(15, .down) == 23)
        // Far left column clamps to first item of last row.
        #expect(nav.move(11, .down) == 22)
        // Far right column clamps to last item.
        #expect(nav.move(21, .down) == 25)
    }

    @Test func upFromCenteredRowKeepsVisualColumn() {
        // Item 22 is visual 3.5 → row 1 index round(3.5)=4 → 15
        #expect(nav.move(22, .up) == 15)
        #expect(nav.move(25, .up) == 18) // visual 6.5 → 7 → 18
    }

    @Test func verticalEdgesStay() {
        #expect(nav.move(3, .up) == 3)
        #expect(nav.move(24, .down) == 24)
    }

    @Test func singleRowAndEmpty() {
        let one = GridNavigator(count: 2, columns: 2)
        #expect(one.move(0, .down) == 0)
        #expect(GridNavigator(count: 0, columns: 4).move(0, .right) == 0)
    }
}

@Suite("List layout")
struct ListLayoutTests {
    let m = GridMetrics(cellWidth: 0, cellHeight: 36, columnSpacing: 0, rowSpacing: 2,
                        horizontalPadding: 10, topPadding: 64, bottomPadding: 12)

    @Test func shrinksToResults() {
        let l = GridLayout.list(count: 3, metrics: m, width: 640, maxWidth: 2000, maxHeight: 2000, maxRows: 9)
        #expect(l.columns == 1 && l.rows == 3 && l.visibleRows == 3 && !l.isScrollable)
        #expect(l.panelWidth == 640)
        #expect(l.panelHeight == 64 + 3 * 36 + 2 * 2 + 12)
    }

    @Test func scrollsBeyondMaxRows() {
        let l = GridLayout.list(count: 30, metrics: m, width: 640, maxWidth: 2000, maxHeight: 2000, maxRows: 9)
        #expect(l.visibleRows == 9 && l.isScrollable)
    }

    @Test func fitsSmallScreens() {
        let l = GridLayout.list(count: 30, metrics: m, width: 640, maxWidth: 500, maxHeight: 64 + 12 + 5 * 38, maxRows: 20)
        #expect(l.visibleRows == 5)
        #expect(l.panelWidth == 500)
    }

    @Test func upDownMoveByOneRow() {
        let nav = GridNavigator(count: 5, columns: 1)
        #expect(nav.move(2, .down) == 3 && nav.move(2, .up) == 1)
        #expect(nav.move(4, .down) == 4 && nav.move(0, .up) == 0)
    }
}
