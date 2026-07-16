@testable import AppBundle
import Common
import XCTest

final class LayoutMemoryCmdArgsTest: XCTestCase {
    func testParsesStatusAndRestore() {
        let status = parseCommand("layout-memory status --json").cmdOrDie
            .flatten().singleOrNil() as? LayoutMemoryCommand
        assertEquals(status?.args.action, .status(json: true))

        let restore = parseCommand("layout-memory restore --version 123E4567-E89B-12D3-A456-426614174000 --dry-run").cmdOrDie
            .flatten().singleOrNil() as? LayoutMemoryCommand
        assertEquals(
            restore?.args.action,
            .restore(
                input: nil,
                version: UUID(uuidString: "123E4567-E89B-12D3-A456-426614174000"),
                dryRun: true,
                json: false,
            ),
        )
    }

    func testRejectsConflictingRestoreTargets() {
        testParseCommandFail(
            "layout-memory restore --input snapshot.json --version 123E4567-E89B-12D3-A456-426614174000",
            msg: "--input conflicts with --version",
            exitCode: EXIT_CODE_TWO,
        )
    }

    func testRejectsMissingRequiredOption() {
        testParseCommandFail(
            "layout-memory export",
            msg: "export requires --output",
            exitCode: EXIT_CODE_TWO,
        )
    }

    func testRejectsOptionsThatDoNotBelongToAction() {
        testParseCommandFail(
            "layout-memory pause --json",
            msg: "Unsupported option for layout-memory action",
            exitCode: EXIT_CODE_TWO,
        )
        testParseCommandFail(
            "layout-memory status --force",
            msg: "Unsupported option for layout-memory action",
            exitCode: EXIT_CODE_TWO,
        )
    }
}
