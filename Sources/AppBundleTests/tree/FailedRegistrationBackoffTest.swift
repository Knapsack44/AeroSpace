import AppBundle
import XCTest

final class FailedRegistrationBackoffTest: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)

    func testFailureSuppressesRetriesUntilDelayExpires() {
        var backoff = FailedRegistrationBackoff<Int>(delay: 5)

        backoff.recordFailure(42, now: start)

        XCTAssertFalse(backoff.shouldAttempt(42, now: start.addingTimeInterval(4.999)))
        XCTAssertTrue(backoff.shouldAttempt(42, now: start.addingTimeInterval(5)))
        XCTAssertTrue(backoff.shouldAttempt(42, now: start.addingTimeInterval(5)))
    }

    func testBackoffIsScopedByKey() {
        var backoff = FailedRegistrationBackoff<Int>(delay: 5)

        backoff.recordFailure(42, now: start)

        XCTAssertFalse(backoff.shouldAttempt(42, now: start))
        XCTAssertTrue(backoff.shouldAttempt(43, now: start))
    }

    func testClearAllowsImmediateRetry() {
        var backoff = FailedRegistrationBackoff<Int>(delay: 5)
        backoff.recordFailure(42, now: start)

        backoff.clear(42)

        XCTAssertTrue(backoff.shouldAttempt(42, now: start))
    }
}
