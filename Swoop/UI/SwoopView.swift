import SwiftUI
import SwoopCore

/// Root content of the switcher panel: search pill + icon grid (references/ images 1 & 2).
struct SwoopView: View {
    @Bindable var model: SearchViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        let results = model.results
        let layout = model.layout
        let metrics = model.metrics
        VStack(spacing: 0) {
            // One field for every layout and for both "Always show the search field" states, so it keeps
            // focus and its insertion point. When hidden it's invisible and takes no space; typing reveals it.
            // (Swapping in a different field when the first letter arrived made AppKit select that letter as
            // the new field took focus, so the second keystroke replaced it.)
            let shows = model.showsSearchField
            let isList = model.panelLayout.isList
            let leading = isList ? ListMetrics.inset + ListMetrics.rowInset(compact: model.panelLayout == .compactList) : 0
            // In lists it spans from where the app icons start to where the scroll bar ends; in the grid it's centered.
            SearchPill(text: $model.query, focused: $searchFocused,
                       width: isList ? layout.panelWidth - leading - ListMetrics.inset : 242)
                .frame(height: shows ? nil : 0, alignment: .top)
                .opacity(shows ? 1 : 0)
                .allowsHitTesting(shows)
                .padding(.leading, leading)
                .padding(.trailing, isList ? ListMetrics.inset : 0)
                .padding(.top, shows ? (isList ? 24 : 21) : 30)
                .padding(.bottom, shows ? (isList ? 20 : 25) : 0)
            if results.isEmpty {
                let registry = model.registry
                let searching = registry.entries.isEmpty && (registry.isRefreshing || registry.lastRefresh == nil)
                EmptyResultsView(state: searching ? .searching : registry.entries.isEmpty ? .noWindows : .noMatches)
                    .frame(maxWidth: .infinity)
                    .frame(height: SearchViewModel.emptyStateHeight)
                    .padding(.bottom, metrics.bottomPadding)
            } else if model.panelLayout.isList {
                WindowListView(model: model, results: results, layout: layout, metrics: metrics)
                    .padding(.bottom, metrics.bottomPadding)
            } else {
                WindowGridView(model: model, results: results, layout: layout, metrics: metrics)
                    .padding(.bottom, metrics.bottomPadding)
            }
        }
        .frame(width: layout.panelWidth, height: layout.panelHeight, alignment: .top)
        // Swoop theme: the brand gradient over the panel's blur (kept slightly see-through). Classic: just the
        // blur material, as before. Icons, highlight and search field are the same in both.
        .background {
            if model.settings.theme == .swoop {
                FittedBrandBackground().opacity(0.94)
            }
        }
        .onAppear { searchFocused = true }
        // Typing must always reach the search field: on every open, after a layout change, and when the
        // field appears (with "Always show the search field" off).
        .onChange(of: model.focusRequest) { focusSearch() }
        .onChange(of: model.panelLayout) { focusSearch() }
        .onChange(of: model.showsSearchField) { focusSearch() }
    }
}

/// Message shown instead of results, with a short hint. Same area and padding in every layout.
private struct EmptyResultsView: View {
    enum State { case searching, noWindows, noMatches }
    let state: State
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                if state == .searching { ProgressView().controlSize(.small) }
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.secondary)
            }
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(scheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch state {
        case .searching: "Finding windows…"
        case .noWindows: "No windows"
        case .noMatches: "No matching windows"
        }
    }

    private var hint: String {
        switch state {
        case .searching: "Looking at your open apps."
        case .noWindows: "Open a window in any app, then press the shortcut again."
        case .noMatches: "Try an app name or part of a window title."
        }
    }
}

extension SwoopView {
    /// Next run-loop turn, so it lands after the panel became key and the field exists.
    fileprivate func focusSearch() {
        Task { @MainActor in searchFocused = true }
    }
}

private struct SearchPill: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var width: Double = 242
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13.8, weight: .medium))
                .foregroundStyle(.secondary)
            // Placeholder drawn separately so it can be regular weight while typed text stays medium.
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.8, weight: .medium))
                .focused(focused)
                .overlay(alignment: .leading) {
                    if text.isEmpty {
                        Text("Search windows…")
                            .font(.system(size: 13.8, weight: .regular))
                            .foregroundStyle(scheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.35))
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Search windows")
        }
        .padding(.horizontal, 15)
        .frame(width: width, height: 29)
        .background(Capsule().fill(scheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(scheme == .dark ? 0.06 : 0.25), lineWidth: 0.5))
    }
}

