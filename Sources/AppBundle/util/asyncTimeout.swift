import Common
import Foundation

func firstResult<T: Sendable>(
    before timeout: Duration,
    start: (AsyncThrowingStream<T, any Error>.Continuation) -> @Sendable () -> Void,
) async throws -> T? {
    let (stream, continuation) = AsyncThrowingStream<T, any Error>.makeStream()
    let cancelOperation = start(continuation)
    let timeoutTask = Task.startUnstructured {
        do {
            try await Task.sleep(for: timeout)
            continuation.finish()
        } catch {
            // The operation completed first.
        }
    }
    defer {
        cancelOperation()
        timeoutTask.cancel()
        continuation.finish()
    }
    return try await stream.first { _ in true }
}
