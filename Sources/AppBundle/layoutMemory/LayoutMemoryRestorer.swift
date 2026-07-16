import AppKit

enum LayoutMemoryRestoreError: Error, Equatable {
    case busy
    case monitorProfileChanged
    case layoutChanged
    case missingWindow(UInt32)
    case duplicateWindow(UInt32)
}

struct LayoutMemoryRestoreResult: Equatable, Sendable {
    let kind: LayoutMemoryRestoreResultKind
    let mutated: Bool
    let warnings: [String]
}

enum LayoutMemoryRestorer {
    @MainActor
    static func restore(_ plan: ResolvedLayoutMemoryPlan) async throws -> LayoutMemoryRestoreResult {
        let runtime = LayoutMemoryRuntime.shared
        guard runtime.phase == .idle else { throw LayoutMemoryRestoreError.busy }
        runtime.beginPreflight()
        var didCommit = false
        defer {
            if !didCommit, runtime.phase != .idle {
                _ = runtime.finish()
            }
        }

        let profile = try currentLayoutMemoryMonitorProfile()
        guard profile.signature == plan.expectedMonitorSignature else {
            throw LayoutMemoryRestoreError.monitorProfileChanged
        }
        guard runtime.layoutGeneration == plan.expectedLayoutGeneration else {
            throw LayoutMemoryRestoreError.layoutChanged
        }
        let targetIds = plan.workspaces.flatMap { collectWindowIds($0.root) } +
            plan.floatingWindows.map(\.windowId)
        var seen: Set<UInt32> = []
        var windowsById: [UInt32: Window] = [:]
        for windowId in targetIds {
            guard seen.insert(windowId).inserted else {
                throw LayoutMemoryRestoreError.duplicateWindow(windowId)
            }
            guard let window = Window.get(byId: windowId) else {
                throw LayoutMemoryRestoreError.missingWindow(windowId)
            }
            windowsById[windowId] = window
        }

        let refreshedProfile = try currentLayoutMemoryMonitorProfile()
        guard refreshedProfile.signature == plan.expectedMonitorSignature else {
            throw LayoutMemoryRestoreError.monitorProfileChanged
        }
        guard runtime.layoutGeneration == plan.expectedLayoutGeneration else {
            throw LayoutMemoryRestoreError.layoutChanged
        }

        runtime.beginCommit()
        for workspacePlan in plan.workspaces {
            let workspace = Workspace.get(byName: workspacePlan.name)
            let previousRoot = workspace.children.compactMap { $0 as? TilingContainer }.singleOrNil()
            previousRoot?.unbindFromParent()
            _ = buildContainer(
                workspacePlan.root,
                parent: workspace,
                index: INDEX_BIND_LAST,
                windowsById: windowsById,
            )
        }
        didCommit = true

        var warnings: [String] = []
        for floatingPlan in plan.floatingWindows {
            guard let window = Window.get(byId: floatingPlan.windowId) else { continue }
            let workspace = Workspace.get(byName: floatingPlan.workspace)
            window.bindAsFloatingWindow(to: workspace)
            if let geometry = floatingPlan.geometry,
               let monitor = try? monitor(identity: geometry.monitorIdentity, profile: refreshedProfile)
            {
                let visible = monitor.visibleRect
                let normalized = geometry.normalizedVisibleFrame
                window.setAxFrame(
                    CGPoint(
                        x: visible.topLeftX + visible.width * normalized.x,
                        y: visible.topLeftY + visible.height * normalized.y,
                    ),
                    CGSize(
                        width: visible.width * normalized.width,
                        height: visible.height * normalized.height,
                    ),
                )
            }
        }

        for (monitorIdentity, workspaceName) in plan.visibility.visibleWorkspaceByMonitorIdentity {
            do {
                _ = try monitor(identity: monitorIdentity, profile: refreshedProfile)
                    .setActiveWorkspace(Workspace.get(byName: workspaceName))
            } catch {
                warnings.append("Monitor '\(monitorIdentity)' disappeared before visibility restore")
            }
        }
        if let windowId = plan.focus.windowId, let window = Window.get(byId: windowId) {
            _ = window.focusWindow()
            window.nativeFocus()
        } else {
            _ = Workspace.get(byName: plan.focus.workspace).focusWorkspace()
        }

        let queued = runtime.finish()
        for windowId in queued {
            if let window = Window.get(byId: windowId) {
                await tryOnWindowDetected(window)
            }
        }
        return .init(kind: plan.resultKind, mutated: true, warnings: warnings)
    }

    @MainActor
    private static func buildContainer(
        _ source: ResolvedLayoutMemoryContainer,
        parent: NonLeafTreeNodeObject,
        index: Int,
        windowsById: [UInt32: Window],
    ) -> TilingContainer {
        let container = TilingContainer(
            parent: parent,
            adaptiveWeight: CGFloat(source.weight),
            source.orientation == .horizontal ? .h : .v,
            source.layout == .tiles ? .tiles : .accordion,
            index: index,
        )
        for (childIndex, child) in source.children.enumerated() {
            switch child {
                case .window(let windowId, let weight):
                    windowsById[windowId].orDie()
                        .bind(to: container, adaptiveWeight: CGFloat(weight), index: childIndex)
                case .container(let nested):
                    _ = buildContainer(
                        nested,
                        parent: container,
                        index: childIndex,
                        windowsById: windowsById,
                    )
            }
        }
        if let activeChildIndex = source.activeChildIndex,
           let active = container.children.getOrNil(atIndex: activeChildIndex)
        {
            active.markAsMostRecentChild()
        }
        return container
    }

    private static func collectWindowIds(_ container: ResolvedLayoutMemoryContainer) -> [UInt32] {
        container.children.flatMap { node -> [UInt32] in
            switch node {
                case .window(let windowId, _): [windowId]
                case .container(let nested): collectWindowIds(nested)
            }
        }
    }

    @MainActor
    private static func monitor(
        identity: String,
        profile: LayoutMemoryMonitorProfile,
    ) throws -> Monitor {
        for monitor in monitors {
            if try profile.identity(for: LayoutMemoryMonitorSnapshot(monitor)) == identity {
                return monitor
            }
        }
        throw LayoutMemoryRestoreError.monitorProfileChanged
    }
}
