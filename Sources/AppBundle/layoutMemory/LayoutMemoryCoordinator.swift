import AppKit
import Common
import Foundation

enum LayoutMemoryCoordinatorError: Error, CustomStringConvertible {
    case disabled
    case paused
    case noSnapshot
    case failureCooldown
    case invalidManualChangeToken

    var description: String {
        switch self {
            case .disabled: "Layout memory is disabled or unavailable for this AeroSpace app"
            case .paused: "Automatic layout memory is paused"
            case .noSnapshot: "No snapshot exists for the current monitor profile"
            case .failureCooldown: "Automatic restore is cooling down after a previous failure"
            case .invalidManualChangeToken: "Unknown manual layout change token"
        }
    }
}

struct LayoutMemoryStatus: Codable, Equatable, Sendable {
    // periphery:ignore - Serialized to JSON
    let available: Bool
    // periphery:ignore - Serialized to JSON
    let enabled: Bool
    // periphery:ignore - Serialized to JSON
    let mode: String
    // periphery:ignore - Serialized to JSON
    let paused: Bool
    // periphery:ignore - Serialized to JSON
    let monitorSignature: String?
    // periphery:ignore - Serialized to JSON
    let snapshotCount: Int
    // periphery:ignore - Serialized to JSON
    let pendingTransition: Bool
    // periphery:ignore - Serialized to JSON
    let manualChangeDepth: Int
}

struct LayoutMemoryRestoreReport: Codable, Equatable, Sendable {
    // periphery:ignore - Serialized to JSON
    let dryRun: Bool
    let result: String
    let matchedWindows: Int
    // periphery:ignore - Serialized to JSON
    let missingWindows: Int
    // periphery:ignore - Serialized to JSON
    let ambiguousWindows: Int
    let mutated: Bool
    let warnings: [String]
}

@MainActor
final class LayoutMemoryCoordinator {
    static private(set) var shared: LayoutMemoryCoordinator?

    let configuration: CustomLayoutMemoryConfig
    let store: LayoutMemoryStore
    private let exporter: LayoutMemoryExporter
    private let stateUrl: URL
    private let logUrl: URL
    private var observer: LayoutMemorySystemObserver?
    private var transitionTask: Task<Void, Never>?
    private var paused: Bool
    private var systemActive = true
    private var transitionStartedAt = Date()
    private var lastSnapshotAt = Date.distantPast
    private var manualChangeTokens: Set<UUID> = []
    private var transitionGate = LayoutMemoryTransitionGate()
    private var failureCooldownUntilByProfile: [String: Date] = [:]
    private var automaticRestoreEpoch: UInt64 = 0

    static func startIfEnabled() {
        guard isCustomLayoutMemoryRuntimeEnabled(
            appId: aeroSpaceAppId,
            isReadOnly: serverArgs.isReadOnly,
            config: config.customLayoutMemory,
        ) else {
            shared = nil
            return
        }
        let coordinator = LayoutMemoryCoordinator(configuration: config.customLayoutMemory)
        shared = coordinator
        coordinator.start()
    }

    static func statusWhenUnavailable() -> LayoutMemoryStatus {
        let isCustomApp = aeroSpaceAppId == customAeroSpaceAppId
        let profile = isCustomApp ? try? currentLayoutMemoryMonitorProfile() : nil
        let snapshotCount = profile.flatMap {
            try? makeStore(configuration: config.customLayoutMemory).list(signature: $0.signature).count
        } ?? 0
        return .init(
            available: isCustomApp,
            enabled: false,
            mode: "disabled",
            paused: false,
            monitorSignature: profile?.signature,
            snapshotCount: snapshotCount,
            pendingTransition: false,
            manualChangeDepth: 0,
        )
    }

    static func listWhenUnavailable() throws -> [LayoutMemoryStoredVersion] {
        guard aeroSpaceAppId == customAeroSpaceAppId else { return [] }
        let profile = try currentLayoutMemoryMonitorProfile()
        return try makeStore(configuration: config.customLayoutMemory).list(signature: profile.signature)
    }

    init(configuration: CustomLayoutMemoryConfig) {
        self.configuration = configuration
        let root = Self.storeRoot
        self.store = Self.makeStore(configuration: configuration)
        self.exporter = LayoutMemoryExporter(configuration: configuration)
        self.stateUrl = root.appending(component: "state.json")
        self.logUrl = root.appending(component: "layout-memory.log")
        self.paused = (try? Self.readPauseState(stateUrl)) ?? false
    }

