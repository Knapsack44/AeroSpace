import Common
import Foundation

struct LayoutMemoryCommand: Command {
    let args: LayoutMemoryCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    @MainActor
    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        if LayoutMemoryCoordinator.shared == nil {
            switch args.action {
                case .status(let json):
                    return output(LayoutMemoryCoordinator.statusWhenUnavailable(), json: json, io: io)
                case .list(let json):
                    do {
                        return outputVersions(try LayoutMemoryCoordinator.listWhenUnavailable(), json: json, io: io)
                    } catch {
                        return .fail(io.err(String(describing: error)))
                    }
                default:
                    break
            }
        }
        guard let coordinator = LayoutMemoryCoordinator.shared else {
            return .fail(io.err(LayoutMemoryCoordinatorError.disabled.description))
        }
        do {
            switch args.action {
                case .status(let json):
                    return output(coordinator.status(), json: json, io: io)
                case .list(let json):
                    return outputVersions(try coordinator.listCurrentProfile(), json: json, io: io)
                case .snapshot(let label):
                    let stored = try await coordinator.snapshot(label: label)
                    return .succ(io.out(stored.snapshotId.uuidString))
                case .export(let outputPath):
                    try await coordinator.export(to: URL(filePath: outputPath))
                    return .succ
                case .restore(let input, let version, let dryRun, let json):
                    let report = try await coordinator.restore(
                        input: input.map { URL(filePath: $0) },
                        version: version,
                        dryRun: dryRun,
                    )
                    return output(report, json: json, io: io)
                case .pause:
                    try coordinator.setPaused(true)
                    return .succ
                case .resume:
                    try coordinator.setPaused(false)
                    return .succ
                case .togglePause:
                    try coordinator.togglePaused()
                    return .succ
                case .pin(let version, let label):
                    let signature = try currentLayoutMemoryMonitorProfile().signature
                    try coordinator.store.pin(signature: signature, version: version, label: label)
                    return .succ
                case .prefer(let version):
                    let signature = try currentLayoutMemoryMonitorProfile().signature
                    try coordinator.store.prefer(signature: signature, version: version)
                    return .succ
                case .unprefer:
                    let signature = try currentLayoutMemoryMonitorProfile().signature
                    try coordinator.store.unprefer(signature: signature)
                    return .succ
                case .deleteVersion(let version, let force):
                    let signature = try currentLayoutMemoryMonitorProfile().signature
                    try coordinator.store.deleteVersion(signature: signature, version: version, force: force)
                    return .succ
                case .deleteProfile(let signature, let force):
                    try coordinator.store.deleteProfile(signature: signature, force: force)
                    return .succ
                case .manualChangeBegin:
                    return .succ(io.out(coordinator.beginManualChange().uuidString))
                case .manualChangeEnd(let token):
                    try coordinator.endManualChange(token: token)
                    return .succ
            }
        } catch {
            return .fail(io.err(String(describing: error)))
        }
    }

    private func output<T: Encodable>(_ value: T, json: Bool, io: CmdIo) -> BinaryExitCode {
        if json {
            guard let encoded = JSONEncoder.aeroSpaceDefault.encodeToString(value) else {
                return .fail(io.err("Can't encode layout memory response"))
            }
            return .succ(io.out(encoded))
        }
        return .succ(io.out(String(describing: value)))
    }

    private func outputVersions(
        _ versions: [LayoutMemoryStoredVersion],
        json: Bool,
        io: CmdIo,
    ) -> BinaryExitCode {
        if json {
            return output(versions.map(LayoutMemoryVersionOutput.init), json: true, io: io)
        }
        return .succ(io.out(versions.map {
            "\($0.snapshotId) \($0.createdAt.ISO8601Format()) \($0.isPinned ? "pinned" : "regular") \($0.label ?? "")"
        }.joined(separator: "\n")))
    }
}

private struct LayoutMemoryVersionOutput: Encodable {
    // periphery:ignore - Serialized to JSON
    let id: UUID
    // periphery:ignore - Serialized to JSON
    let createdAt: Date
    // periphery:ignore - Serialized to JSON
    let fingerprint: String
    // periphery:ignore - Serialized to JSON
    let label: String?
    // periphery:ignore - Serialized to JSON
    let pinned: Bool

    init(_ version: LayoutMemoryStoredVersion) {
        id = version.snapshotId
        createdAt = version.createdAt
        fingerprint = version.fingerprint
        label = version.label
        pinned = version.isPinned
    }
}
