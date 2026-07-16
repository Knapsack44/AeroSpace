import CryptoKit
import Foundation

struct CodableRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: Rect) {
        self.init(
            x: Double(rect.topLeftX),
            y: Double(rect.topLeftY),
            width: Double(rect.width),
            height: Double(rect.height),
        )
    }

    fileprivate func normalized(relativeTo origin: CodableRect) -> CodableRect {
        .init(
            x: (x - origin.x).rounded(),
            y: (y - origin.y).rounded(),
            width: width.rounded(),
            height: height.rounded(),
        )
    }
}

struct LayoutMemoryMonitorSnapshot: Codable, Equatable, Sendable {
    let displayUuid: String?
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let normalizedName: String
    let frame: CodableRect
    let visibleFrame: CodableRect
    let backingScale: Double
    let rotationDegrees: Double
    let isMain: Bool

    fileprivate var stableIdentity: String? {
        if let displayUuid, !displayUuid.isEmpty {
            return "uuid:\(displayUuid.lowercased())"
        }
        if serialNumber != 0 {
            return "display:\(vendorNumber):\(modelNumber):\(serialNumber)"
        }
        let name = Self.normalizeName(normalizedName)
        return name.isEmpty ? nil : "name:\(name)"
    }

    fileprivate static func normalizeName(_ name: String) -> String {
        name
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    fileprivate func canonical(relativeTo mainFrame: CodableRect) throws -> Self {
        guard stableIdentity != nil else {
            throw LayoutMemoryMonitorProfileError.unstableIdentity(normalizedName)
        }
        return .init(
            displayUuid: displayUuid?.lowercased(),
            vendorNumber: vendorNumber,
            modelNumber: modelNumber,
            serialNumber: serialNumber,
            normalizedName: Self.normalizeName(normalizedName),
            frame: frame.normalized(relativeTo: mainFrame),
            visibleFrame: visibleFrame.normalized(relativeTo: mainFrame),
            backingScale: (backingScale * 100).rounded() / 100,
            rotationDegrees: rotationDegrees.rounded(),
            isMain: isMain,
        )
    }
}

struct LayoutMemoryMonitorProfile: Codable, Equatable, Sendable {
    let signature: String
    let monitors: [LayoutMemoryMonitorSnapshot]

    static func make(snapshots: [LayoutMemoryMonitorSnapshot]) throws -> Self {
        guard !snapshots.isEmpty else {
            throw LayoutMemoryMonitorProfileError.noMonitors
        }
        guard let main = snapshots.singleOrNil(where: \.isMain) else {
            throw LayoutMemoryMonitorProfileError.invalidMainMonitorCount
        }
        let canonical = try snapshots
            .map { try $0.canonical(relativeTo: main.frame) }
            .sorted {
                ($0.stableIdentity ?? "", $0.frame.x, $0.frame.y) <
                    ($1.stableIdentity ?? "", $1.frame.x, $1.frame.y)
            }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(canonical)
        let digest = SHA256.hash(data: data).reduce(into: "") { result, byte in
            if byte < 16 { result.append("0") }
            result.append(String(byte, radix: 16))
        }
        return .init(signature: digest, monitors: canonical)
    }
}

enum LayoutMemoryMonitorProfileError: Error, Equatable {
    case noMonitors
    case invalidMainMonitorCount
    case unstableIdentity(String)
}

extension LayoutMemoryMonitorSnapshot {
    @MainActor
    init(_ monitor: Monitor) {
        displayUuid = monitor.displayUuid
        vendorNumber = monitor.vendorNumber
        modelNumber = monitor.modelNumber
        serialNumber = monitor.serialNumber
        normalizedName = monitor.name
        frame = CodableRect(monitor.rect)
        visibleFrame = CodableRect(monitor.visibleRect)
        backingScale = monitor.backingScale
        rotationDegrees = monitor.rotationDegrees
        isMain = monitor.isMain
    }
}

@MainActor
func currentLayoutMemoryMonitorProfile() throws -> LayoutMemoryMonitorProfile {
    try .make(snapshots: monitors.map(LayoutMemoryMonitorSnapshot.init))
}
