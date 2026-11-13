import Foundation

/// One raw sighting of a window from a single discovery source.
public struct WindowObservation<Ref: Hashable & Sendable>: Sendable {
    public var title: String
    public var source: WindowSource
    public var isMinimized: Bool
    public var isFullScreen: Bool
    /// Window element (visible/anchor/mainOrFocused), tab-group anchor (tab), or nil (menuOnly).
    public var ref: Ref?

    public init(title: String, source: WindowSource, isMinimized: Bool = false, isFullScreen: Bool = false, ref: Ref? = nil) {
        self.title = title; self.source = source; self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen; self.ref = ref
    }
}

/// A deduplicated window slot produced from all observations for one app.
public struct MergedWindow<Ref: Hashable & Sendable>: Sendable {
    public var title: String
    public var source: WindowSource
    public var isMinimized: Bool
    public var isFullScreen: Bool
    public var ref: Ref?
    /// Number of merged slots of this app sharing this exact title.
    public var titleMultiplicity: Int
    /// 0-based position among same-titled slots (stable within one merge).
    public var ordinal: Int
}

/// Merges per-app observations into a duplicate-free list of window slots.
///
/// Sources describe overlapping sets:
///  - the Window menu lists every AppKit window of the app (all Spaces, all tabs),
///  - visible/anchor/mainOrFocused are concrete elements (deduped by element identity),
///  - tabs are non-selected tabs (disjoint from the selected tab's window element).
/// Each menu item claims one element/tab slot with an equivalent title; unclaimed menu items become
/// menu-only slots. Menu titles may differ from AX titles (truncation with "…", decorations),
/// so matching falls back to `menuTitle(_:matches:)` after exact matches.
public enum WindowMerger {
    public static func merge<Ref>(_ observations: [WindowObservation<Ref>]) -> [MergedWindow<Ref>] {
        var slots: [WindowObservation<Ref>] = []
        var seenRefs = Set<Ref>()
        var seenTabs = Set<String>()
        var menus: [WindowObservation<Ref>] = []

        // Higher-precision sources first; stable within a source.
        let ordered = observations.enumerated().sorted { a, b in
            a.element.source != b.element.source ? a.element.source > b.element.source : a.offset < b.offset
        }.map(\.element)

        for o in ordered {
            switch o.source {
            case .menuOnly:
                menus.append(o)
            case .tab:
                // Tabs are keyed by group + title.
                let key = "\(o.ref.map { "\($0.hashValue)" } ?? "-")|\(o.title)"
                if seenTabs.insert(key).inserted { slots.append(o) }
            case .visible, .anchor, .mainOrFocused:
                if let r = o.ref {
                    if seenRefs.insert(r).inserted { slots.append(o) }
                } else {
                    slots.append(o)
                }
            }
        }

        var claimed = Array(repeating: false, count: slots.count)
        var unmatched: [WindowObservation<Ref>] = []
        for m in menus {
            if let i = slots.indices.first(where: { !claimed[$0] && slots[$0].title == m.title }) {
                claimed[i] = true
                if m.isMinimized { slots[i].isMinimized = true }
            } else {
                unmatched.append(m)
            }
        }
        for m in unmatched {
            if let i = slots.indices.first(where: { !claimed[$0] && menuTitle(m.title, matches: slots[$0].title) }) {
                claimed[i] = true
            } else {
                slots.append(m)
                claimed.append(true)
            }
        }

        var counts: [String: Int] = [:]
        for s in slots { counts[s.title, default: 0] += 1 }
        var ordinals: [String: Int] = [:]
        return slots.map { s in
            let ordinal = ordinals[s.title, default: 0]
            ordinals[s.title] = ordinal + 1
            return MergedWindow(title: s.title, source: s.source, isMinimized: s.isMinimized, isFullScreen: s.isFullScreen,
                                ref: s.ref, titleMultiplicity: counts[s.title] ?? 1, ordinal: ordinal)
        }
    }

    /// Whether a Window-menu title plausibly denotes the window with AX title `windowTitle`.
    /// Handles middle truncation ("Heron A…proxy.") and punctuation-only differences
    /// ("Activity Monitor (My Processes)" vs "Activity Monitor – My Processes").
    public static func menuTitle(_ menuTitle: String, matches windowTitle: String) -> Bool {
        if menuTitle == windowTitle { return true }
        if menuTitle.contains("…") {
            let parts = menuTitle.components(separatedBy: "…")
            let head = parts.first ?? "", tail = parts.last ?? ""
            guard windowTitle.hasPrefix(head) else { return false }
            let rest = windowTitle.dropFirst(head.count)
            return tail.isEmpty || rest.contains(tail)
        }
        let a = alphanumerics(menuTitle), b = alphanumerics(windowTitle)
        return !a.isEmpty && a == b
    }

    private static func alphanumerics(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}
