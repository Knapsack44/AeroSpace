public struct FocusCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .focus,
        help: focus_help_generated,
        flags: [
            "--ignore-floating": falseBoolFlag(\.floatingAsTiling),
            "--window-id": windowIdSubArgParser(),
            "--dfs-index": singleValueSubArgParser(\.dfsIndex, "<dfs-index>", parseUInt32),

            "--boundaries": ArgParser(\.rawBoundaries, upcastArgParserFun(parseBoundaries)),
            "--boundaries-action": ArgParser(\.rawBoundariesAction, upcastArgParserFun(parseBoundariesAction)),
            "--fail-if-fullscreen": trueBoolFlag(\.failIfFullscreen),
            "--fail-if-macos-native-fullscreen": trueBoolFlag(\.failIfMacosNativeFullscreen),
            "--wrap-around": trueBoolFlag(\.wrapAroundAlias),
        ],
        posArgs: [ArgParser(\.target, upcastArgParserFun(parseFocusTarget))],
        conflictingOptions: [
            ["--wrap-around", "--boundaries-action"],
            ["--wrap-around", "--boundaries"],
        ],
    )

    public var rawBoundaries: Boundaries? = nil // todo cover boundaries wrapping with tests
    public var rawBoundariesAction: WhenBoundariesCrossed? = nil
    public var failIfFullscreen: Bool = false
    public var failIfMacosNativeFullscreen: Bool = false
    fileprivate var wrapAroundAlias: Bool = false
    public var dfsIndex: UInt32? = nil
    public var target: FocusCmdTarget? = nil
    public var floatingAsTiling: Bool = true

    public init(rawArgs: StrArrSlice, target: FocusCmdTarget) {
        self.commonState = .init(rawArgs)
        self.target = target
    }

    public init(rawArgs: StrArrSlice, windowId: UInt32) {
        self.commonState = .init(rawArgs)
        self.windowId = windowId
    }

    public init(rawArgs: StrArrSlice, dfsIndex: UInt32) {
        self.commonState = .init(rawArgs)
        self.dfsIndex = dfsIndex
    }

    public enum Boundaries: String, CaseIterable, Equatable, Sendable {
        case workspace
        case allMonitorsOuterFrame = "all-monitors-outer-frame"
    }
    public enum WhenBoundariesCrossed: String, CaseIterable, Equatable, Sendable {
        case stop = "stop"
        case fail = "fail"
        case wrapAroundTheWorkspace = "wrap-around-the-workspace"
        case wrapAroundAllMonitors = "wrap-around-all-monitors"
    }
}

public enum FocusCmdTarget: Equatable, Sendable {
    case direction(CardinalDirection)
    case windowId(UInt32)
    case dfsIndex(UInt32)
    case dfsRelative(DfsNextPrev)
    case containerRelative(ContainerFocusNextPrev)
    case containerMruRelative(ContainerMruFocusNextPrev)

    var isDfsRelative: Bool {
        switch self {
            case .dfsRelative: true
            default: false
        }
    }

    var isContainerLocalRelative: Bool {
        switch self {
            case .containerRelative, .containerMruRelative: true
            default: false
        }
    }

    static var cliArgsCases: [String] {
        CardinalDirection.cliArgsCases
            + DfsNextPrev.cliArgsCases
            + ContainerFocusNextPrev.cliArgsCases
            + ContainerMruFocusNextPrev.cliArgsCases
    }

    static var unionLiteral: String { cliArgsCases.joinedCliArgs }
}

public enum ContainerFocusNextPrev: String, CaseIterable, Equatable, Sendable {
    case containerNext = "container-next"
    case containerPrev = "container-prev"
}

public enum ContainerMruFocusNextPrev: String, CaseIterable, Equatable, Sendable {
    case containerMruNext = "container-mru-next"
    case containerMruPrev = "container-mru-prev"
}

extension FocusCmdArgs {
    public var resolvedTarget: FocusCmdTarget {
        if let target { return target }
        if let windowId {
            return .windowId(windowId)
        }
        if let dfsIndex {
            return .dfsIndex(dfsIndex)
        }
        die("Parser invariants are broken")
    }

