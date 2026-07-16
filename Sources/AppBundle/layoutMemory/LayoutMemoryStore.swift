import Darwin
import Foundation

struct LayoutMemoryStoredVersion: Equatable, Sendable {
    let url: URL
    let snapshotId: UUID
    let createdAt: Date
    let fingerprint: String
    let label: String?
    let isPinned: Bool
}

enum LayoutMemoryStoreError: Error {
    case unsupportedSchema(Int)
    case tooManyWindows(Int)
    case snapshotTooLarge(Int)
    case invalidSnapshot
}

final class LayoutMemoryStore {
    static let maximumWindowCount = 500
    static let maximumSnapshotBytes = 10 * 1024 * 1024

    let rootUrl: URL
    let historyLimit: Int
    private let fileManager: FileManager

    init(rootUrl: URL, historyLimit: Int, fileManager: FileManager = .default) {
        self.rootUrl = rootUrl
        self.historyLimit = historyLimit
        self.fileManager = fileManager
    }

    func save(_ snapshot: LayoutMemorySnapshot) throws -> LayoutMemoryStoredVersion {
        try validate(snapshot)
        try ensureDirectory(rootUrl)
        let snapshotsUrl = profileSnapshotsUrl(signature: snapshot.monitorProfile.signature)
        try ensureDirectory(snapshotsUrl)

        if !snapshot.isPinned,
           let identical = try list(signature: snapshot.monitorProfile.signature)
           .first(where: { !$0.isPinned && $0.fingerprint == snapshot.fingerprint })
        {
            return identical
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= Self.maximumSnapshotBytes else {
            throw LayoutMemoryStoreError.snapshotTooLarge(data.count)
        }

        let fileName = "\(Int(snapshot.createdAt.timeIntervalSince1970 * 1000))-\(snapshot.snapshotId.uuidString).json"
        let destination = snapshotsUrl.appending(component: fileName)
        let temporary = snapshotsUrl.appending(component: ".\(fileName).tmp")
        try data.write(to: temporary, options: [])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        _ = try loadSnapshot(at: temporary)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporary, to: destination)
        try syncDirectory(snapshotsUrl)
        try rotateRegularSnapshots(signature: snapshot.monitorProfile.signature)
        return version(snapshot, at: destination)
    }

    func loadSnapshot(at url: URL) throws -> LayoutMemorySnapshot {
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumSnapshotBytes else {
            throw LayoutMemoryStoreError.snapshotTooLarge(data.count)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LayoutMemorySnapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }

    func list(signature: String) throws -> [LayoutMemoryStoredVersion] {
        let directory = profileSnapshotsUrl(signature: signature)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { url in
            guard let snapshot = try? loadSnapshot(at: url) else { return nil }
            return version(snapshot, at: url)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func validate(_ snapshot: LayoutMemorySnapshot) throws {
        guard snapshot.schemaVersion == LayoutMemorySnapshot.currentSchemaVersion else {
            throw LayoutMemoryStoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard snapshot.windows.count <= Self.maximumWindowCount else {
            throw LayoutMemoryStoreError.tooManyWindows(snapshot.windows.count)
        }
        guard snapshot.monitorProfile.signature == (try LayoutMemoryMonitorProfile.make(
            snapshots: snapshot.monitorProfile.monitors,
        )).signature else {
            throw LayoutMemoryStoreError.invalidSnapshot
        }
    }

    private func rotateRegularSnapshots(signature: String) throws {
        let regular = try list(signature: signature).filter { !$0.isPinned }
        for version in regular.dropFirst(historyLimit) {
            try fileManager.removeItem(at: version.url)
        }
    }

    private func profileSnapshotsUrl(signature: String) -> URL {
        rootUrl
            .appending(component: "profiles")
            .appending(component: signature)
            .appending(component: "snapshots")
    }

    private func version(_ snapshot: LayoutMemorySnapshot, at url: URL) -> LayoutMemoryStoredVersion {
        .init(
            url: url,
            snapshotId: snapshot.snapshotId,
            createdAt: snapshot.createdAt,
            fingerprint: snapshot.fingerprint,
            label: snapshot.label,
            isPinned: snapshot.isPinned,
        )
    }

    private func ensureDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700],
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        var parent = url.deletingLastPathComponent()
        while parent.path.hasPrefix(rootUrl.path), parent.path != rootUrl.deletingLastPathComponent().path {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            if parent == rootUrl { break }
            parent.deleteLastPathComponent()
        }
    }

    private func syncDirectory(_ url: URL) throws {
        let descriptor = unsafe open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        _ = fsync(descriptor)
    }
}
