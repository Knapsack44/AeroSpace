@testable import AppBundle
import Testing

struct NativeFocusRetryTest {
    @Test mutating func retriesOnlyTheLatestStillFocusedWindow() {
        var retry = NativeFocusRetry()

        retry.request(windowId: 8881)
        retry.request(windowId: 6165)

        #expect(retry.acceptsNativeFocus(windowId: 6165))
        #expect(!retry.acceptsNativeFocus(windowId: 8881))
        #expect(retry.consume(requestedWindowId: 8881, focusedWindowId: 8881) == nil)
        #expect(retry.pendingWindowId == 6165)
        #expect(retry.consume(requestedWindowId: 6165, focusedWindowId: 8881) == nil)
        #expect(retry.pendingWindowId == nil)

        retry.request(windowId: 6165)
        #expect(retry.consume(requestedWindowId: 6165, focusedWindowId: 6165) == 6165)
        #expect(retry.pendingWindowId == nil)
    }
}
