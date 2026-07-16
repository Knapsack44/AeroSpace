enum LayoutMemoryRestorePlanningError: Error, Equatable {
    case monitorProfileMismatch
    case noMatchedWindows
    case nativeFullscreenActive
}

enum LayoutMemoryRestorePlanner {
    static func plan(
        snapshot: LayoutMemorySnapshot,
        currentMonitorSignature: String,
        expectedLayoutGeneration: UInt64,
        matches: LayoutMemoryWindowMatchResult,
        liveWindows: [LayoutMemoryLiveWindowState],
        automatic: Bool,
    ) throws -> ResolvedLayoutMemoryPlan {
        guard snapshot.monitorProfile.signature == currentMonitorSignature else {
            throw LayoutMemoryRestorePlanningError.monitorProfileMismatch
        }
        guard !matches.matches.isEmpty else {
            throw LayoutMemoryRestorePlanningError.noMatchedWindows
        }
        if automatic, liveWindows.contains(where: \.isNativeFullscreen) {
            throw LayoutMemoryRestorePlanningError.nativeFullscreenActive
        }

        let liveById = Dictionary(uniqueKeysWithValues: liveWindows.map { ($0.windowId, $0) })
        var workspacePlans: [ResolvedWorkspacePlan] = []
        for workspace in snapshot.workspaces {
            let resolvedChildren = try resolveChildren(
                workspace.root.children,
                activeChildIndex: workspace.root.activeChildIndex,
                matches: matches.matches,
            )
            var root = ResolvedLayoutMemoryContainer(
                orientation: workspace.root.orientation,
                layout: workspace.root.layout,
                weight: 1,
                activeChildIndex: resolvedChildren.activeChildIndex,
                children: resolvedChildren.children,
            )
            let unmatchedTilingIds = matches.untouchedLiveWindowIds
                .compactMap { liveById[$0] }
                .filter { $0.workspace == workspace.name && $0.state == .tiling && !$0.isNativeFullscreen }
                .map(\.windowId)
                .sorted()
            if !unmatchedTilingIds.isEmpty {
                let accordion = ResolvedLayoutMemoryContainer(
                    orientation: .horizontal,
                    layout: .accordion,
                    weight: 1,
                    activeChildIndex: 0,
                    children: unmatchedTilingIds.map { .window(windowId: $0, weight: 1 / Double(unmatchedTilingIds.count)) },
                )
                root = root.copy(children: normalizeWeights(root.children + [.container(accordion)]))
            } else {
                root = root.copy(children: normalizeWeights(root.children))
            }
            workspacePlans.append(.init(
                name: workspace.name,
                monitorIdentity: workspace.monitorIdentity,
                isVisible: workspace.isVisible,
                root: root,
            ))
        }

        let floating = snapshot.windows.compactMap { stored -> ResolvedFloatingWindowPlan? in
            guard stored.state == .floating,
                  let match = matches.matches[stored.reference],
                  liveById[match.windowId]?.isNativeFullscreen != true
            else {
                return nil
            }
            return .init(
                windowId: match.windowId,
                workspace: stored.workspace,
                geometry: stored.floatingGeometry,
                zIndex: stored.floatingZIndex,
            )
        }
        let focusedWindow = snapshot.focus.focusedWindow.flatMap { matches.matches[$0]?.windowId }
        let visibility = Dictionary(uniqueKeysWithValues: workspacePlans.filter(\.isVisible).map {
            ($0.monitorIdentity, $0.name)
        })
        let partial = !matches.missing.isEmpty || !matches.ambiguous.isEmpty
        return .init(
            expectedMonitorSignature: currentMonitorSignature,
            expectedLayoutGeneration: expectedLayoutGeneration,
            sourceFingerprint: snapshot.fingerprint,
            workspaces: workspacePlans,
            floatingWindows: floating,
            visibility: .init(visibleWorkspaceByMonitorIdentity: visibility),
            focus: .init(windowId: focusedWindow, workspace: snapshot.focus.focusedWorkspace),
            resultKind: partial ? .partial : .full,
        )
    }

    private static func resolveChildren(
        _ nodes: [LayoutMemoryTreeNodeSnapshot],
        activeChildIndex: Int?,
        matches: [LayoutMemoryWindowReference: LayoutMemoryWindowMatch],
    ) throws -> (children: [ResolvedLayoutMemoryNode], activeChildIndex: Int?) {
        var resolvedWithOriginalIndex: [(Int, ResolvedLayoutMemoryNode)] = []
        for (index, node) in nodes.enumerated() {
            if let resolved = try resolve(node, matches: matches) {
                resolvedWithOriginalIndex.append((index, resolved))
            }
        }
        let active = activeChildIndex.flatMap { requested in
            resolvedWithOriginalIndex.firstIndex(where: { $0.0 == requested })
                ?? resolvedWithOriginalIndex.firstIndex(where: { $0.0 > requested })
                ?? resolvedWithOriginalIndex.lastIndex(where: { $0.0 < requested })
        }
        return (normalizeWeights(resolvedWithOriginalIndex.map(\.1)), active)
    }

    private static func resolve(
        _ node: LayoutMemoryTreeNodeSnapshot,
        matches: [LayoutMemoryWindowReference: LayoutMemoryWindowMatch],
    ) throws -> ResolvedLayoutMemoryNode? {
        switch node {
            case .window(let reference, let weight):
                return matches[reference].map { .window(windowId: $0.windowId, weight: weight) }
            case .container(let container):
                let resolved = try resolveChildren(
                    container.children,
                    activeChildIndex: container.activeChildIndex,
                    matches: matches,
                )
                if resolved.children.isEmpty { return nil }
                if resolved.children.count == 1 {
                    return resolved.children[0].withWeight(container.weight)
                }
                return .container(.init(
                    orientation: container.orientation,
                    layout: container.layout,
                    weight: container.weight,
                    activeChildIndex: resolved.activeChildIndex,
                    children: resolved.children,
                ))
        }
    }

    private static func normalizeWeights(_ nodes: [ResolvedLayoutMemoryNode]) -> [ResolvedLayoutMemoryNode] {
        let total = nodes.map(\.weight).filter { $0.isFinite && $0 > 0 }.reduce(0, +)
        guard !nodes.isEmpty else { return [] }
        if total <= 0 {
            return nodes.map { $0.withWeight(1 / Double(nodes.count)) }
        }
        return nodes.map { $0.withWeight(max($0.weight, 0) / total) }
    }
}
