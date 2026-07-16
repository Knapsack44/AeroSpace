@testable import AppBundle
import Common
import XCTest

@MainActor
final class CustomLayoutMemoryConfigTest: XCTestCase {
    func testCustomLayoutMemoryIsDisabledByDefault() {
        let result = parseConfig("config-version = 2")

        assertEquals(result.errors, [])
        assertEquals(result.config.customLayoutMemory.enabled, false)
        assertEquals(result.config.customLayoutMemory.mode, .shadow)
    }

    func testParsesCompleteCustomLayoutMemoryBlock() {
        let result = parseConfig(
            """
            config-version = 2

            [custom-layout-memory]
            enabled = true
            mode = 'automatic'
            stability-delay-ms = 5000
            topology-sample-interval-ms = 2000
            snapshot-interval-seconds = 300
            post-transition-save-delay-seconds = 60
            layout-idle-seconds = 30
            history-limit = 5
            login-restore-window-seconds = 90
            failure-cooldown-seconds = 600
            native-fullscreen-deferral-seconds = 300
            play-sound-after-auto-restore = true
            success-sound = '/System/Library/Sounds/Glass.aiff'
            failure-sound = '/System/Library/Sounds/Basso.aiff'
            pause-sound = '/System/Library/Sounds/Pop.aiff'
            resume-sound = '/System/Library/Sounds/Ping.aiff'
            temporary-window-title-regex-substrings = ['^Create New Branch', '^Push Commits']
            excluded-workspaces = ['NULL-WORKSPACE', 'WSRESTORETMP']
            """,
        )

        assertEquals(result.errors, [])
        let parsed = result.config.customLayoutMemory
        assertEquals(parsed.enabled, true)
        assertEquals(parsed.mode, .automatic)
        assertEquals(parsed.stabilityDelayMs, 5000)
        assertEquals(parsed.temporaryWindowTitleRegexSubstrings, ["^Create New Branch", "^Push Commits"])
        assertEquals(parsed.excludedWorkspaces, ["NULL-WORKSPACE", "WSRESTORETMP"])
    }

    func testRejectsUnknownMode() {
        let result = parseConfig(
            """
            config-version = 2
            custom-layout-memory.mode = 'aggressive'
            """,
        )

        assertEquals(result.strErrors, [
            "[ERROR] custom-layout-memory.mode: Can't parse custom layout memory mode 'aggressive'",
        ])
    }

    func testRejectsNonPositiveTimingAndHistoryValues() {
        let result = parseConfig(
            """
            config-version = 2
            custom-layout-memory.stability-delay-ms = 0
            custom-layout-memory.history-limit = 0
            """,
        )

        assertEquals(result.strErrors, [
            "[ERROR] custom-layout-memory.history-limit: history-limit must be greater than zero",
            "[ERROR] custom-layout-memory.stability-delay-ms: stability-delay-ms must be greater than zero",
        ])
    }

    func testRejectsInvalidTemporaryWindowRegex() {
        let result = parseConfig(
            """
            config-version = 2
            custom-layout-memory.temporary-window-title-regex-substrings = ['[']
            """,
        )

        assertEquals(result.strErrors.count, 1)
        assertTrue(result.strErrors[0].starts(with: "[ERROR] custom-layout-memory.temporary-window-title-regex-substrings[0]: Invalid regular expression"))
    }

    func testRuntimeGateRequiresCustomWritableServer() {
        var enabled = CustomLayoutMemoryConfig()
        enabled.enabled = true

        assertEquals(isCustomLayoutMemoryRuntimeEnabled(appId: customAeroSpaceAppId, isReadOnly: false, config: enabled), true)
        assertEquals(isCustomLayoutMemoryRuntimeEnabled(appId: stableAeroSpaceAppId, isReadOnly: false, config: enabled), false)
        assertEquals(isCustomLayoutMemoryRuntimeEnabled(appId: customAeroSpaceAppId, isReadOnly: true, config: enabled), false)
        assertEquals(isCustomLayoutMemoryRuntimeEnabled(appId: customAeroSpaceAppId, isReadOnly: false, config: .init()), false)
    }
}
