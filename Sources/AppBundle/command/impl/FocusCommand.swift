import AppKit
import Common

struct FocusCommand: Command {
    let args: FocusCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        if let window = target.windowOrNil, await shouldFailBecauseFullscreen_nonCancellable(
            window: window,
            failIfFullscreen: args.failIfFullscreen,
            failIfMacosNativeFullscreen: args.failIfMacosNativeFullscreen,
        ) {
            return .fail
        }
        // todo bug: floating windows break mru
        let floatingWindows = args.floatingAsTiling ? await makeFloatingWindowsSeenAsTiling(workspace: target.workspace) : []
        defer {
            if args.floatingAsTiling {
                restoreFloatingWindows(floatingWindows: floatingWindows, workspace: target.workspace)
            }
        }

        switch args.resolvedTarget {
            case .direction(let direction):
                let window = target.windowOrNil
                if let (parent, ownIndex) = window?.closestParent(hasChildrenInDirection: direction, withLayout: .tiles) {
                    guard let windowToFocus = parent.children[ownIndex + direction.focusOffset]
                        .findLeafWindowRecursive(snappedTo: direction.opposite) else { return .fail(io.err(bugPrompt())) }
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return hitWorkspaceBoundaries(target, io, args, direction)
                }
            case .windowId(let windowId):
                if let windowToFocus = Window.get(byId: windowId) {
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return .fail(io.err("Can't find window with ID \(windowId)"))
                }
            case .dfsIndex(let dfsIndex):
                if let windowToFocus = target.workspace.rootTilingContainer.allLeafWindowsRecursive.getOrNil(atIndex: Int(dfsIndex)) {
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return .fail(io.err("Can't find window with DFS index \(dfsIndex)"))
                }
            case .dfsRelative(let nextPrev):
                let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let currentIndex = windows.firstIndex(where: { $0 == target.windowOrNil }) else {
                    return .fail
                }
                var targetIndex = switch nextPrev {
                    case .dfsNext: currentIndex + 1
                    case .dfsPrev: currentIndex - 1
                }
                if !(0 ..< windows.count).contains(targetIndex) {
                    switch args.boundariesAction {
                        case .stop: return .succ
                        case .fail: return .fail
                        case .wrapAroundTheWorkspace: targetIndex = (targetIndex + windows.count) % windows.count
                        case .wrapAroundAllMonitors: return .fail(io.err(bugPrompt("Must be discarded by args parser")))
                    }
                }
                return .from(bool: windows[targetIndex].focusWindow())
            case .containerRelative(let nextPrev):
                guard let window = target.windowOrNil else {
                    return .fail(io.err(noWindowIsFocused))
                }
                return .from(bool: focusInAncestorContainer(window, nextPrev: nextPrev))
            case .containerMruRelative(let nextPrev):
                guard let window = target.windowOrNil else {
                    return .fail(io.err(noWindowIsFocused))
                }
                return .from(bool: focusInAncestorContainerMru(window, nextPrev: nextPrev, now: .now))
        }
    }
}

@MainActor private func focusInAncestorContainer(_ window: Window, nextPrev: ContainerFocusNextPrev) -> Bool {
    guard let ancestor = window.parentsWithSelf
        .first(where: { $0.allLeafWindowsRecursive.count > 1 })
    else { return true }

    let windows = ancestor.allLeafWindowsRecursive
    guard let currentIndex = windows.firstIndex(of: window) else { return true }

    let targetIndex = switch nextPrev {
        case .containerNext: currentIndex + 1
        case .containerPrev: currentIndex - 1
    }
    let wrappedIndex = (targetIndex + windows.count) % windows.count
    return windows[wrappedIndex].focusWindow()
}

private let containerMruFocusCycleTimeout = Duration.milliseconds(750)

@MainActor private var containerMruFocusCycle: ContainerMruFocusCycle?

private struct ContainerMruFocusCycle {
    let ancestor: TreeNode
    let windowIds: [UInt32]
    var currentIndex: Int
    var lastInvocation: ContinuousClock.Instant
    var focusSequence: UInt64

