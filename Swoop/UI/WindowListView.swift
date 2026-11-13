import SwiftUI
import SwoopCore

/// Shared list geometry (approved mockup): list inset from the panel edge, row content inset, and the
/// slim scroll bar.
enum ListMetrics {
    static let inset: Double = 20
    static func rowInset(compact: Bool) -> Double { compact ? 14 : 16 }
    static let scrollBarWidth: Double = 4
    static let scrollBarGap: Double = 12
}

/// List layouts (Settings → Appearance → Layout): one-line compact rows or two-line comfortable rows.
/// Same selection, scrolling and activation model as the grid (a one-column `GridLayout`).
struct WindowListView: View {
    let model: SearchViewModel
    let results: [WindowEntry]
    let layout: SwoopCore.GridLayout
    let metrics: GridMetrics

    var body: some View {
        let selected = model.selectedIndex(in: results).map { results[$0].id }
        let height = Double(layout.visibleRows) * metrics.cellHeight + Double(max(layout.visibleRows - 1, 0)) * metrics.rowSpacing
        let compact = model.panelLayout == .compactList
        let query = model.query
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: layout.isScrollable ? ListMetrics.scrollBarGap : 0) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: metrics.rowSpacing) {
                        ForEach(results) { entry in
                            WindowListRow(entry: entry, icon: model.registry.icon(for: entry.pid),
                                          badge: model.registry.badges[entry.pid], isSelected: entry.id == selected,
                                          compact: compact, query: query, height: metrics.cellHeight)
                                .id(entry.id)
                                .onTapGesture { model.activate(entry) }
                        }
                    }
                    .background(GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .named("list")), initial: true) { _, f in
                            scroll = ListScroll(offset: -f.minY, content: f.height)
                        }
                    })
                }
                .coordinateSpace(name: "list")
                // The system scroller is wide when "always show scroll bars" is on; draw a slim one instead.
                .scrollIndicators(.never)
                .scrollDisabled(!layout.isScrollable)
                if layout.isScrollable {
                    SlimScrollBar(scroll: scroll, visible: height)
                }
            }
            .frame(height: height)
            .padding(.horizontal, metrics.horizontalPadding)
            .onChange(of: model.scrollRequest) {
                if let id = model.selectedEntry?.id { proxy.scrollTo(id) }
            }
        }
    }

    @State private var scroll = ListScroll()
}

struct ListScroll: Equatable, Sendable {
    var offset: Double = 0
    var content: Double = 0
}

/// 4 pt scroll indicator: a faint track and a thumb sized to the visible fraction.
private struct SlimScrollBar: View {
    let scroll: ListScroll
    let visible: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let content = max(scroll.content, visible)
        let thumb = max(24, visible * visible / content)
        let progress = content > visible ? min(max(scroll.offset / (content - visible), 0), 1) : 0
        let dark = scheme == .dark
        ZStack(alignment: .top) {
            Capsule().fill(dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
            Capsule().fill(dark ? Color.white.opacity(0.38) : Color.black.opacity(0.3))
                .frame(height: thumb)
                .offset(y: progress * (visible - thumb))
        }
        .frame(width: ListMetrics.scrollBarWidth, height: visible)
        .allowsHitTesting(false)
    }
}

struct WindowListRow: View {
    let entry: WindowEntry
    let icon: NSImage
    let badge: String?
    let isSelected: Bool
    let compact: Bool
    let query: String
    let height: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            iconView
            if compact {
                Text(entry.appName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .frame(width: 110, alignment: .leading)
                highlighted(entry.subtitle, size: 13, weight: .regular, color: secondary)
                    .lineLimit(1).truncationMode(.middle)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    highlighted(headline, size: 14, weight: .semibold, color: primary)
                        .lineLimit(1).truncationMode(.middle)
                    highlighted(caption, size: 12, weight: .regular, color: secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Capsule().fill(fill(0.08)))
                    .fixedSize()
            }
            if isSelected {
                Text("↩")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondary)
                    .frame(width: 20, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(fill(0.12)))
            }
        }
        .padding(.horizontal, ListMetrics.rowInset(compact: compact))
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
                .fill(isSelected ? fill(0.13) : .clear))
        .contentShape(Rectangle())
        .help("\(entry.appName) — \(entry.title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.appName), \(entry.subtitle)\(chips.isEmpty ? "" : ", " + chips.joined(separator: ", "))")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var iconView: some View {
        let size: Double = compact ? 26 : 38
        return Image(nsImage: icon)
            .resizable().interpolation(.high)
            .frame(width: size, height: size)
            .opacity(entry.isMinimized ? 0.75 : 1)
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: compact ? 8.5 : 9.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: compact ? 13 : 16, minHeight: compact ? 13 : 16)
                        .background(Capsule().fill(Color(red: 0.96, green: 0.23, blue: 0.21)))
                        .offset(x: compact ? 4 : 5, y: compact ? -3 : -4)
                }
            }
    }

    /// Comfortable rows lead with what tells windows apart: the VS Code project or the window title.
    private var headline: String { entry.projectName ?? (entry.title.isEmpty ? entry.appName : entry.title) }
    private var caption: String {
        if entry.projectName != nil {
            return [entry.appName, entry.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return entry.appName
    }

    /// Status the grid has no room for. At most two, most important first.
    private var chips: [String] {
        var c: [String] = []
        if entry.isMinimized { c.append("Minimized") }
        if entry.isFullScreen { c.append("Full screen") }
        if entry.isNativeTab { c.append("Tab") }
        if !entry.isOnCurrentSpace && !entry.isMinimized && !entry.isFullScreen { c.append("Other desktop") }
        return Array(c.prefix(2))
    }

    /// Bolds the first case-insensitive occurrence of the query.
    private func highlighted(_ text: String, size: Double, weight: Font.Weight, color: Color) -> Text {
        let base = Font.system(size: size, weight: weight)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let r = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(text).font(base).foregroundColor(color)
        }
        let strong = Font.system(size: size, weight: weight == .regular ? .bold : .heavy)
        return Text(text[..<r.lowerBound]).font(base).foregroundColor(color)
            + Text(text[r]).font(strong).foregroundColor(primary)
            + Text(text[r.upperBound...]).font(base).foregroundColor(color)
    }

    private var dark: Bool { scheme == .dark }
    private var primary: Color { dark ? .white : Color.black.opacity(0.88) }
    private var secondary: Color { dark ? Color.white.opacity(0.6) : Color.black.opacity(0.55) }
    private func fill(_ opacity: Double) -> Color { dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity * 0.6) }
}
