import Foundation

private let customLayoutMemoryParser: [String: any ParserProtocol<CustomLayoutMemoryConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "mode": Parser(\.mode, parseCustomLayoutMemoryMode),
    "stability-delay-ms": Parser(\.stabilityDelayMs, parsePositiveInt("stability-delay-ms")),
    "topology-sample-interval-ms": Parser(\.topologySampleIntervalMs, parsePositiveInt("topology-sample-interval-ms")),
    "snapshot-interval-seconds": Parser(\.snapshotIntervalSeconds, parsePositiveInt("snapshot-interval-seconds")),
    "post-transition-save-delay-seconds": Parser(\.postTransitionSaveDelaySeconds, parsePositiveInt("post-transition-save-delay-seconds")),
    "layout-idle-seconds": Parser(\.layoutIdleSeconds, parsePositiveInt("layout-idle-seconds")),
    "history-limit": Parser(\.historyLimit, parsePositiveInt("history-limit")),
    "login-restore-window-seconds": Parser(\.loginRestoreWindowSeconds, parsePositiveInt("login-restore-window-seconds")),
    "failure-cooldown-seconds": Parser(\.failureCooldownSeconds, parsePositiveInt("failure-cooldown-seconds")),
    "native-fullscreen-deferral-seconds": Parser(\.nativeFullscreenDeferralSeconds, parsePositiveInt("native-fullscreen-deferral-seconds")),
    "play-sound-after-auto-restore": Parser(\.playSoundAfterAutoRestore, parseBool),
    "success-sound": Parser(\.successSound, parseAbsolutePath),
    "failure-sound": Parser(\.failureSound, parseAbsolutePath),
    "pause-sound": Parser(\.pauseSound, parseAbsolutePath),
    "resume-sound": Parser(\.resumeSound, parseAbsolutePath),
    "temporary-window-title-regex-substrings": Parser(\.temporaryWindowTitleRegexSubstrings, parseRegexStrings),
    "excluded-workspaces": Parser(\.excludedWorkspaces, parseNonEmptyStrings),
]

func parseCustomLayoutMemory(
    _ rawConfig: OrderedJson,
    _ backtrace: ConfigBacktrace,
    _ c: inout ConfigParserContext,
) -> CustomLayoutMemoryConfig {
    parseTable(rawConfig, CustomLayoutMemoryConfig(), customLayoutMemoryParser, backtrace, &c)
}

private func parseCustomLayoutMemoryMode(
    _ raw: OrderedJson,
    _ backtrace: ConfigBacktrace,
) -> ResOrConfigParseDiagnostic<CustomLayoutMemoryMode> {
    parseString(raw, backtrace).flatMap {
        CustomLayoutMemoryMode(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse custom layout memory mode '\($0)'"))
    }
}

private func parsePositiveInt(
    _ key: String,
) -> @Sendable (OrderedJson, ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    { raw, backtrace in
        parseInt(raw, backtrace)
            .filter(.init(backtrace, "\(key) must be greater than zero")) { $0 > 0 }
    }
}

private func parseAbsolutePath(
    _ raw: OrderedJson,
    _ backtrace: ConfigBacktrace,
) -> ResOrConfigParseDiagnostic<String> {
    parseString(raw, backtrace)
        .filter(.init(backtrace, "Sound path must be an absolute non-empty path")) {
            !$0.isEmpty && URL(filePath: $0).path.hasPrefix("/")
        }
}

private func parseStringArray(
    _ raw: OrderedJson,
    _ backtrace: ConfigBacktrace,
) -> ResOrConfigParseDiagnostic<[String]> {
    parseTomlArray(raw, backtrace).flatMap { array in
        array.enumerated().mapAllOrFailure { index, element in
            parseString(element, backtrace + .index(index))
        }
    }
}

private func parseNonEmptyStrings(
    _ raw: OrderedJson,
    _ backtrace: ConfigBacktrace,
) -> ResOrConfigParseDiagnostic<[String]> {
    parseStringArray(raw, backtrace).flatMap { values in
        for (index, value) in values.enumerated() where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.init(backtrace + .index(index), "Value must not be empty"))
        }
        return .success(values)
    }
}

private func parseRegexStrings(
    _ raw: OrderedJson,
    _ backtrace: ConfigBacktrace,
) -> ResOrConfigParseDiagnostic<[String]> {
    parseStringArray(raw, backtrace).flatMap { values in
        for (index, value) in values.enumerated() {
            do {
                _ = try Regex<AnyRegexOutput>(value)
            } catch {
                return .failure(.init(
                    backtrace + .index(index),
                    "Invalid regular expression '\(value)': \(error.localizedDescription)",
                ))
            }
        }
        return .success(values)
    }
}