    private static var storeRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(component: "Library/Application Support")
            .appending(component: customAeroSpaceAppName)
            .appending(component: "layout-memory")
    }

    private static func makeStore(configuration: CustomLayoutMemoryConfig) -> LayoutMemoryStore {
        LayoutMemoryStore(rootUrl: storeRoot, historyLimit: configuration.historyLimit)
    }

    func start() {
        observer = LayoutMemorySystemObserver { [weak self] event in
            self?.handle(event)
        }
        observer?.start()
        scheduleTransition(reason: "app-started")
        Task.startUnstructured { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await self?.tick()
            }
        }
    }

    func status() -> LayoutMemoryStatus {
        let profile = try? currentLayoutMemoryMonitorProfile()
        return .init(
            available: true,
            enabled: true,
            mode: configuration.mode.rawValue,
            paused: paused,
            monitorSignature: profile?.signature,
            snapshotCount: profile.flatMap { try? store.list(signature: $0.signature).count } ?? 0,
            pendingTransition: transitionTask != nil,
            manualChangeDepth: manualChangeTokens.count,
        )
    }

    func listCurrentProfile() throws -> [LayoutMemoryStoredVersion] {
        let profile = try currentLayoutMemoryMonitorProfile()
        return try store.list(signature: profile.signature)
    }

    func snapshot(label: String? = nil) async throws -> LayoutMemoryStoredVersion {
        let snapshot = try await exporter.export(label: label, pinned: label != nil)
        let stored = try store.save(snapshot)
        lastSnapshotAt = Date()
        failureCooldownUntilByProfile[snapshot.monitorProfile.signature] = nil
        log("snapshot \(stored.snapshotId) profile=\(snapshot.monitorProfile.signature)")
        return stored
    }

    func export(to output: URL) async throws {
        let snapshot = try await exporter.export()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: output, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
    }

    func restore(
        input: URL? = nil,
        version: UUID? = nil,
        dryRun: Bool,
        automatic: Bool = false,
    ) async throws -> LayoutMemoryRestoreReport {
        let restoreEpoch = automaticRestoreEpoch
        if automatic, paused || !manualChangeTokens.isEmpty {
            throw LayoutMemoryCoordinatorError.paused
        }
        let profile = try currentLayoutMemoryMonitorProfile()
        if automatic,
           let cooldownUntil = failureCooldownUntilByProfile[profile.signature],
           cooldownUntil > Date()
        {
            throw LayoutMemoryCoordinatorError.failureCooldown
        }
        let snapshot: LayoutMemorySnapshot
        if let input {
            snapshot = try store.loadSnapshot(at: input)
        } else {
            guard let selected = try store.selectedSnapshot(signature: profile.signature, version: version) else {
                throw LayoutMemoryCoordinatorError.noSnapshot
            }
            snapshot = selected
        }
        if let current = try? await exporter.export(), current.fingerprint == snapshot.fingerprint {
            return .init(
                dryRun: dryRun,
                result: LayoutMemoryRestoreResultKind.noOp.rawValue,
                matchedWindows: snapshot.windows.count,
                missingWindows: 0,
                ambiguousWindows: 0,
                mutated: false,
                warnings: [],
            )
        }

        let live = try await liveWindows()
        let matches = LayoutMemoryWindowMatcher.match(stored: snapshot.windows, live: live.map(\.window))
        let plan = try LayoutMemoryRestorePlanner.plan(
            snapshot: snapshot,
            currentMonitorSignature: profile.signature,
            expectedLayoutGeneration: LayoutMemoryRuntime.shared.layoutGeneration,
            matches: matches,
            liveWindows: live.map(\.state),
            automatic: automatic,
        )
        if dryRun {
            return report(plan: plan, matches: matches, dryRun: true, mutated: false, warnings: [])
        }
        if automatic, paused || !manualChangeTokens.isEmpty || restoreEpoch != automaticRestoreEpoch {
            throw LayoutMemoryCoordinatorError.paused
        }
        let result = try await LayoutMemoryRestorer.restore(plan)
        transitionStartedAt = Date()
        log("restore \(snapshot.snapshotId) result=\(result.kind.rawValue)")
        return report(
            plan: plan,
            matches: matches,
            dryRun: false,
            mutated: result.mutated,
            warnings: result.warnings,
        )
    }

    func setPaused(_ target: Bool) throws {
        paused = target
        automaticRestoreEpoch &+= 1
        try persistPauseState()
        transitionTask?.cancel()
        transitionTask = nil
        transitionGate.reset()
        play(target ? configuration.pauseSound : configuration.resumeSound)
        log(target ? "paused" : "resumed")
    }

    func togglePaused() throws {
        try setPaused(!paused)
    }

    func beginManualChange() -> UUID {
        automaticRestoreEpoch &+= 1
        transitionTask?.cancel()
        transitionTask = nil
        transitionGate.reset()
        let token = UUID()
        manualChangeTokens.insert(token)
        log("manual-change-begin \(token)")
        return token
    }

    func endManualChange(token: UUID) throws {
        guard manualChangeTokens.remove(token) != nil else {
            throw LayoutMemoryCoordinatorError.invalidManualChangeToken
        }
        transitionStartedAt = Date()
        LayoutMemoryRuntime.shared.noteLayoutMutation()
        log("manual-change-end \(token)")
    }

    func handle(_ event: LayoutMemoryEvent) {
        switch event {
            case .willSleep, .screenLocked, .sessionResigned:
                systemActive = false
                transitionTask?.cancel()
                transitionTask = nil
                Task.startUnstructured { [weak self] in
                    try? await self?.snapshotIfEligible()
                }
            case .didWake, .screenUnlocked, .sessionBecameActive:
                systemActive = true
                scheduleTransition(reason: event.rawValue)
            case .monitorParametersChanged:
                scheduleTransition(reason: event.rawValue)
        }
    }

    private func scheduleTransition(reason: String) {
        guard let candidate = try? currentLayoutMemoryMonitorProfile() else {
            log("transition \(reason) ignored: monitor profile unavailable")
            return
        }
        if transitionTask != nil, !transitionGate.request(signature: candidate.signature, at: Date()) {
            log("transition \(reason) coalesced profile=\(candidate.signature)")
            return
        }
        transitionTask?.cancel()
        transitionStartedAt = Date()
        _ = transitionGate.request(signature: candidate.signature, at: Date())
        transitionTask = Task.startUnstructured { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(configuration.topologySampleIntervalMs))
            guard !Task.isCancelled,
                  let second = try? currentLayoutMemoryMonitorProfile(),
                  candidate.signature == second.signature
            else {
                if !Task.isCancelled {
                    transitionTask = nil
                    transitionGate.reset()
                    scheduleTransition(reason: "topology-recheck")
                }
                return
            }
            let remaining = max(configuration.stabilityDelayMs - configuration.topologySampleIntervalMs, 0)
            try? await Task.sleep(for: .milliseconds(remaining))
            guard !Task.isCancelled else { return }
            guard systemActive, !paused, manualChangeTokens.isEmpty else {
                transitionTask = nil
                transitionGate.reset()
                return
            }
            guard let finalProfile = try? currentLayoutMemoryMonitorProfile(),
                  finalProfile.signature == candidate.signature
            else {
                transitionTask = nil
                transitionGate.reset()
                scheduleTransition(reason: "topology-recheck")
                return
            }
            transitionTask = nil
            transitionGate.clearCandidate()
            do {
                switch configuration.mode {
                    case .automatic:
                        let report = try await restore(dryRun: false, automatic: true)
                        if report.mutated {
                            play(configuration.successSound)
                        }
                    case .shadow:
                        let report = try await restore(dryRun: true, automatic: true)
                        log("shadow-restore \(report.result) matched=\(report.matchedWindows)")
                    case .manual:
                        break
                }
                transitionGate.reset()
            } catch LayoutMemoryCoordinatorError.noSnapshot {
                transitionGate.reset()
                log("learn profile \(candidate.signature)")
            } catch LayoutMemoryCoordinatorError.failureCooldown {
                transitionGate.reset()
                log("transition \(reason) skipped during failure cooldown profile=\(candidate.signature)")
            } catch LayoutMemoryRestorePlanningError.nativeFullscreenActive {
                if !transitionGate.hasExceededDeferral(
                    at: Date(),
                    seconds: configuration.nativeFullscreenDeferralSeconds,
                ) {
                    transitionTask = nil
                    scheduleTransition(reason: "native-fullscreen-deferral")
                } else {
                    transitionGate.reset()
                    log("transition \(reason) abandoned after native fullscreen deferral")
                }
            } catch LayoutMemoryRestoreError.monitorProfileChanged {
                transitionGate.reset()
                log("transition \(reason) aborted because monitor topology changed")
            } catch LayoutMemoryRestoreError.layoutChanged, LayoutMemoryCoordinatorError.paused {
                transitionGate.reset()
                log("transition \(reason) aborted because layout automation was superseded")
            } catch {
                transitionGate.reset()
                log("transition \(reason) failed: \(error)")
                if configuration.mode == .automatic {
                    failureCooldownUntilByProfile[candidate.signature] = Date()
                        .addingTimeInterval(Double(configuration.failureCooldownSeconds))
                    play(configuration.failureSound)
                }
            }
        }
    }

    private func tick() async {
        guard systemActive, !paused, manualChangeTokens.isEmpty else { return }
        try? await snapshotIfEligible()
    }

    private func snapshotIfEligible() async throws {
        let now = Date()
        guard now.timeIntervalSince(transitionStartedAt) >= Double(configuration.postTransitionSaveDelaySeconds),
              now.timeIntervalSince(LayoutMemoryRuntime.shared.lastLayoutMutationAt) >= Double(configuration.layoutIdleSeconds),
              now.timeIntervalSince(lastSnapshotAt) >= Double(configuration.snapshotIntervalSeconds)
        else {
            return
        }
        _ = try await snapshot()
    }

    private func liveWindows() async throws -> [(window: LayoutMemoryLiveWindow, state: LayoutMemoryLiveWindowState)] {
        var result: [(LayoutMemoryLiveWindow, LayoutMemoryLiveWindowState)] = []
        for workspace in Workspace.all {
            for window in workspace.allLeafWindowsRecursive {
                let title = try await window.getTitle(.nonCancellable)
                let state: LayoutMemoryWindowState = switch window.windowParentCases {
                    case .tilingContainer: .tiling
                    case .floatingWindowsContainer: .floating
                    case .macosHiddenAppsWindowsContainer: .hidden
                    case .macosMinimizedWindowsContainer: .minimized
                    case .macosFullscreenWindowsContainer: .nativeFullscreen
                    case .macosPopupWindowsContainer, .unbound: .floating
                }
                result.append((
                    .init(windowId: window.windowId, bundleId: window.app.rawAppBundleId ?? "", title: title),
                    .init(
                        windowId: window.windowId,
                        workspace: workspace.name,
                        state: state,
                        isNativeFullscreen: try await window.isMacosFullscreen(.nonCancellable),
                    ),
                ))
            }
        }
        return result
    }

    private func report(
        plan: ResolvedLayoutMemoryPlan,
        matches: LayoutMemoryWindowMatchResult,
        dryRun: Bool,
        mutated: Bool,
        warnings: [String],
    ) -> LayoutMemoryRestoreReport {
        .init(
            dryRun: dryRun,
            result: plan.resultKind.rawValue,
            matchedWindows: matches.matches.count,
            missingWindows: matches.missing.count,
            ambiguousWindows: matches.ambiguous.count,
            mutated: mutated,
            warnings: warnings,
        )
    }

    private func persistPauseState() throws {
        try FileManager.default.createDirectory(
            at: stateUrl.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700],
        )
        let data = try JSONEncoder().encode(paused)
        try data.write(to: stateUrl, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateUrl.path)
    }

    private static func readPauseState(_ url: URL) throws -> Bool {
        try JSONDecoder().decode(Bool.self, from: Data(contentsOf: url))
    }

    private func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        try? FileManager.default.createDirectory(
            at: logUrl.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700],
        )
        if !FileManager.default.fileExists(atPath: logUrl.path) {
            _ = FileManager.default.createFile(
                atPath: logUrl.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600],
            )
        }
        if let handle = try? FileHandle(forWritingTo: logUrl) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        }
    }

    private func play(_ path: String) {
        guard configuration.playSoundAfterAutoRestore else { return }
        NSSound(contentsOfFile: path, byReference: true)?.play()
    }
}

enum LayoutMemoryEvent: String, Sendable {
    case monitorParametersChanged
    case willSleep
    case didWake
    case screenLocked
    case screenUnlocked
    case sessionResigned
    case sessionBecameActive
}

struct LayoutMemoryTransitionGate: Equatable, Sendable {
    private(set) var candidateSignature: String?
    private(set) var startedAt: Date?

    mutating func request(signature: String, at now: Date) -> Bool {
        if candidateSignature == signature {
            return false
        }
        if candidateSignature != nil || startedAt == nil {
            startedAt = now
        }
        candidateSignature = signature
        return true
    }

    mutating func clearCandidate() {
        candidateSignature = nil
    }

    mutating func reset() {
        candidateSignature = nil
        startedAt = nil
    }

    func hasExceededDeferral(at now: Date, seconds: Int) -> Bool {
        guard let startedAt else { return false }
        return now.timeIntervalSince(startedAt) >= Double(seconds)
    }
}
