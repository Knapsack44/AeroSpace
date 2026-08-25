@testable import AppBundle
import Testing

struct NativeFocusZOrderTest {
    @Test func restoresOnlyWindowsFromOtherApps() {
        #expect(!shouldRestoreVisibleWorkspaceFrontWindow(targetAppPid: 41, frontWindowAppPid: 41))
        #expect(shouldRestoreVisibleWorkspaceFrontWindow(targetAppPid: 41, frontWindowAppPid: 42))
    }

    @Test func targetAppFrontWindowConsumesWorkspace() {
        let candidates = [
            (id: 1, workspace: 1, appPid: Int32(41)),
            (id: 2, workspace: 1, appPid: Int32(42)),
            (id: 3, workspace: 2, appPid: Int32(42)),
        ]

        let selected = selectVisibleWorkspaceFrontWindowsToRestore(
            from: candidates,
            targetAppPid: 41,
            workspaceId: { $0.workspace },
            appPid: { $0.appPid },
        )

        #expect(selected.map { $0.id } == [3])
    }
}