struct WindowGridView: View {
    let model: SearchViewModel
    let results: [WindowEntry]
    let layout: SwoopCore.GridLayout
    let metrics: GridMetrics

    var body: some View {
        let columns = max(layout.columns, 1)
        let rows = stride(from: 0, to: results.count, by: columns).map { Array(results[$0..<min($0 + columns, results.count)]) }
        let selected = model.selectedIndex(in: results).map { results[$0].id }
        let gridHeight = Double(layout.visibleRows) * metrics.cellHeight + Double(max(layout.visibleRows - 1, 0)) * metrics.rowSpacing
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: metrics.rowSpacing) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: metrics.columnSpacing) {
                            ForEach(rows[r]) { entry in
                                WindowGridItemView(entry: entry, icon: model.registry.icon(for: entry.pid),
                                                   badge: model.registry.badges[entry.pid],
                                                   isSelected: entry.id == selected,
                                                   iconSize: model.settings.iconSize.points,
                                                   cellWidth: metrics.cellWidth, cellHeight: metrics.cellHeight)
                                    .id(entry.id)
                                    .onTapGesture { model.activate(entry) }
                            }
                        }
                        .frame(maxWidth: .infinity) // centers the incomplete last row
                    }
                }
            }
            .scrollIndicators(layout.isScrollable ? .automatic : .never)
            .scrollDisabled(!layout.isScrollable)
            .frame(height: gridHeight)
            .padding(.horizontal, metrics.horizontalPadding)
            .onChange(of: model.scrollRequest) {
                if let id = model.selectedEntry?.id { proxy.scrollTo(id) }
            }
        }
    }
}

struct WindowGridItemView: View {
    let entry: WindowEntry
    let icon: NSImage
    let badge: String?
    let isSelected: Bool
    let iconSize: Double
    let cellWidth: Double
    let cellHeight: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let highlight = iconSize + 20
        VStack(spacing: 0) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: highlight * 0.24, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: highlight * 0.24, style: .continuous)
                                .strokeBorder(Color.white.opacity(scheme == .dark ? 0.10 : 0.35), lineWidth: 1))
                }
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(entry.isMinimized ? 0.75 : 1)
                    .overlay(alignment: .topTrailing) {
                        if let badge {
                            Text(badge)
                                .font(.system(size: iconSize * 0.2, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, iconSize * 0.07)
                                .frame(minWidth: iconSize * 0.33, minHeight: iconSize * 0.33)
                                .background(Capsule().fill(Color(red: 0.96, green: 0.23, blue: 0.21)))
                                .offset(x: iconSize * 0.1, y: -iconSize * 0.1)
                        }
                    }
            }
            .frame(width: highlight, height: highlight)
            .padding(.bottom, 8)

            Text(entry.appName)
                .font(.system(size: 13.5, weight: isSelected ? .bold : .medium))
                .foregroundStyle(nameColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 17)

            HStack(spacing: 4) {
                if let symbol = stateSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(subtitleColor)
                }
                Text(entry.subtitle.isEmpty ? " " : entry.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(height: 16)
        }
        .frame(width: cellWidth, height: cellHeight)
        .contentShape(Rectangle())
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.appName), \(entry.subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // Explicit tones (instead of vibrancy) to match the references: dim names, bright selected name.
    private var nameColor: Color {
        let dark = scheme == .dark
        if isSelected { return dark ? .white : Color.black.opacity(0.88) }
        return dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62)
    }

    private var subtitleColor: Color {
        scheme == .dark ? Color.white.opacity(isSelected ? 0.62 : 0.45) : Color.black.opacity(isSelected ? 0.6 : 0.45)
    }

    /// Small state indicator (PRD §7.5), used sparingly like the references.
    private var stateSymbol: String? {
        if entry.isMinimized { return "minus.square" }
        if entry.isFullScreen { return "arrow.up.left.and.arrow.down.right" }
        return nil
    }

    private var helpText: String {
        var parts = ["\(entry.appName) — \(entry.title)"]
        if entry.isMinimized { parts.append("Minimized") }
        if entry.isNativeTab { parts.append("Native tab") }
        if !entry.isOnCurrentSpace && !entry.isMinimized { parts.append("On another desktop") }
        return parts.joined(separator: " · ")
    }
}
