import Foundation

/// Pure decisions for recovering window elements on other Spaces (ARCHITECTURE §2a).
///
/// Background (verified, F18–F21): an app's AX element ids are small, dense and stable for the life
/// of the app process, and an element stays reachable by id after the client that first requested it
/// quits. So windows that any client (e.g. a previous Swoop run) already saw can be recovered, but a
/// window that was never requested has no id. A recovered window element may be a *hidden native tab*:
/// it then has no tab bar of its own and looks like a normal window. Focusing it directly is unverified
/// and could relocate its group (F7), so it is only used when proven safe.
public enum RemoteRecoveryPolicy {

    /// How a recovered window element may be used.
    public enum Verdict: Equatable, Sendable {
        /// Safe to use as a window anchor (focus → navigates to its Space without moving it).
        case anchor
        /// A non-selected tab of some group: never focus it directly.
        case hiddenTab
        /// Could be a hidden tab of an unknown group: not used.
        case ambiguous
    }

    /// Classifies a recovered window element.
    /// - Parameters:
    ///   - title: the element's window title.
    ///   - selectedTabTitle: nil if the element has no tab bar of its own; otherwise the title of the
    ///     selected tab in that bar (the visible window of a group is the selected tab).
    ///   - knownHiddenTabTitles: titles of non-selected tabs in tab groups already known for the app.
    ///   - windowsSharingFrame: CG windows of the app whose frame equals this element's frame (incl. itself).
    ///   - accountedSharingFrame: of those, how many are explained by *other* known elements
    ///     (a known group window accounts for all its tabs, a known plain window for 1).
    public static func classify(title: String, selectedTabTitle: String??, knownHiddenTabTitles: Set<String>,
                                windowsSharingFrame: Int, accountedSharingFrame: Int) -> Verdict {
        if let selected = selectedTabTitle, let selected {
            return selected == title ? .anchor : .hiddenTab
        }
        if knownHiddenTabTitles.contains(title) { return .hiddenTab }
        // Hidden tabs always share their group's frame with the group's other windows (F4). If every other
        // window with this frame is accounted for by known elements, this one is alone: not a hidden tab.
        return isProvablyStandalone(windowsSharingFrame: windowsSharingFrame, accountedSharingFrame: accountedSharingFrame)
            ? .anchor : .ambiguous
    }

    public static func isProvablyStandalone(windowsSharingFrame: Int, accountedSharingFrame: Int) -> Bool {
        windowsSharingFrame - accountedSharingFrame <= 1
    }

    // MARK: - Sweep planning

    /// Ids above the highest id seen so far that are still swept (elements vended concurrently).
    public static let sweepMargin: UInt64 = 512
    /// Hard ceiling of ids swept per app process per Swoop run, so a pathological app (huge id space)
    /// can never cost more than a few seconds of low-priority background work.
    public static let sweepCap: UInt64 = 400_000

    /// Next range of element ids to sweep, or nil when there is nothing (new) to sweep.
    /// - Parameters:
    ///   - cursor: ids below this were already swept.
    ///   - highWater: highest element id observed for the app.
    ///   - swept: ids swept so far for the app in this run.
    public static func nextSweepRange(cursor: UInt64, highWater: UInt64, swept: UInt64,
                                      margin: UInt64 = sweepMargin, cap: UInt64 = sweepCap) -> Range<UInt64>? {
        guard swept < cap else { return nil }
        let end = min(highWater + margin, cursor + (cap - swept))
        return cursor < end ? cursor..<end : nil
    }
}
