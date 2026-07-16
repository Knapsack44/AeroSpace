import Common
import XCTest

final class AppMetadataTest: XCTestCase {
    func testCustomProductIdentityIsIndependentFromStableProduct() {
        assertEquals(stableAeroSpaceAppId, "bobko.aerospace")
        assertEquals(stableAeroSpaceAppName, "AeroSpace")
        assertEquals(customAeroSpaceAppId, "bobko.aerospace.custom")
        assertEquals(customAeroSpaceAppName, "AeroSpace Custom")
    }

    func testCliMetadataUsesExplicitOverrides() {
        let environment = [
            AEROSPACE_APP_ID: customAeroSpaceAppId,
            AEROSPACE_APP_NAME: customAeroSpaceAppName,
        ]
        assertEquals(resolveAeroSpaceAppId(isCli: true, environment: environment), customAeroSpaceAppId)
        assertEquals(resolveAeroSpaceAppName(isCli: true, environment: environment), customAeroSpaceAppName)
    }

    func testResolveSocketPathUsesExplicitOverride() {
        assertEquals(
            resolveSocketPath(
                appId: customAeroSpaceAppId,
                environment: [AEROSPACE_SOCKET_PATH: "/tmp/custom.sock"],
            ),
            "/tmp/custom.sock",
        )
    }

    func testResolveSocketPathFallsBackToAppId() {
        assertEquals(
            resolveSocketPath(appId: customAeroSpaceAppId, environment: [:]),
            "/tmp/\(customAeroSpaceAppId)-\(unixUserName).sock",
        )
    }
}
