import Foundation
import XCTest

final class CustomPatchManifestTest: XCTestCase {
    private let validIndex = """
        {
          "cases": [
            {
              "id": "ASR-0001",
              "relations": {"patch-ids": ["container-focus"]}
            }
          ],
          "schema-version": 1
        }
        """

    func testRejectsUnknownRegressionId() throws {
        let result = try verify(
            manifest: manifest(regressions: ["ASR-9999"]),
            index: validIndex,
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("unknown regression ID ASR-9999"))
    }

    func testRejectsPatchWithoutRegressionOrFeatureRationale() throws {
        let result = try verify(manifest: manifest(), index: validIndex)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("requires regressions or a feature-class"))
    }

    func testRejectsDuplicatePatchIds() throws {
        let duplicatePatch = """
            schema-version = 1
            upstream-base = 'fixture-base'

            [[patch]]
            id = 'custom-app-bundle'
            commit-subject = 'First patch'
            feature-class = 'product-identity'
            feature-rationale = 'Provides a separately named app bundle and Accessibility identity.'

            [[patch]]
            id = 'custom-app-bundle'
            commit-subject = 'Second patch'
            feature-class = 'product-identity'
            feature-rationale = 'Provides a separately named app bundle and Accessibility identity.'
            """
        let result = try verify(manifest: duplicatePatch, index: emptyIndex)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("duplicate patch ID custom-app-bundle"))
    }

    func testRejectsFillerFeatureClassAndRationale() throws {
        let featureManifest = manifest(
            featureClass: "aaaaaaaaaaaaaaaaaaaa",
            featureRationale: "aaaaaaaaaaaaaaaaaaaa",
        )
        let result = try verify(manifest: featureManifest, index: emptyIndex)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("unknown feature-class"))
    }

    func testRejectsKnownFeatureClassOnUnregisteredPatch() throws {
        let result = try verify(
            manifest: manifest(
                featureClass: "product-identity",
                featureRationale: "aaaaaaaaaaaaaaaaaaaa",
            ),
            index: emptyIndex,
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("is not registered as a feature-only patch"))
    }

    func testAcceptsCurrentCustomAppBundleFeatureContract() throws {
        let result = try verify(
            manifest: manifest(
                patchId: "custom-app-bundle",
                featureClass: "product-identity",
                featureRationale: "Provides a separately named app bundle and Accessibility identity.",
            ),
            index: emptyIndex,
        )

        XCTAssertEqual(result.status, 0, result.stderr)
    }

    func testAcceptsCurrentCustomCliRoutingFeatureContract() throws {
        let result = try verify(
            manifest: manifest(
                patchId: "custom-cli-routing",
                featureClass: "runtime-target-selection",
                featureRationale: "Routes commands to the running Custom app without changing vanilla defaults.",
            ),
            index: emptyIndex,
        )

        XCTAssertEqual(result.status, 0, result.stderr)
    }

    func testRejectsFillerRationaleForKnownFeaturePatch() throws {
        let result = try verify(
            manifest: manifest(
                patchId: "custom-app-bundle",
                featureClass: "product-identity",
                featureRationale: "placeholder placeholder placeholder placeholder placeholder placeholder placeholder",
            ),
            index: emptyIndex,
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("must contain at least 7 words and 6 distinct words"))
    }

    func testRejectsUnrelatedRationaleForKnownFeaturePatch() throws {
        let result = try verify(
            manifest: manifest(
                patchId: "custom-cli-routing",
                featureClass: "runtime-target-selection",
                featureRationale: "Documents colorful gardening recipes for weekend visitors and seasonal flowers.",
            ),
            index: emptyIndex,
        )

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("must describe runtime-target-selection"))
    }

    func testPatchStackAllowsUnmappedDocumentationOnlyCommit() throws {
        let fixture = try makePatchStackFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try commitFile(
            in: fixture,
            path: "docs/note.md",
            contents: "Documentation only.\n",
            subject: "Document fixture behavior",
        )

        let result = try verifyPatchStack(in: fixture)

        XCTAssertEqual(result.status, 0, result.stderr)
    }

    func testPatchStackRejectsUnmappedProductiveCommit() throws {
        let fixture = try makePatchStackFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try commitFile(
            in: fixture,
            path: "Sources/Unmapped.swift",
            contents: "let unmappedBehavior = true\n",
            subject: "Add unmapped product behavior",
        )

        let result = try verifyPatchStack(in: fixture)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("Unmapped productive commit"))
        XCTAssertTrue(result.stderr.contains("Add unmapped product behavior"))
    }

    func testPatchStackRejectsUnmappedFileUnderCustomDirectory() throws {
        let fixture = try makePatchStackFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try commitFile(
            in: fixture,
            path: "custom/runtime-policy.json",
            contents: "{\"enabled\":true}\n",
            subject: "Add unmapped Custom runtime policy",
        )

        let result = try verifyPatchStack(in: fixture)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("Unmapped productive commit"))
        XCTAssertTrue(result.stderr.contains("Add unmapped Custom runtime policy"))
    }

    private var emptyIndex: String {
        """
        {"cases": [], "schema-version": 1}
        """
    }

    private func manifest(
        patchId: String = "container-focus",
        regressions: [String]? = nil,
        featureClass: String? = nil,
        featureRationale: String? = nil,
    ) -> String {
        var lines = [
            "schema-version = 1",
            "upstream-base = 'fixture-base'",
            "",
            "[[patch]]",
            "id = '\(patchId)'",
            "commit-subject = 'Container focus patch'",
        ]
        if let regressions {
            let values = regressions.map { "'\($0)'" }.joined(separator: ", ")
            lines.append("regressions = [\(values)]")
        }
        if let featureClass {
            lines.append("feature-class = '\(featureClass)'")
        }
        if let featureRationale {
            lines.append("feature-rationale = '\(featureRationale)'")
        }
        return lines.joined(separator: "\n")
    }

    private func verify(manifest: String, index: String) throws -> CommandResult {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let manifestUrl = fixture.appendingPathComponent("patches.toml")
        let indexUrl = fixture.appendingPathComponent("index.json")
        try manifest.write(to: manifestUrl, atomically: true, encoding: .utf8)
        try index.write(to: indexUrl, atomically: true, encoding: .utf8)

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            repositoryRoot.appendingPathComponent("script/verify-regression-references.sh").path,
            manifestUrl.path,
            indexUrl.path,
        ]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        )
    }

    private func makePatchStackFixture() throws -> URL {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixture.appendingPathComponent("script"),
            withIntermediateDirectories: true,
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("script/verify-custom-patch-stack.sh"),
            to: fixture.appendingPathComponent("script/verify-custom-patch-stack.sh"),
        )
        let referenceVerifier = repositoryRoot.appendingPathComponent("script/verify-regression-references.sh")
        if FileManager.default.fileExists(atPath: referenceVerifier.path) {
            try FileManager.default.copyItem(
                at: referenceVerifier,
                to: fixture.appendingPathComponent("script/verify-regression-references.sh"),
            )
        }
        try runGit(["init", "-q", "-b", "custom/main"], in: fixture)
        try runGit(["config", "user.name", "Test"], in: fixture)
        try runGit(["config", "user.email", "test@example.invalid"], in: fixture)
        try commitFile(
            in: fixture,
            path: "README.md",
            contents: "Upstream fixture.\n",
            subject: "Upstream base",
        )
        try runGit(["tag", "fixture-base"], in: fixture)
        try FileManager.default.createDirectory(
            at: fixture.appendingPathComponent("custom"),
            withIntermediateDirectories: true,
        )
        try manifest(regressions: ["ASR-0001"]).write(
            to: fixture.appendingPathComponent("custom/patches.toml"),
            atomically: true,
            encoding: .utf8,
        )
        try validIndex.write(
            to: fixture.appendingPathComponent("index.json"),
            atomically: true,
            encoding: .utf8,
        )
        try commitFile(
            in: fixture,
            path: "Sources/Product.swift",
            contents: "let productBehavior = true\n",
            subject: "Container focus patch",
        )
        return fixture
    }

    private func commitFile(
        in repository: URL,
        path: String,
        contents: String,
        subject: String,
    ) throws {
        let file = repository.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try contents.write(to: file, atomically: true, encoding: .utf8)
        try runGit(["add", "--", path], in: repository)
        try runGit(["commit", "-qm", subject], in: repository)
    }

    private func verifyPatchStack(in repository: URL) throws -> CommandResult {
        try run(
            executable: "/bin/bash",
            arguments: ["script/verify-custom-patch-stack.sh", "--skip-tests"],
            currentDirectory: repository,
            environment: [
                "AEROSPACE_CUSTOM_REGRESSION_INDEX": repository.appendingPathComponent("index.json").path,
            ],
        )
    }

    private func runGit(_ arguments: [String], in repository: URL) throws {
        let result = try run(
            executable: "/usr/bin/git",
            arguments: arguments,
            currentDirectory: repository,
        )
        guard result.status == 0 else {
            throw CommandError.failed(result.stderr)
        }
    }

    private func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String] = [:],
    ) throws -> CommandResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private enum CommandError: Error {
    case failed(String)
}
