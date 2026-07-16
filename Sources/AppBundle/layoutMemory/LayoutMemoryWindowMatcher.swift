import Foundation

struct LayoutMemoryLiveWindow: Equatable, Sendable {
    let windowId: UInt32
    let bundleId: String
    let title: String
}

enum LayoutMemoryWindowMatchStrategy: String, Equatable, Sendable {
    case windowId
    case exactTitle
    case titlePrefix
    case uniqueAppWindow
    case appOrder
}

struct LayoutMemoryWindowMatch: Equatable, Sendable {
    let windowId: UInt32
    let strategy: LayoutMemoryWindowMatchStrategy
}

struct LayoutMemoryAmbiguousWindow: Equatable, Sendable {
    let reference: LayoutMemoryWindowReference
    let candidateWindowIds: [UInt32]
}

struct LayoutMemoryWindowMatchResult: Equatable, Sendable {
    let matches: [LayoutMemoryWindowReference: LayoutMemoryWindowMatch]
    let missing: [LayoutMemoryWindowReference]
    let ambiguous: [LayoutMemoryAmbiguousWindow]
    let untouchedLiveWindowIds: Set<UInt32>
}

enum LayoutMemoryWindowMatcher {
    static func match(
        stored: [LayoutMemoryWindowSnapshot],
        live: [LayoutMemoryLiveWindow],
    ) -> LayoutMemoryWindowMatchResult {
        var remainingStored = stored.map(\.reference)
        var remainingLive = Dictionary(uniqueKeysWithValues: live.map { ($0.windowId, $0) })
        var matches: [LayoutMemoryWindowReference: LayoutMemoryWindowMatch] = [:]
        var ambiguous: [LayoutMemoryAmbiguousWindow] = []

        applyUniqueMatches(
            strategy: .windowId,
            stored: &remainingStored,
            live: &remainingLive,
            matches: &matches,
        ) { reference, candidate in
            reference.windowId == candidate.windowId
        }
        applyUniqueMatches(
            strategy: .exactTitle,
            stored: &remainingStored,
            live: &remainingLive,
            matches: &matches,
        ) { reference, candidate in
            reference.bundleId == candidate.bundleId && reference.title == candidate.title
        }
        applyUniqueMatches(
            strategy: .titlePrefix,
            stored: &remainingStored,
            live: &remainingLive,
            matches: &matches,
        ) { reference, candidate in
            reference.bundleId == candidate.bundleId &&
                candidate.title.hasPrefix(stableTitlePrefix(reference.title))
        }
        applyUniqueMatches(
            strategy: .uniqueAppWindow,
            stored: &remainingStored,
            live: &remainingLive,
            matches: &matches,
        ) { reference, candidate in
            reference.bundleId == candidate.bundleId
        }

        for reference in remainingStored {
            let candidates = remainingLive.values
                .filter { $0.bundleId == reference.bundleId }
                .map(\.windowId)
                .sorted()
            if candidates.isEmpty {
                continue
            }
            ambiguous.append(.init(reference: reference, candidateWindowIds: candidates))
        }

        let ambiguousReferences = Set(ambiguous.map(\.reference))
        return .init(
            matches: matches,
            missing: remainingStored.filter { !ambiguousReferences.contains($0) },
            ambiguous: ambiguous,
            untouchedLiveWindowIds: Set(remainingLive.keys),
        )
    }

    private static func applyUniqueMatches(
        strategy: LayoutMemoryWindowMatchStrategy,
        stored: inout [LayoutMemoryWindowReference],
        live: inout [UInt32: LayoutMemoryLiveWindow],
        matches: inout [LayoutMemoryWindowReference: LayoutMemoryWindowMatch],
        predicate: (LayoutMemoryWindowReference, LayoutMemoryLiveWindow) -> Bool,
    ) {
        var matchedStored: Set<LayoutMemoryWindowReference> = []
        var matchedLive: Set<UInt32> = []
        for reference in stored {
            let candidates = live.values.filter { predicate(reference, $0) }
            guard candidates.count == 1, let candidate = candidates.first else { continue }
            let competingReferences = stored.filter { predicate($0, candidate) }
            guard competingReferences.count == 1 else { continue }
            matches[reference] = .init(windowId: candidate.windowId, strategy: strategy)
            matchedStored.insert(reference)
            matchedLive.insert(candidate.windowId)
        }
        stored.removeAll { matchedStored.contains($0) }
        for windowId in matchedLive {
            live.removeValue(forKey: windowId)
        }
    }

    static func stableTitlePrefix(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = [" — ", " – ", " | ", " • ", " - "]
        let candidates = separators.compactMap { separator -> Range<String.Index>? in
            trimmed.range(of: separator)
        }
        guard let first = candidates.min(by: { $0.lowerBound < $1.lowerBound }) else {
            return trimmed
        }
        let prefix = String(trimmed[..<first.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.count >= 4 ? prefix : trimmed
    }
}
