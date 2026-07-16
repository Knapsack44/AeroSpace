import Foundation
import Common

enum LayoutMemoryTransactionPhase: Equatable, Sendable {
    case idle
    case preflight
    case committing
}

@MainActor
final class LayoutMemoryRuntime {
    static let shared = LayoutMemoryRuntime()

    private(set) var phase: LayoutMemoryTransactionPhase = .idle
    private(set) var layoutGeneration: UInt64 = 0
    private(set) var lastLayoutMutationAt = Date.distantPast
    private(set) var queuedDetectedWindowIds: Set<UInt32> = []

    var suppressesCallbacks: Bool { phase == .committing }

    func noteLayoutMutation() {
        guard phase != .committing else { return }
        layoutGeneration &+= 1
        lastLayoutMutationAt = Date()
    }

    func beginPreflight() {
        check(phase == .idle)
        phase = .preflight
    }

    func beginCommit() {
        check(phase == .preflight)
        phase = .committing
    }

    func queueDetectedWindow(_ windowId: UInt32) {
        queuedDetectedWindowIds.insert(windowId)
    }

    func finish() -> Set<UInt32> {
        phase = .idle
        let queued = queuedDetectedWindowIds
        queuedDetectedWindowIds = []
        return queued
    }

    func resetForTests() {
        phase = .idle
        layoutGeneration = 0
        lastLayoutMutationAt = .distantPast
        queuedDetectedWindowIds = []
    }
}
