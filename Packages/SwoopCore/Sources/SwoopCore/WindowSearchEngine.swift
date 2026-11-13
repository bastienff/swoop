import Foundation

/// Case- and diacritic-insensitive fuzzy ranking of window entries.
///
/// Tiers (higher wins): exact (1000) > prefix (800) > word prefix (700) > substring (500)
/// > fuzzy subsequence (100…400). A VS Code project-name match adds a small bonus that never
/// crosses a tier. Ties break by recency, then by input order.
public enum WindowSearchEngine {
    public struct Options: Sendable {
        public var projectBoost: Double
        public init(projectBoost: Double = 40) { self.projectBoost = projectBoost }
    }

    public static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Scores `query` against `text`; nil if no match. Both are normalized internally.
    public static func score(query rawQuery: String, in rawText: String) -> Double? {
        let q = normalize(rawQuery).trimmingCharacters(in: .whitespaces)
        let t = normalize(rawText)
        guard !q.isEmpty, !t.isEmpty else { return nil }
        if t == q { return 1000 }
        if t.hasPrefix(q) { return 800 + lengthBonus(q, t) }
        if let r = t.range(of: q) {
            let start = r.lowerBound
            if start == t.startIndex || isBoundary(t[t.index(before: start)]) {
                return 700 + lengthBonus(q, t)
            }
            let offset = Double(t.distance(from: t.startIndex, to: start))
            return 500 - min(offset, 80) + lengthBonus(q, t)
        }
        return fuzzy(Array(q), Array(t))
    }

    private static func lengthBonus(_ q: String, _ t: String) -> Double {
        // Prefer tighter matches (query covers more of the text), max +50.
        50 * Double(q.count) / Double(max(t.count, q.count))
    }

    private static func isBoundary(_ c: Character) -> Bool {
        c == " " || c == "-" || c == "_" || c == "." || c == "/" || c == "—" || c == "(" || c == "[" || c == ":" || c == "·"
    }

    /// Greedy subsequence match rewarding contiguity and word-boundary hits.
    private static func fuzzy(_ q: [Character], _ t: [Character]) -> Double? {
        if q.contains(" ") {
            // Multi-word query: every word must match somewhere; score by the weakest word.
            let words = String(q).split(separator: " ").map(String.init)
            var worst = Double.infinity
            for w in words {
                guard let s = score(query: w, in: String(t)) else { return nil }
                worst = min(worst, s)
            }
            return min(worst, 400) * 0.9
        }
        // Acronym pass over word initials ("hap" → heron-api-proxy).
        let initials = t.indices.filter { $0 == 0 || isBoundary(t[$0 - 1]) }.map { t[$0] }
        if q.count >= 2, isSubsequence(q, of: initials) {
            return 360 - 5 * Double(max(initials.count - q.count, 0)).squareRoot()
        }
        var qi = 0, ti = 0
        var run = 0, bestRun = 0, boundaryHits = 0, gaps = 0
        var lastMatch = -1, firstMatch = -1
        while qi < q.count && ti < t.count {
            if q[qi] == t[ti] {
                if lastMatch == ti - 1 { run += 1 } else { run = 1; if lastMatch >= 0 { gaps += ti - lastMatch - 1 } }
                bestRun = max(bestRun, run)
                if ti == 0 || isBoundary(t[ti - 1]) { boundaryHits += 1 }
                if firstMatch < 0 { firstMatch = ti }
                lastMatch = ti
                qi += 1
            }
            ti += 1
        }
        guard qi == q.count else { return nil }
        // Reject scattered matches: unless every character (or all but one) starts a word
        // (acronym-style, e.g. "hap" → "heron-api-proxy"), the matched span must stay compact.
        let span = lastMatch - firstMatch + 1
        let isAcronym = boundaryHits >= max(q.count - 1, 2)
        if q.count >= 3 && !isAcronym && span > max(q.count * 2, q.count + 4) { return nil }
        let contiguity = Double(bestRun) / Double(q.count)
        let s = 100 + 200 * contiguity + 20 * Double(boundaryHits) - 5 * min(Double(gaps), 20)
        return min(max(s, 100), 400)
    }

    private static func isSubsequence(_ q: [Character], of t: [Character]) -> Bool {
        var i = 0
        for c in t where i < q.count && c == q[i] { i += 1 }
        return i == q.count
    }

    public static func score(entry: WindowEntry, query: String, options: Options = .init()) -> Double? {
        var best: Double?
        func consider(_ text: String?, bonus: Double = 0) {
            guard let text, let s = score(query: query, in: text) else { return }
            best = max(best ?? -.infinity, s + bonus)
        }
        consider(entry.appName)
        consider(entry.title)
        consider(entry.detail)
        if let project = entry.projectName, let s = score(query: query, in: project) {
            // Bonus stays inside the tier (tiers are ≥100 apart; bonus < 100).
            best = max(best ?? -.infinity, s + min(options.projectBoost, 90))
        }
        // Whole "app title" phrase, so "code heron" matches "Code — heron.config.js".
        consider("\(entry.appName) \(entry.projectName ?? "") \(entry.title)")
        return best
    }

    /// Ranks entries for `query`. Empty query → most-recently-used first, stable otherwise.
    public static func rank(_ entries: [WindowEntry], query: String, options: Options = .init()) -> [WindowEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let indexed = Array(entries.enumerated())
        func recencyOrder(_ a: (Int, WindowEntry), _ b: (Int, WindowEntry)) -> Bool {
            switch (a.1.lastUsed, b.1.lastUsed) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.0 < b.0
            }
        }
        if trimmed.isEmpty {
            return indexed.sorted(by: recencyOrder).map(\.1)
        }
        let scored: [(Int, WindowEntry, Double)] = indexed.compactMap { i, e in
            score(entry: e, query: trimmed, options: options).map { (i, e, $0) }
        }
        return scored.sorted { a, b in
            if abs(a.2 - b.2) > 0.0001 { return a.2 > b.2 }
            return recencyOrder((a.0, a.1), (b.0, b.1))
        }.map(\.1)
    }
}
