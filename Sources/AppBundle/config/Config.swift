import AppKit
import Common
import HotKey
import OrderedCollections

func getDefaultConfigUrlFromProject() -> URL {
    var url = URL(filePath: #filePath)
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    let projectRoot: URL = url
    return projectRoot.appending(component: "docs/config-examples/default-config.toml")
}

var defaultConfigUrl: URL {
    if isUnitTest {
        return getDefaultConfigUrlFromProject()
    } else {
        return Bundle.main.url(forResource: "default-config", withExtension: "toml")
            // Useful for debug builds that are not app bundles
            ?? getDefaultConfigUrlFromProject()
    }
}
@MainActor let defaultConfig: Config = {
    let parsedConfig = parseConfig(Result { try String(contentsOf: defaultConfigUrl, encoding: .utf8) }.getOrDie())
    if !parsedConfig.errors.isEmpty {
        die("Can't parse default config: \(parsedConfig.errors)")
    }
    return parsedConfig.config
}()
@MainActor var config: Config = defaultConfig // todo move to Ctx?
@MainActor var configUrl: URL = defaultConfigUrl

struct Config: ConvenienceMutable {
    var configVersion: ConfigVersion = ._1
    var _afterLoginCommand: [any Command] = []
    var afterStartupCommand: Shell<any Command> = .empty
    var _indentForNestedContainersWithTheSameOrientation: Void = ()
    var enableNormalizationFlattenContainers: Bool = true
    var _nonEmptyWorkspacesRootContainersLayoutOnStartup: Void = ()
    var defaultRootContainerLayout: Layout = .tiles
    var defaultRootContainerOrientation: DefaultContainerOrientation = .auto
    var startAtLogin: Bool = false
    var autoReloadConfig: Bool = false
    var automaticallyUnhideMacosHiddenApps: Bool = false
    var accordionPadding: Int = 30
    var enableNormalizationOppositeOrientationForNestedContainers: Bool = true
    var persistentWorkspaces: OrderedSet<String> = []
    var execOnWorkspaceChange: [String] = [] // todo deprecate
    var keyMapping = KeyMapping()
    var execConfig: ExecConfig = ExecConfig()
    var focusFollowsMouse: FocusFollowsMouse = FocusFollowsMouse()
    var customLayoutMemory = CustomLayoutMemoryConfig()

    var onFocusChanged: Shell<any Command> = .empty
    // var onFocusedWorkspaceChanged: [any Command] = []
    var onFocusedMonitorChanged: Shell<any Command> = .empty

    var gaps: Gaps = .zero
    var workspaceToMonitorForceAssignment: [String: [MonitorDescription]] = [:]
    var modes: [String: Mode] = [:]
    var onWindowDetected: [WindowDetectedCallback] = []
    var onModeChanged: Shell<any Command> = .empty
}

struct FocusFollowsMouse: ConvenienceMutable {
    var enabled: Bool = false
    var delayMs: Int = 0
}

enum CustomLayoutMemoryMode: String, Equatable, Sendable {
    case shadow
    case manual
    case automatic
}

struct CustomLayoutMemoryConfig: ConvenienceMutable, Equatable, Sendable {
    var enabled = false
    var mode: CustomLayoutMemoryMode = .shadow
    var stabilityDelayMs = 5000
    var topologySampleIntervalMs = 2000
    var snapshotIntervalSeconds = 300
    var postTransitionSaveDelaySeconds = 60
    var layoutIdleSeconds = 30
    var historyLimit = 5
    var loginRestoreWindowSeconds = 90
    var failureCooldownSeconds = 600
    var nativeFullscreenDeferralSeconds = 300
    var playSoundAfterAutoRestore = true
    var successSound = "/System/Library/Sounds/Glass.aiff"
    var failureSound = "/System/Library/Sounds/Basso.aiff"
    var pauseSound = "/System/Library/Sounds/Pop.aiff"
    var resumeSound = "/System/Library/Sounds/Ping.aiff"
    var temporaryWindowTitleRegexSubstrings: [String] = []
    var excludedWorkspaces = ["NULL-WORKSPACE", "WS2TMP", "WS3TMP", "WSRESTORETMP"]
}

func isCustomLayoutMemoryRuntimeEnabled(
    appId: String,
    isReadOnly: Bool,
    config: CustomLayoutMemoryConfig,
) -> Bool {
    appId == customAeroSpaceAppId && !isReadOnly && config.enabled
}

enum ConfigVersion: Int, Comparable, CaseIterable, Sendable, CustomStringConvertible {
    case _1 = 1
    case _2 = 2

    static let max = allCases.max().orDie()
    static let min = allCases.min().orDie()
    static func < (lhs: ConfigVersion, rhs: ConfigVersion) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { rawValue.description }
}

enum DefaultContainerOrientation: String {
    case horizontal, vertical, auto
}
