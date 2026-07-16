private let focusFollowsMouseParserTable: [String: any ParserProtocol<FocusFollowsMouse>] = [
    "enabled": Parser(\.enabled, parseBool),
    "delay-ms": Parser(\.delayMs, parseFocusFollowsMouseDelayMs),
]

func parseFocusFollowsMouse(_ rawConfig: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> FocusFollowsMouse {
    parseTable(rawConfig, FocusFollowsMouse(), focusFollowsMouseParserTable, backtrace, &c)
}

private func parseFocusFollowsMouseDelayMs(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    parseInt(raw, backtrace)
        .filter(.init(backtrace, "delay-ms must be greater than or equal to zero")) { $0 >= 0 }
}
