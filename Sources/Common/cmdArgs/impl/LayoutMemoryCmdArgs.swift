import Foundation

private let layoutMemoryHelp = """
    USAGE: layout-memory <action> [options]

    Experimental AeroSpace Custom layout snapshot and restore commands.
    """

public enum LayoutMemoryAction: Equatable, Sendable {
    case export(output: String)
    case restore(input: String?, version: UUID?, dryRun: Bool, json: Bool)
    case status(json: Bool)
    case list(json: Bool)
    case snapshot(label: String?)
    case pause
    case resume
    case togglePause
    case pin(version: UUID, label: String?)
    case prefer(version: UUID)
    case unprefer
    case deleteVersion(version: UUID, force: Bool)
    case deleteProfile(signature: String, force: Bool)
    case manualChangeBegin
    case manualChangeEnd(token: UUID)
}

public struct LayoutMemoryCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public static let parser: CmdParser<Self> = .init(
        kind: .layoutMemory,
        help: layoutMemoryHelp,
        flags: [
            "--json": trueBoolFlag(\.json),
            "--dry-run": trueBoolFlag(\.dryRun),
            "--force": trueBoolFlag(\.force),
            "--output": singleValueSubArgParser(\.output, "<file>", Result.success),
            "--input": singleValueSubArgParser(\.input, "<file>", Result.success),
            "--version": singleValueSubArgParser(\.version, "<id>", Result.success),
            "--label": singleValueSubArgParser(\.label, "<text>", Result.success),
            "--signature": singleValueSubArgParser(\.signature, "<id>", Result.success),
            "--token": singleValueSubArgParser(\.token, "<token>", Result.success),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.rawAction, consumeStrCliArg, placeholder: "<action>"),
        ],
    )

    public var rawAction: Lateinit<String> = .uninitialized
    public var json = false
    public var dryRun = false
    public var force = false
    public var output: String?
    public var input: String?
    public var version: String?
    public var label: String?
    public var signature: String?
    public var token: String?

    public init(rawArgs: StrArrSlice) {
        commonState = .init(rawArgs)
    }

    public var action: LayoutMemoryAction {
        switch rawAction.val {
            case "export": .export(output: output.orDie())
            case "restore": .restore(input: input, version: version.flatMap(UUID.init(uuidString:)), dryRun: dryRun, json: json)
            case "status": .status(json: json)
            case "list": .list(json: json)
            case "snapshot": .snapshot(label: label)
            case "pause": .pause
            case "resume": .resume
            case "toggle-pause": .togglePause
            case "pin": .pin(version: UUID(uuidString: version.orDie()).orDie(), label: label)
            case "prefer": .prefer(version: UUID(uuidString: version.orDie()).orDie())
            case "unprefer": .unprefer
            case "delete-version": .deleteVersion(version: UUID(uuidString: version.orDie()).orDie(), force: force)
            case "delete-profile": .deleteProfile(signature: signature.orDie(), force: force)
            case "manual-change-begin": .manualChangeBegin
            case "manual-change-end": .manualChangeEnd(token: UUID(uuidString: token.orDie()).orDie())
            default: die("Validated by parseLayoutMemoryCmdArgs")
        }
    }
}

public func parseLayoutMemoryCmdArgs(_ args: StrArrSlice) -> ParsedCmd<LayoutMemoryCmdArgs> {
    parseSpecificCmdArgs(LayoutMemoryCmdArgs(rawArgs: args), args)
        .filter("--input conflicts with --version") { !($0.input != nil && $0.version != nil) }
        .filter("Unknown layout-memory action") { validActions.contains($0.rawAction.val) }
        .filter("export requires --output") { $0.rawAction.val != "export" || $0.output != nil }
        .filter("pin requires --version") { $0.rawAction.val != "pin" || validUuid($0.version) }
        .filter("prefer requires --version") { $0.rawAction.val != "prefer" || validUuid($0.version) }
        .filter("delete-version requires --version") { $0.rawAction.val != "delete-version" || validUuid($0.version) }
        .filter("delete-profile requires --signature") { $0.rawAction.val != "delete-profile" || $0.signature != nil }
        .filter("manual-change-end requires --token") { $0.rawAction.val != "manual-change-end" || validUuid($0.token) }
        .filter("Invalid --version UUID") {
            $0.version == nil || validUuid($0.version)
        }
        .filter("Unsupported option for layout-memory action") { optionsAreValid($0) }
}

private let validActions: Set<String> = [
    "export", "restore", "status", "list", "snapshot", "pause", "resume", "toggle-pause",
    "pin", "prefer", "unprefer", "delete-version", "delete-profile",
    "manual-change-begin", "manual-change-end",
]

private func validUuid(_ value: String?) -> Bool {
    value.flatMap(UUID.init(uuidString:)) != nil
}

private func optionsAreValid(_ args: LayoutMemoryCmdArgs) -> Bool {
    let used = Set([
        args.json ? "json" : nil,
        args.dryRun ? "dry-run" : nil,
        args.force ? "force" : nil,
        args.output.map { _ in "output" },
        args.input.map { _ in "input" },
        args.version.map { _ in "version" },
        args.label.map { _ in "label" },
        args.signature.map { _ in "signature" },
        args.token.map { _ in "token" },
    ].compactMap { $0 })
    let allowed: Set<String> = switch args.rawAction.val {
        case "export": ["output"]
        case "restore": ["input", "version", "dry-run", "json"]
        case "status", "list": ["json"]
        case "snapshot": ["label"]
        case "pin": ["version", "label"]
        case "prefer": ["version"]
        case "delete-version": ["version", "force"]
        case "delete-profile": ["signature", "force"]
        case "manual-change-end": ["token"]
        default: []
    }
    return used.isSubset(of: allowed)
}
