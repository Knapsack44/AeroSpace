import Foundation

package struct FailedRegistrationBackoff<Key: Hashable> {
    let delay: TimeInterval
    private var retryAfterByKey: [Key: Date] = [:]

    package init(delay: TimeInterval) {
        self.delay = delay
    }

    package mutating func shouldAttempt(_ key: Key, now: Date) -> Bool {
        guard let retryAfter = retryAfterByKey[key] else { return true }
        if retryAfter > now { return false }
        retryAfterByKey[key] = nil
        return true
    }

    package mutating func recordFailure(_ key: Key, now: Date) {
        retryAfterByKey[key] = now.addingTimeInterval(delay)
    }

    package mutating func clear(_ key: Key) {
        retryAfterByKey[key] = nil
    }
}
