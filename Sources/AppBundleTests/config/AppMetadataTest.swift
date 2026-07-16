import Common
import XCTest

final class AppMetadataTest: XCTestCase {
    private func makeTarget(
        appId: String,
        appName: String,
        environment: [String: String] = [:],
    ) -> AeroSpaceCliTarget {
        AeroSpaceCliTarget(
            appId: appId,
            appName: appName,
            socketPath: resolveSocketPath(appId: appId, environment: environment),
        )
    }

    func testResolveAeroSpaceCliTargetPrefersCustomWhenCustomAppIsRunning() {
        assertEquals(
            resolveAeroSpaceCliTarget(
                environment: [:],
                executableName: "aerospace",
                runningBundleIds: [customAeroSpaceAppId],
            ),
            makeTarget(appId: customAeroSpaceAppId, appName: customAeroSpaceAppName),
        )
    }

    func testResolveAeroSpaceCliTargetFallsBackToStableWhenCustomAppIsNotRunning() {
        assertEquals(
            resolveAeroSpaceCliTarget(
                environment: [:],
                executableName: "aerospace",
                runningBundleIds: [],
            ),
            makeTarget(appId: stableAeroSpaceAppId, appName: stableAeroSpaceAppName),
        )
    }

    func testResolveAeroSpaceCliTargetPrefersCustomWhenBothAppsAreRunning() {
        assertEquals(
            resolveAeroSpaceCliTarget(
                environment: [:],
                executableName: "aerospace",
                runningBundleIds: [stableAeroSpaceAppId, customAeroSpaceAppId],
            ),
            makeTarget(appId: customAeroSpaceAppId, appName: customAeroSpaceAppName),
        )
    }

    func testResolveAeroSpaceCliTargetUsesCustomExecutableAsFallback() {
        assertEquals(
            resolveAeroSpaceCliTarget(
                environment: [:],
                executableName: "aerospace-custom",
                runningBundleIds: [],
            ),
            makeTarget(appId: customAeroSpaceAppId, appName: customAeroSpaceAppName),
        )
    }

    func testResolveAeroSpaceCliTargetUsesExplicitEnvOverrides() {
        let resolvedTarget = resolveAeroSpaceCliTarget(
            environment: [
                AEROSPACE_APP_ID: "bobko.aerospace.custom",
                AEROSPACE_APP_NAME: "AeroSpace Custom",
                AEROSPACE_SOCKET_PATH: "/tmp/custom.sock",
            ],
            executableName: "aerospace",
            runningBundleIds: [stableAeroSpaceAppId, customAeroSpaceAppId],
        )
        assertEquals(
            resolvedTarget,
            makeTarget(appId: "bobko.aerospace.custom", appName: "AeroSpace Custom", environment: [
                AEROSPACE_APP_ID: "bobko.aerospace.custom",
                AEROSPACE_APP_NAME: "AeroSpace Custom",
                AEROSPACE_SOCKET_PATH: "/tmp/custom.sock",
            ]),
        )
        assertEquals(resolvedTarget.socketPath, "/tmp/custom.sock")
    }

    func testResolveSocketPathUsesExplicitOverride() {
        assertEquals(
            resolveSocketPath(
                appId: "bobko.aerospace.custom",
                environment: [AEROSPACE_SOCKET_PATH: "/tmp/custom.sock"],
            ),
            "/tmp/custom.sock",
        )
    }

    func testResolveSocketPathFallsBackToAppId() {
        assertEquals(
            resolveSocketPath(appId: "bobko.aerospace.custom", environment: [:]),
            "/tmp/bobko.aerospace.custom-\(unixUserName).sock",
        )
    }
}