    func isValid(
        ancestor currentAncestor: TreeNode,
        windowIds currentWindowIds: [UInt32],
        focusedWindowId: UInt32,
        now: ContinuousClock.Instant,
        focusSequence currentFocusSequence: UInt64,
    ) -> Bool {
        ancestor === currentAncestor
            && windowIds.count == currentWindowIds.count
            && Set(windowIds) == Set(currentWindowIds)
            && windowIds.getOrNil(atIndex: currentIndex) == focusedWindowId
            && focusSequence == currentFocusSequence
            && lastInvocation.duration(to: now) <= containerMruFocusCycleTimeout
    }
}

@MainActor
func resetContainerMruFocusCycle() {
    containerMruFocusCycle = nil
}

@MainActor
func focusInAncestorContainerMru(
    _ window: Window,
    nextPrev: ContainerMruFocusNextPrev,
    now: ContinuousClock.Instant,
) -> Bool {
    guard let ancestor = window.parentsWithSelf.first(where: { $0.allLeafWindowsRecursive.count > 1 }) else {
        resetContainerMruFocusCycle()
        return true
    }

    let windows = ancestor.allLeafWindowsRecursive
    let windowIds = windows.map(\.windowId)
    var cycle: ContainerMruFocusCycle = if let existingCycle = containerMruFocusCycle, existingCycle.isValid(
        ancestor: ancestor,
        windowIds: windowIds,
        focusedWindowId: window.windowId,
        now: now,
        focusSequence: focusSequence,
    ) {
        existingCycle
    } else {
        makeContainerMruFocusCycle(ancestor: ancestor, windows: windows, current: window, now: now)
    }

    let offset = switch nextPrev {
        case .containerMruNext: 1
        case .containerMruPrev: -1
    }
    cycle.currentIndex = (cycle.currentIndex + offset + cycle.windowIds.count) % cycle.windowIds.count
    guard let target = windows.first(where: { $0.windowId == cycle.windowIds[cycle.currentIndex] }) else {
        resetContainerMruFocusCycle()
        return true
    }
    guard target.focusWindow() else {
        resetContainerMruFocusCycle()
        return false
    }

    cycle.lastInvocation = now
    cycle.focusSequence = focusSequence
    containerMruFocusCycle = cycle
    return true
}

@MainActor
private func makeContainerMruFocusCycle(
    ancestor: TreeNode,
    windows: [Window],
    current: Window,
    now: ContinuousClock.Instant,
) -> ContainerMruFocusCycle {
    let windowIds = windows.enumerated().sorted {
        $0.element.focusSequence == $1.element.focusSequence
            ? $0.offset < $1.offset
            : $0.element.focusSequence > $1.element.focusSequence
    }.map(\.element.windowId)
    return ContainerMruFocusCycle(
        ancestor: ancestor,
        windowIds: windowIds,
        currentIndex: windowIds.firstIndex(of: current.windowId).orDie(),
        lastInvocation: now,
        focusSequence: focusSequence,
    )
}

@MainActor private func hitWorkspaceBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
) -> BinaryExitCode {
    switch args.boundaries {
        case .workspace:
            return switch args.boundariesAction {
                case .stop: .succ
                case .fail: .fail
                case .wrapAroundTheWorkspace: wrapAroundTheWorkspace(target, io, direction)
                case .wrapAroundAllMonitors: .fail(io.err("Must be discarded by args parser"))
            }
        case .allMonitorsOuterFrame:
            let currentMonitor = target.workspace.workspaceMonitor
            guard let (monitors, index) = currentMonitor.findRelativeMonitor(inDirection: direction) else {
                return .fail(io.err(bugPrompt("Should never happen. Can't find the current monitor")))
            }

            if let targetMonitor = monitors.getOrNil(atIndex: index) {
                return .from(bool: targetMonitor.activeWorkspace.focusWorkspace())
            } else {
                guard let wrapped = monitors.get(wrappingIndex: index) else { return .fail(io.err(bugPrompt("\(index) \(monitors)"))) }
                return hitAllMonitorsOuterFrameBoundaries(target, io, args, direction, wrapped)
            }
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
    _ wrappedMonitor: Monitor,
) -> BinaryExitCode {
    switch args.boundariesAction {
        case .stop:
            return .succ
        case .fail:
            return .fail
        case .wrapAroundTheWorkspace:
            return wrapAroundTheWorkspace(target, io, direction)
        case .wrapAroundAllMonitors:
            wrappedMonitor.activeWorkspace.findLeafWindowRecursive(snappedTo: direction.opposite)?.markAsMostRecentChild()
            return .from(bool: wrappedMonitor.activeWorkspace.focusWorkspace())
    }
}

@MainActor private func wrapAroundTheWorkspace(_ target: LiveFocus, _ io: CmdIo, _ direction: CardinalDirection) -> BinaryExitCode {
    guard let windowToFocus = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite) else {
        return .fail(io.err(noWindowIsFocused))
    }
    return .from(bool: windowToFocus.focusWindow())
}

