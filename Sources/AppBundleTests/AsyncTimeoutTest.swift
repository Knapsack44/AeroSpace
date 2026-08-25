@testable import AppBundle
import Dispatch
import Foundation
import XCTest

final class AsyncTimeoutTest: XCTestCase {
    func testReturnsResultBeforeTimeout() async throws {
        let result = try await firstResult(before: .seconds(1)) { continuation in
            continuation.yield("ready")
            continuation.finish()
            return {}
        }

        assertEquals(result, "ready")
    }

    func testReturnsWithoutWaitingForBlockedOperation() async throws {
        let semaphore = DispatchSemaphore(value: 0)
        defer { semaphore.signal() }
        let clock = ContinuousClock()
        let startedAt = clock.now

        let result: String? = try await firstResult(before: .milliseconds(25)) { continuation in
            let operation = Thread {
                semaphore.wait()
                continuation.yield("late")
                continuation.finish()
            }
            operation.start()
            return { semaphore.signal() }
        }

        assertNil(result)
        assertTrue(startedAt.duration(to: clock.now) < .milliseconds(250))
    }

    func testPropagatesOperationError() async {
        struct ExpectedError: Error {}

        do {
            let _: String? = try await firstResult(before: .seconds(1)) { continuation in
                continuation.finish(throwing: ExpectedError())
                return {}
            }
            failExpectedActual("ExpectedError", "no error thrown")
        } catch is ExpectedError {
            // expected
        } catch {
            failExpectedActual("ExpectedError", error)
        }
    }
}