    public var boundaries: Boundaries { rawBoundaries ?? .workspace }
    public var boundariesAction: WhenBoundariesCrossed {
        wrapAroundAlias ? .wrapAroundTheWorkspace : (rawBoundariesAction ?? .stop)
    }
}

func parseFocusCmdArgs(_ args: StrArrSlice) -> ParsedCmd<FocusCmdArgs> {
    return parseSpecificCmdArgs(FocusCmdArgs(rawArgs: args), args)
        .flatMap { (raw: FocusCmdArgs) -> ParsedCmd<FocusCmdArgs> in
            raw.boundaries == .workspace && raw.boundariesAction == .wrapAroundAllMonitors
                ? .failure("\(raw.boundaries.rawValue) and \(raw.boundariesAction.rawValue) is an invalid combination of values")
                : .cmd(raw)
        }
        .filter("Mandatory argument is missing. \(FocusCmdTarget.unionLiteral), --window-id or --dfs-index is required") {
            $0.target != nil || $0.windowId != nil || $0.dfsIndex != nil
        }
        .filter("--window-id is incompatible with other options") {
            $0.windowId == nil || $0 == FocusCmdArgs(rawArgs: args, windowId: $0.windowId.orDie())
        }
        .filter("--dfs-index is incompatible with other options") {
            $0.dfsIndex == nil || $0 == FocusCmdArgs(rawArgs: args, dfsIndex: $0.dfsIndex.orDie())
        }
        .filter("--fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument") {
            if !$0.failIfFullscreen && !$0.failIfMacosNativeFullscreen {
                return true
            }
            return switch $0.target {
                case .direction: true
                case .dfsIndex, .dfsRelative, .windowId, .containerRelative, .containerMruRelative, nil: false
            }
        }
        .filter("(container-next|container-prev|container-mru-next|container-mru-prev) only supports --ignore-floating") {
            !($0.target?.isContainerLocalRelative == true)
                || ($0.rawBoundaries == nil
                    && $0.rawBoundariesAction == nil
                    && !$0.wrapAroundAlias
                    && !$0.failIfFullscreen
                    && !$0.failIfMacosNativeFullscreen)
        }
        .filter("(dfs-next|dfs-prev) only supports --boundaries workspace") {
            ($0.target?.isDfsRelative == true).implies($0.boundaries == .workspace)
        }
}

private func parseFocusTarget(i: PosArgParserInput) -> ParsedCliArgs<FocusCmdTarget> {
    switch i.arg {
        case ContainerFocusNextPrev.containerNext.rawValue:
            return .succ(.containerRelative(.containerNext), advanceBy: 1)
        case ContainerFocusNextPrev.containerPrev.rawValue:
            return .succ(.containerRelative(.containerPrev), advanceBy: 1)
        case ContainerMruFocusNextPrev.containerMruNext.rawValue:
            return .succ(.containerMruRelative(.containerMruNext), advanceBy: 1)
        case ContainerMruFocusNextPrev.containerMruPrev.rawValue:
            return .succ(.containerMruRelative(.containerMruPrev), advanceBy: 1)
        default:
            if let direction = CardinalDirection(rawValue: i.arg) {
                return .succ(.direction(direction), advanceBy: 1)
            } else if let nextPrev = DfsNextPrev(rawValue: i.arg) {
                return .succ(.dfsRelative(nextPrev), advanceBy: 1)
            } else {
                return .fail("Can't parse '\(i.arg)'.\nPossible values: \(FocusCmdTarget.unionLiteral)", advanceBy: 1)
            }
    }
}

private func parseBoundariesAction(i: SubArgParserInput) -> ParsedCliArgs<FocusCmdArgs.WhenBoundariesCrossed> {
    if let arg = i.nonFlagArgOrNil() {
        return .init(parseEnum(arg, FocusCmdArgs.WhenBoundariesCrossed.self), advanceBy: 1)
    } else {
        return .fail("<action> is mandatory", advanceBy: 0)
    }
}

private func parseBoundaries(i: SubArgParserInput) -> ParsedCliArgs<FocusCmdArgs.Boundaries> {
    if let arg = i.nonFlagArgOrNil() {
        return .init(parseEnum(arg, FocusCmdArgs.Boundaries.self), advanceBy: 1)
    } else {
        return .fail("<boundary> is mandatory", advanceBy: 0)
    }
}
