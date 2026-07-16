import CryptoKit
import Foundation
import Common

enum LayoutMemoryExportError: Error, Equatable {
    case occupiedExcludedWorkspace(String)
    case noMonitorIdentity(String)
}

struct LayoutMemoryExporter {
    let configuration: CustomLayoutMemoryConfig

    @MainActor
    func export(label: String? = nil, pinned: Bool = false) async throws -> LayoutMemorySnapshot {
        for name in configuration.excludedWorkspaces {
            if Workspace.all.first(where: { $0.name == name })?.isEffectivelyEmpty == false {
                throw LayoutMemoryExportError.occupiedExcludedWorkspace(name)
            }
        }

        let profile = try currentLayoutMemoryMonitorProfile()
        let allWindows = Workspace.all.flatMap(\.allLeafWindowsRecursive)
        var references: [UInt32: LayoutMemoryWindowReference] = [:]
        var titles: [UInt32: String] = [:]
        for window in allWindows {
            let title = try await window.getTitle(.nonCancellable)
            titles[window.windowId] = title
            if !isTemporary(window: window, title: title) {
                references[window.windowId] = .init(
                    windowId: window.windowId,
                    bundleId: window.app.rawAppBundleId ?? "",
                    title: title,
                )
            }
        }

        let workspaceSnapshots = try Workspace.all
            .filter { !configuration.excludedWorkspaces.contains($0.name) }
            .map { workspace in
                let monitorIdentity = try profile.identity(for: LayoutMemoryMonitorSnapshot(workspace.workspaceMonitor))
                let root = workspace.children.compactMap { $0 as? TilingContainer }.singleOrNil()
                return LayoutMemoryWorkspaceSnapshot(
                    name: workspace.name,
                    monitorIdentity: monitorIdentity,
                    isVisible: workspace.isVisible,
                    root: exportRoot(root, references: references),
                )
            }

        var windowSnapshots: [LayoutMemoryWindowSnapshot] = []
        for workspace in Workspace.all where !configuration.excludedWorkspaces.contains(workspace.name) {
            for window in workspace.allLeafWindowsRecursive {
                guard let reference = references[window.windowId] else { continue }
                windowSnapshots.append(try await exportWindow(window, reference: reference, workspace: workspace, profile: profile))
            }
        }
        windowSnapshots.sort { $0.reference.windowId < $1.reference.windowId }

        let focusSnapshot = LayoutMemoryFocusSnapshot(
            focusedWindow: focus.windowOrNil.flatMap { references[$0.windowId] },
            focusedWorkspace: focus.workspace.name,
        )
        let fingerprint = try makeFingerprint(
            profile: profile,
            workspaces: workspaceSnapshots,
            windows: windowSnapshots,
            focus: focusSnapshot,
        )
        return .init(
            schemaVersion: LayoutMemorySnapshot.currentSchemaVersion,
            snapshotId: UUID(),
            createdAt: Date(),
            appVersion: aeroSpaceAppVersion,
            appBuildHash: gitHash,
            monitorProfile: profile,
            fingerprint: fingerprint,
            workspaces: workspaceSnapshots,
            windows: windowSnapshots,
            focus: focusSnapshot,
            label: label,
            isPinned: pinned,
        )
    }

