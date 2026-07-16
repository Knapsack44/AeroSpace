import Foundation

public let stableAeroSpaceAppId: String = "bobko.aerospace"
public let stableAeroSpaceAppName: String = "AeroSpace"
public let customAeroSpaceAppId: String = "bobko.aerospace.custom"
public let customAeroSpaceAppName: String = "AeroSpace Custom"
public let debugAeroSpaceAppId: String = "bobko.aerospace.debug"
public let debugAeroSpaceAppName: String = "AeroSpace-Debug"

public func resolveAeroSpaceAppId(
    isCli: Bool,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main,
) -> String {
    if let override = environment[AEROSPACE_APP_ID] {
        return override
    }
    if isCli {
        return stableAeroSpaceAppId
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
    if let override = environment[AEROSPACE_APP_NAME] {
        return override
    }
    if isCli {
        return stableAeroSpaceAppName
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
