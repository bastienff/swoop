import Foundation

/// Geometry of the icon grid. All values in points.
public struct GridMetrics: Sendable, Equatable {
    public var cellWidth: Double
    public var cellHeight: Double
    public var columnSpacing: Double
    public var rowSpacing: Double
    public var horizontalPadding: Double
    public var topPadding: Double      // includes the search field area
    public var bottomPadding: Double

    public init(cellWidth: Double, cellHeight: Double, columnSpacing: Double, rowSpacing: Double,
                horizontalPadding: Double, topPadding: Double, bottomPadding: Double) {
        self.cellWidth = cellWidth; self.cellHeight = cellHeight
        self.columnSpacing = columnSpacing; self.rowSpacing = rowSpacing
        self.horizontalPadding = horizontalPadding; self.topPadding = topPadding; self.bottomPadding = bottomPadding
    }
}

public struct GridLayout: Sendable, Equatable {
    public var columns: Int
    public var rows: Int
    public var visibleRows: Int
    public var panelWidth: Double
    public var panelHeight: Double
    public var isScrollable: Bool { rows > visibleRows }

    /// Computes a layout for `count` items that fits `maxWidth`/`maxHeight` (e.g. 90 % of the screen's
    /// visible frame) and at most `maxRows` visible rows. Columns are whole cells, so nothing is clipped
    /// horizontally. `minWidth` keeps the search field usable when there are few results.
    public static func compute(count: Int, metrics m: GridMetrics, maxWidth: Double, maxHeight: Double,
                               maxRows: Int, minWidth: Double) -> GridLayout {
        let usable = max(maxWidth - 2 * m.horizontalPadding, m.cellWidth)
        let maxColumns = max(1, Int((usable + m.columnSpacing) / (m.cellWidth + m.columnSpacing)))
        let columns = max(1, min(max(count, 1), maxColumns))
        let rows = count == 0 ? 0 : (count + columns - 1) / columns
        let heightForRows = max(maxHeight - m.topPadding - m.bottomPadding, m.cellHeight)
        let rowsThatFit = max(1, Int((heightForRows + m.rowSpacing) / (m.cellHeight + m.rowSpacing)))
        let visibleRows = min(rows, max(1, min(maxRows, rowsThatFit)))
        let gridWidth = Double(columns) * m.cellWidth + Double(columns - 1) * m.columnSpacing
        let width = max(gridWidth + 2 * m.horizontalPadding, minWidth)
        let gridHeight = visibleRows == 0 ? 0 : Double(visibleRows) * m.cellHeight + Double(visibleRows - 1) * m.rowSpacing
        let height = m.topPadding + gridHeight + m.bottomPadding
        return GridLayout(columns: columns, rows: rows, visibleRows: visibleRows, panelWidth: width, panelHeight: height)
    }
}

extension GridLayout {
    /// A one-column list: rows of `metrics.cellHeight`, fixed `width` (clamped to `maxWidth`), at most
    /// `maxRows` visible rows (then it scrolls). Navigation reuses `GridNavigator` with one column.
    public static func list(count: Int, metrics m: GridMetrics, width: Double, maxWidth: Double, maxHeight: Double,
                            maxRows: Int) -> GridLayout {
        let heightForRows = max(maxHeight - m.topPadding - m.bottomPadding, m.cellHeight)
        let rowsThatFit = max(1, Int((heightForRows + m.rowSpacing) / (m.cellHeight + m.rowSpacing)))
        let visibleRows = min(count, max(1, min(maxRows, rowsThatFit)))
        let listHeight = visibleRows == 0 ? 0 : Double(visibleRows) * m.cellHeight + Double(visibleRows - 1) * m.rowSpacing
        return GridLayout(columns: 1, rows: count, visibleRows: visibleRows, panelWidth: min(width, maxWidth),
                          panelHeight: m.topPadding + listHeight + m.bottomPadding)
    }
}

/// Keyboard navigation over a grid whose incomplete last row is horizontally centered.
public struct GridNavigator: Sendable {
    public enum Direction: Sendable { case left, right, up, down }

    public var count: Int
    public var columns: Int

    public init(count: Int, columns: Int) { self.count = count; self.columns = max(1, columns) }

    public var rows: Int { count == 0 ? 0 : (count + columns - 1) / columns }

    public func row(of index: Int) -> Int { index / columns }

    /// Items in `row` (the last row may be shorter).
    public func itemsInRow(_ row: Int) -> Int {
        guard row >= 0, row < rows else { return 0 }
        return row == rows - 1 ? count - row * columns : columns
    }

    /// Visual x-position of an item in column units (centering offset applied to short rows).
    public func visualColumn(of index: Int) -> Double {
        let r = row(of: index)
        let offset = Double(columns - itemsInRow(r)) / 2
        return Double(index - r * columns) + offset
    }

    private func index(inRow r: Int, nearestVisualColumn x: Double) -> Int {
        let n = itemsInRow(r)
        let offset = Double(columns - n) / 2
        let local = Int((x - offset).rounded(.toNearestOrAwayFromZero))
        return r * columns + min(max(local, 0), n - 1)
    }

    public func move(_ index: Int, _ direction: Direction) -> Int {
        guard count > 0 else { return 0 }
        let i = min(max(index, 0), count - 1)
        switch direction {
        case .left: return max(i - 1, 0)
        case .right: return min(i + 1, count - 1)
        case .up:
            let r = row(of: i)
            return r == 0 ? i : self.index(inRow: r - 1, nearestVisualColumn: visualColumn(of: i))
        case .down:
            let r = row(of: i)
            return r >= rows - 1 ? i : self.index(inRow: r + 1, nearestVisualColumn: visualColumn(of: i))
        }
    }
}
