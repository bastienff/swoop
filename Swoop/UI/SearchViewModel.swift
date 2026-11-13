import AppKit
import Observation
import SwoopCore

/// State of one presentation of the switcher: query, ranked results, selection and layout.
@MainActor
@Observable
final class SearchViewModel {
    var query = "" {
        didSet { if query != oldValue { selectedID = nil; scrollRequest += 1 } }
    }
    /// Selection is tracked by id so registry refreshes don't reset it (PRD §7 "reset only when necessary").
    var selectedID: String?
    /// Incremented to ask the grid to scroll the selection into view.
    private(set) var scrollRequest = 0
    /// Incremented each time the panel opens, so the search field takes keyboard focus again.
    private(set) var focusRequest = 0

    func requestFocus() { focusRequest += 1 }
    /// Screen-dependent bounds set by the panel controller before showing.
    var maxPanelSize = CGSize(width: 1400, height: 900)

    @ObservationIgnored let registry: WindowRegistry
    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored var onActivate: ((WindowEntry) -> Void)?
    @ObservationIgnored var onDismiss: (() -> Void)?

    init(registry: WindowRegistry, settings: AppSettings) {
        self.registry = registry
        self.settings = settings
    }

    var results: [WindowEntry] {
        let options = WindowSearchEngine.Options(projectBoost: settings.vscodeSearchBoost ? 40 : 0)
        return WindowSearchEngine.rank(registry.entries, query: query, options: options)
    }

    var showsSearchField: Bool { settings.alwaysShowSearchField || !query.isEmpty }

    // MARK: Metrics (tuned against references/: ~96 pt icons, ~131 pt column pitch)

    var panelLayout: PanelLayout { settings.panelLayout }

    var metrics: GridMetrics {
        if panelLayout.isList {
            // Approved spacing: 40/60 pt rows, 4 pt gaps, 20 pt list inset; search 24 + 29 + 20 pt; 24 pt bottom.
            return GridMetrics(
                cellWidth: 0, cellHeight: panelLayout == .compactList ? 40 : 60, columnSpacing: 0, rowSpacing: 4,
                horizontalPadding: ListMetrics.inset, topPadding: showsSearchField ? 73 : 30, bottomPadding: 24)
        }
        let icon = settings.iconSize.points
        let highlight = icon + 20
        return GridMetrics(
            cellWidth: highlight + 10,
            cellHeight: highlight + 8 + 17 + 16,
            columnSpacing: max(4, icon * 0.1),
            rowSpacing: max(10, icon * 0.2),
            horizontalPadding: 28,
            topPadding: showsSearchField ? 75 : 30,
            bottomPadding: 26)
    }

    /// Height of the message area shown instead of results ("No matching windows", "Finding windows…").
    /// The panel reserves it, so the message keeps the same padding as results in every layout.
    static let emptyStateHeight: Double = 64

    var layout: GridLayout {
        let count = results.count
        var l: GridLayout
        if panelLayout.isList {
            l = GridLayout.list(count: count, metrics: metrics, width: panelLayout == .compactList ? 640 : 680,
                                maxWidth: maxPanelSize.width, maxHeight: maxPanelSize.height,
                                maxRows: settings.maxVisibleListRows)
        } else {
            l = GridLayout.compute(count: count, metrics: metrics,
                                   maxWidth: maxPanelSize.width, maxHeight: maxPanelSize.height,
                                   maxRows: settings.maxVisibleRows, minWidth: 400)
        }
        if count == 0 { l.panelHeight += Self.emptyStateHeight }
        return l
    }

    // MARK: Selection

    func selectedIndex(in results: [WindowEntry]) -> Int? {
        guard !results.isEmpty else { return nil }
        if let id = selectedID, let i = results.firstIndex(where: { $0.id == id }) { return i }
        return 0
    }

    var selectedEntry: WindowEntry? {
        let r = results
        return selectedIndex(in: r).map { r[$0] }
    }

    func move(_ direction: GridNavigator.Direction) {
        let r = results
        guard let current = selectedIndex(in: r) else { return }
        let next = GridNavigator(count: r.count, columns: layout.columns).move(current, direction)
        selectedID = r[next].id
        scrollRequest += 1
    }

    func step(_ delta: Int) {
        let r = results
        guard let current = selectedIndex(in: r), !r.isEmpty else { return }
        selectedID = r[(current + delta + r.count) % r.count].id
        scrollRequest += 1
    }

    func activateSelection() {
        if let e = selectedEntry { onActivate?(e) }
    }

    func activate(_ entry: WindowEntry) {
        selectedID = entry.id
        onActivate?(entry)
    }

    func reset() {
        query = ""
        selectedID = nil
    }
}
