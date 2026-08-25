@testable import AppBundle
import Testing

struct NativeFocusZOrderTest {
    @Test func restoresOnlyWindowsFromOtherApps() {
        #expect(!shouldRestoreVisibleWorkspaceFrontWindow(targetAppPid: 41, frontWindowAppPid: 41))
        #expect(shouldRestoreVisibleWorkspaceFrontWindow(targetAppPid: 41, frontWindowAppPid: 42))
    }
}
