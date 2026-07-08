import AppKit
import Foundation

public let stableAeroSpaceAppId: String = "bobko.aerospace"
public let stableAeroSpaceAppName: String = "AeroSpace"
public let customAeroSpaceAppId: String = "bobko.aerospace.custom"
public let customAeroSpaceAppName: String = "AeroSpace Custom"
public let debugAeroSpaceAppId: String = "bobko.aerospace.debug"
public let debugAeroSpaceAppName: String = "AeroSpace-Debug"

public func cliExecutableName() -> String {
    URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent
}

private func isCustomCliExecutable(_ executableName: String) -> Bool {
    executableName.hasPrefix("aerospace-custom")
}

public func currentAeroSpaceRunningBundleIds() -> Set<String> {
    Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        .intersection([stableAeroSpaceAppId, customAeroSpaceAppId])
}

public struct AeroSpaceCliTarget: Equatable {
    public let appId: String
    public let appName: String
    public let socketPath: String

    public init(appId: String, appName: String, socketPath: String) {
        self.appId = appId
        self.appName = appName
        self.socketPath = socketPath
    }
}

private func resolveDefaultAeroSpaceCliTarget(
    executableName: String,
    runningBundleIds: Set<String>,
) -> (appId: String, appName: String) {
    if isCustomCliExecutable(executableName) || runningBundleIds.contains(customAeroSpaceAppId) {
        return (customAeroSpaceAppId, customAeroSpaceAppName)
    }
    return (stableAeroSpaceAppId, stableAeroSpaceAppName)
}

private func resolveAeroSpaceCliTargetImpl(
    environment: [String: String],
    executableName: String,
    runningBundleIds: Set<String>,
) -> AeroSpaceCliTarget {
    let defaultTarget = resolveDefaultAeroSpaceCliTarget(
        executableName: executableName,
        runningBundleIds: runningBundleIds,
    )
    let appId = environment[AEROSPACE_APP_ID] ?? defaultTarget.appId
    return .init(
        appId: appId,
        appName: environment[AEROSPACE_APP_NAME] ?? defaultTarget.appName,
        socketPath: resolveSocketPath(appId: appId, environment: environment),
    )
}

public func resolveAeroSpaceCliTarget(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    executableName: String = cliExecutableName(),
    runningBundleIds: Set<String> = currentAeroSpaceRunningBundleIds(),
) -> AeroSpaceCliTarget {
    resolveAeroSpaceCliTargetImpl(
        environment: environment,
        executableName: executableName,
        runningBundleIds: runningBundleIds,
    )
}

public func resolveAeroSpaceAppId(
    isCli: Bool,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main,
) -> String {
    if isCli {
        return resolveAeroSpaceCliTarget(environment: environment).appId
    }
    return bundle.bundleIdentifier ?? {
        #if DEBUG
            debugAeroSpaceAppId
        #else
            stableAeroSpaceAppId
        #endif
    }()
}

public func resolveAeroSpaceAppId(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main,
) -> String {
    resolveAeroSpaceAppId(isCli: isCli, environment: environment, bundle: bundle)
}

public func resolveAeroSpaceAppName(
    isCli: Bool,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main,
) -> String {
    if isCli {
        return resolveAeroSpaceCliTarget(environment: environment).appName
    }
    return (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? {
        #if DEBUG
            debugAeroSpaceAppName
        #else
            stableAeroSpaceAppName
        #endif
    }()
}

public func resolveAeroSpaceAppName(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main,
) -> String {
    resolveAeroSpaceAppName(isCli: isCli, environment: environment, bundle: bundle)
}

public let aeroSpaceAppId: String = resolveAeroSpaceAppId()
public let aeroSpaceAppName: String = resolveAeroSpaceAppName()
public let releaseAeroSpaceAppId: String = aeroSpaceAppId.hasSuffix(".debug")
    ? String(aeroSpaceAppId.dropLast(".debug".count))
    : aeroSpaceAppId