    @MainActor
    private func isTemporary(window: Window, title: String) -> Bool {
        configuration.temporaryWindowTitleRegexSubstrings.contains { pattern in
            title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    @MainActor
    private func exportRoot(
        _ root: TilingContainer?,
        references: [UInt32: LayoutMemoryWindowReference],
    ) -> LayoutMemoryContainerSnapshot {
        guard let root else {
            return .init(
                orientation: config.defaultRootContainerOrientation == .vertical ? .vertical : .horizontal,
                layout: config.defaultRootContainerLayout.layoutMemoryValue,
                weight: 1,
                activeChildIndex: nil,
                children: [],
            )
        }
        return exportContainer(root, weight: 1, references: references)
    }

    @MainActor
    private func exportContainer(
        _ container: TilingContainer,
        weight: Double,
        references: [UInt32: LayoutMemoryWindowReference],
    ) -> LayoutMemoryContainerSnapshot {
        let included = container.children.filter {
            !($0 is Window) || references[($0 as? Window)?.windowId ?? 0] != nil
        }
        let rawWeights = included.map { child in
            max(Double(child.getWeight(container.orientation)), 0)
        }
        let total = rawWeights.reduce(0, +)
        let normalized = rawWeights.map { total > 0 ? $0 / total : 1 / Double(max(included.count, 1)) }
        let children = zip(included, normalized).compactMap { child, childWeight -> LayoutMemoryTreeNodeSnapshot? in
            switch child.nodeCases {
                case .window(let window):
                    return references[window.windowId].map { .window($0, weight: childWeight) }
                case .tilingContainer(let nested):
                    return .container(exportContainer(nested, weight: childWeight, references: references))
                default:
                    return nil
            }
        }
        let activeChildIndex = container.layout == .accordion
            ? container.mostRecentChild.flatMap { included.firstIndex(of: $0) }
            : nil
        return .init(
            orientation: container.orientation == .h ? .horizontal : .vertical,
            layout: container.layout.layoutMemoryValue,
            weight: weight,
            activeChildIndex: activeChildIndex,
            children: children,
        )
    }

    @MainActor
    private func exportWindow(
        _ window: Window,
        reference: LayoutMemoryWindowReference,
        workspace: Workspace,
        profile: LayoutMemoryMonitorProfile,
    ) async throws -> LayoutMemoryWindowSnapshot {
        let isNativeFullscreen = try await window.isMacosFullscreen(.nonCancellable)
        let isMinimized = try await window.isMacosMinimized(.nonCancellable)
        let isHidden = window.windowParentCases.isHiddenForLayoutMemory
        let state: LayoutMemoryWindowState = switch window.windowParentCases {
            case .floatingWindowsContainer: .floating
            case .macosFullscreenWindowsContainer: .nativeFullscreen
            case .macosHiddenAppsWindowsContainer: .hidden
            case .macosMinimizedWindowsContainer: .minimized
            case .tilingContainer: .tiling
            case .macosPopupWindowsContainer, .unbound: .floating
        }
        let geometry: LayoutMemoryFloatingGeometry?
        if state == .floating, let rect = try await window.getAxRect(.nonCancellable) {
            let monitor = rect.center.monitorApproximation
            let visible = monitor.visibleRect
            geometry = .init(
                monitorIdentity: try profile.identity(for: LayoutMemoryMonitorSnapshot(monitor)),
                normalizedVisibleFrame: .init(
                    x: Double((rect.topLeftX - visible.topLeftX) / max(visible.width, 1)),
                    y: Double((rect.topLeftY - visible.topLeftY) / max(visible.height, 1)),
                    width: Double(rect.width / max(visible.width, 1)),
                    height: Double(rect.height / max(visible.height, 1)),
                ),
                absoluteFrame: CodableRect(rect),
            )
        } else {
            geometry = nil
        }
        let floatingZIndex = state == .floating
            ? workspace.floatingWindows.firstIndex(of: window)
            : nil
        return .init(
            reference: reference,
            workspace: workspace.name,
            state: state,
            isAeroSpaceFullscreen: window.isFullscreen,
            noOuterGapsInFullscreen: window.noOuterGapsInFullscreen,
            floatingGeometry: geometry,
            floatingZIndex: floatingZIndex,
            isHidden: isHidden,
            isMinimized: isMinimized,
            isNativeFullscreen: isNativeFullscreen,
        )
    }

    private func makeFingerprint(
        profile: LayoutMemoryMonitorProfile,
        workspaces: [LayoutMemoryWorkspaceSnapshot],
        windows: [LayoutMemoryWindowSnapshot],
        focus: LayoutMemoryFocusSnapshot,
    ) throws -> String {
        struct Payload: Encodable {
            let profile: LayoutMemoryMonitorProfile
            let workspaces: [LayoutMemoryWorkspaceSnapshot]
            let windows: [LayoutMemoryWindowSnapshot]
            let focus: LayoutMemoryFocusSnapshot
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Payload(profile: profile, workspaces: workspaces, windows: windows, focus: focus))
        return SHA256.hash(data: data).reduce(into: "") { result, byte in
            if byte < 16 { result.append("0") }
            result.append(String(byte, radix: 16))
        }
    }
}

extension Layout {
    fileprivate var layoutMemoryValue: LayoutMemoryLayout {
        self == .tiles ? .tiles : .accordion
    }
}

extension WindowParentCases {
    fileprivate var isHiddenForLayoutMemory: Bool {
        if case .macosHiddenAppsWindowsContainer = self { return true }
        return false
    }
}
