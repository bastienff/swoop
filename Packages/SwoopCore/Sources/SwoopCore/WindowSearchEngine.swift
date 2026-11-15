import Foundation

/// How the switcher orders windows when nothing is typed (and how it breaks ties when searching).
public enum WindowOrder: String, CaseIterable, Identifiable, Sendable {
    /// Most recently used first, except the window you're in, which comes second:
    /// open the switcher and press Return to go back to the previous window.
    case smart
    /// Most recently used first, including the window you're in.
    case recent
    /// Alphabetical by app, then by window title.
    case name
    public var id: String { rawValue }
}

/// Case- and diacritic-insensitive fuzzy ranking of window entries.
///
/// Tiers (higher wins): exact (1000) > prefix (800) > word prefix (700) > initials (600…650)
/// > initials run (550…590) > substring (420…549) > initials subsequence (~360) > fuzzy (100…400).
/// "Initials" are the first letters of words, where words also split at camelCase
/// (`vsc` → Visual Studio Code, `hw` → heron-web or HeronWeb). A VS Code project-name match
/// adds a small bonus that can't lift a match past the next tier. Ties break by the chosen order
/// (recency or name), then by input order.
public enum WindowSearchEngine {
    public struct Options: Sendable {
        public var projectBoost: Double
        public var order: WindowOrder
        /// The frontmost app when the switcher opened. In `.smart` order, its most recently used
        /// window (the one you're in) moves from first to second place.
        public var frontmostPID: Int32?
        public init(projectBoost: Double = 40, order: WindowOrder = .recent, frontmostPID: Int32? = nil) {
            self.projectBoost = projectBoost; self.order = order; self.frontmostPID = frontmostPID
        }
    }

    public static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Scores `query` against `text`; nil if no match. Both are normalized internally.
    public static func score(query rawQuery: String, in rawText: String) -> Double? {
        evaluate(rawQuery, rawText)?.score
    }