@MainActor private func makeFloatingWindowsSeenAsTiling(workspace: Workspace) async -> [FloatingWindowData] {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    var _floatingWindows: [FloatingWindowData] = []
    for window in workspace.floatingWindows {
        // todo bug: we shouldn't access ax api here. What if the window was moved but it wasn't committed to ax yet?
        guard let center = try? await window.getCenter(.nonCancellable) else { continue }

        let tilingParent: TilingContainer
        let index: Int
        if let target = center.coerce(in: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)?
            .findWindowRecursively(in: workspace.rootTilingContainer, virtual: true, fullscreenCoversAll: false)
        {
            guard let targetCenter = try? await target.getCenter(.nonCancellable) else { continue }
            guard let _tilingParent = target.parent as? TilingContainer else { continue }
            tilingParent = _tilingParent
            index = switch tilingParent.layout {
                case .tiles:
                    center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                        ? target.ownIndex.orDie() + 1
                        : target.ownIndex.orDie()
                case .accordion:
                    center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                        ? tilingParent.children.count
                        : 0
            }
        } else {
            index = 0
            tilingParent = workspace.rootTilingContainer
        }

        let data = window.unbindFromParent()
        let floatingWindowData = FloatingWindowData(
            window: window,
            center: center,
            tilingParent: tilingParent,
            adaptiveWeight: data.adaptiveWeight,
            index: index,
        )
        _floatingWindows.append(floatingWindowData)
    }
    let floatingWindows: [FloatingWindowData] = _floatingWindows.sortedBy { $0.center.getProjection($0.tilingParent.orientation) }.reversed()

    for floating in floatingWindows { // Make floating windows be seen as tiling
        floating.window.bind(to: floating.tilingParent, adaptiveWeight: 1, index: floating.index)
    }
    return floatingWindows
}

@MainActor private func restoreFloatingWindows(floatingWindows: [FloatingWindowData], workspace: Workspace) {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    for floating in floatingWindows {
        floating.window.bind(to: workspace.floatingWindowsContainer, adaptiveWeight: floating.adaptiveWeight, index: INDEX_BIND_LAST)
    }
}

private struct FloatingWindowData {
    let window: Window
    let center: CGPoint

    let tilingParent: TilingContainer
    let adaptiveWeight: CGFloat
    let index: Int
}

extension TreeNode {
    @MainActor
    func findLeafWindowRecursive(snappedTo direction: CardinalDirection) -> Window? {
        switch nodeCases {
            case .workspace(let workspace):
                return workspace.rootTilingContainer.findLeafWindowRecursive(snappedTo: direction)
            case .window(let window):
                return window
            case .tilingContainer(let container):
                switch container.layout {
                    case .accordion:
                        return mostRecentChild?.findLeafWindowRecursive(snappedTo: direction)
                    case .tiles:
                        if direction.orientation == container.orientation {
                            return (direction.isPositive ? container.children.last : container.children.first)?
                                .findLeafWindowRecursive(snappedTo: direction)
                        } else {
                            return mostRecentChild?.findLeafWindowRecursive(snappedTo: direction)
                        }
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer,
                 .floatingWindowsContainer:
                die("Impossible")
        }
    }
}