    /// The parts of `text` to emphasize for `query`: the matched initials when an initials match
    /// ranks the text, otherwise the first occurrence of the query. Empty for other fuzzy matches.
    public static func matchRanges(query rawQuery: String, in text: String) -> [Range<String.Index>] {
        guard let match = evaluate(rawQuery, text) else { return [] }
        if let initials = match.initials {
            return initials.map { $0..<text.index(after: $0) }
        }
        let q = rawQuery.trimmingCharacters(in: .whitespaces)
        return text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]).map { [$0] } ?? []
    }

    private struct Match {
        var score: Double
        /// Where the matched initials are in the raw text, when the score comes from them.
        var initials: [String.Index]?
    }

    private static func evaluate(_ rawQuery: String, _ rawText: String) -> Match? {
        let q = normalize(rawQuery).trimmingCharacters(in: .whitespaces)
        let t = normalize(rawText)
        guard !q.isEmpty, !t.isEmpty else { return nil }
        if t == q { return Match(score: 1000) }
        if t.hasPrefix(q) { return Match(score: 800 + lengthBonus(q, t)) }
        let starts = wordStarts(rawText)
        let acronym = initialsMatch(Array(q), starts)
        if let r = t.range(of: q) {
            let start = r.lowerBound
            if start == t.startIndex || isBoundary(t[t.index(before: start)]) {
                return Match(score: 700 + lengthBonus(q, t))
            }
            // Mid-word hit: initials beat it ("hw" → heron-web over "touchwood").
            let offset = Double(t.distance(from: t.startIndex, to: start))
            let substring = 500 - min(offset, 80) + lengthBonus(q, t)
            if let acronym, acronym.score > substring { return acronym }
            return Match(score: substring)
        }
        if let acronym { return acronym }
        return fuzzy(Array(q), Array(t), starts: starts)
    }

    /// Initials tiers: the query is the start of the initials (600…650, 650 = every initial), or a
    /// run of them further in (550…590). Single letters and multi-word queries don't count.
    private static func initialsMatch(_ q: [Character], _ starts: [(index: String.Index, char: Character)]) -> Match? {
        guard q.count >= 2, !q.contains(" "), starts.count >= q.count else { return nil }
        let chars = starts.map(\.char), coverage = Double(q.count) / Double(chars.count)
        for offset in 0...(chars.count - q.count) where Array(chars[offset..<offset + q.count]) == q {
            let indices = starts[offset..<offset + q.count].map(\.index)
            return Match(score: offset == 0 ? 600 + 50 * coverage : 550 + 40 * coverage, initials: indices)
        }
        return nil
    }

    /// The first character of each word, normalized, with its index in `text`. Words start after any
    /// non-alphanumeric character, at a lowercase→uppercase step ("HeronWeb"), at the last capital
    /// of a capital run followed by lowercase ("VSCode" → V, C), and at a letter→digit step ("iTerm2").
    static func wordStarts(_ text: String) -> [(index: String.Index, char: Character)] {
        var out: [(index: String.Index, char: Character)] = []
        let chars = Array(text.indices)
        for (i, idx) in chars.enumerated() {
            let c = text[idx]
            guard c.isLetter || c.isNumber else { continue }
            var start = i == 0
            if !start {
                let prev = text[chars[i - 1]]
                let next: Character? = i + 1 < chars.count ? text[chars[i + 1]] : nil
                start = !(prev.isLetter || prev.isNumber)
                    || (c.isUppercase && prev.isLowercase)
                    || (c.isUppercase && prev.isUppercase && next?.isLowercase == true)
                    || (c.isNumber && prev.isLetter)
            }
            if start { out.append((idx, normalize(String(c)).first ?? c)) }
        }
        return out
    }

    private static func lengthBonus(_ q: String, _ t: String) -> Double {
        // Prefer tighter matches (query covers more of the text), max +50.
        50 * Double(q.count) / Double(max(t.count, q.count))
    }

    /// Words are separated by anything that isn't a letter or digit (space, -, _, ., /, #, —, …),
    /// the same rule `wordStarts` uses for initials.
    private static func isBoundary(_ c: Character) -> Bool { !(c.isLetter || c.isNumber) }

    /// Greedy subsequence match rewarding contiguity and word-boundary hits.
    private static func fuzzy(_ q: [Character], _ t: [Character], starts: [(index: String.Index, char: Character)]) -> Match? {
        if q.contains(" ") {
            // Multi-word query: every word must match somewhere; score by the weakest word.
            let words = String(q).split(separator: " ").map(String.init)
            var worst = Double.infinity
            for w in words {
                guard let s = score(query: w, in: String(t)) else { return nil }
                worst = min(worst, s)
            }
            return Match(score: min(worst, 400) * 0.9)
        }
        // Initials in order with gaps ("vc" → Visual Studio Code).
        if q.count >= 2, let picked = subsequence(q, of: starts) {
            return Match(score: 360 - 5 * Double(max(starts.count - q.count, 0)).squareRoot(), initials: picked)
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
        return Match(score: min(max(s, 100), 400))
    }

    /// Indices of the word starts that spell `q` in order (greedy), or nil.
    private static func subsequence(_ q: [Character], of starts: [(index: String.Index, char: Character)]) -> [String.Index]? {
        var picked: [String.Index] = []
        for s in starts where picked.count < q.count && s.char == q[picked.count] { picked.append(s.index) }
        return picked.count == q.count ? picked : nil
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
            // Capped so it can lift a match past weaker scores of the next tier at most, never two
            // tiers up (e.g. a substring hit never passes an initials match of the whole name).
            best = max(best ?? -.infinity, s + min(options.projectBoost, 45))
        }
        // Whole "app title" phrase, so "code heron" matches "Code — heron.config.js".
        consider("\(entry.appName) \(entry.projectName ?? "") \(entry.title)")
        return best
    }

    /// Ranks entries for `query`. Empty query → `options.order`; otherwise by score, ties by that order.
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
        func nameOrder(_ a: (Int, WindowEntry), _ b: (Int, WindowEntry)) -> Bool {
            for (x, y) in [(a.1.appName, b.1.appName), (a.1.projectName ?? a.1.title, b.1.projectName ?? b.1.title), (a.1.title, b.1.title)] {
                let c = x.localizedStandardCompare(y)
                if c != .orderedSame { return c == .orderedAscending }
            }
            return a.0 < b.0
        }
        let order = options.order == .name ? nameOrder : recencyOrder
        if trimmed.isEmpty {
            var ranked = indexed.sorted(by: order).map(\.1)
            // Smart: the window you're in is the frontmost app's most recent one. When it leads the
            // list, the previous window takes its place so Return goes back.
            if options.order == .smart, ranked.count > 1, let pid = options.frontmostPID, ranked[0].pid == pid {
                ranked.swapAt(0, 1)
            }
            return ranked
        }
        let scored: [(Int, WindowEntry, Double)] = indexed.compactMap { i, e in
            score(entry: e, query: trimmed, options: options).map { (i, e, $0) }
        }
        return scored.sorted { a, b in
            if abs(a.2 - b.2) > 0.0001 { return a.2 > b.2 }
            return order((a.0, a.1), (b.0, b.1))
        }.map(\.1)
    }
}
