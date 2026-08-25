@testable import AppBundle
import Common
import XCTest

// todo write tests
//
// test 1
//     horizontal
//         window1
//         vertical
//             vertical
//                 window2 <-- focused
//             vertical
//                 window5
//                 horizontal
//                     window3
//                     window4
// pre-condition: focus_wrapping force_workspace
// action: focus up
// expected: mru(window3, window4) is focused

@MainActor
final class FocusCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        XCTAssertTrue(parseCommand("focus --boundaries left").errorOrNil?.contains("Possible values") == true)
        var expected = FocusCmdArgs(rawArgs: [], target: .direction(.left))
        expected.rawBoundaries = .workspace
        testParseSingleCommandSucc("focus --boundaries workspace left", expected)
        testParseSingleCommandSucc("focus container-next", FocusCmdArgs(rawArgs: [], target: .containerRelative(.containerNext)))
        testParseSingleCommandSucc(
            "focus --ignore-floating container-prev",
            FocusCmdArgs(rawArgs: [], target: .containerRelative(.containerPrev)).copy(\.floatingAsTiling, false),
        )
        testParseSingleCommandSucc(
            "focus container-mru-next",
            FocusCmdArgs(rawArgs: [], target: .containerMruRelative(.containerMruNext)),
        )
        testParseSingleCommandSucc(
            "focus --ignore-floating container-mru-prev",
            FocusCmdArgs(rawArgs: [], target: .containerMruRelative(.containerMruPrev)).copy(\.floatingAsTiling, false),
        )

        assertEquals(
            parseCommand("focus --boundaries workspace --boundaries workspace left").errorOrNil,
            "ERROR: Duplicated option '--boundaries'",
        )
        assertEquals(
            parseCommand("focus --window-id 42 --ignore-floating").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertEquals(
            parseCommand("focus --boundaries all-monitors-outer-frame dfs-next").errorOrNil,
            "(dfs-next|dfs-prev) only supports --boundaries workspace",
        )
        assertEquals(
            parseCommand("focus container-next --wrap-around").errorOrNil,
            "(container-next|container-prev|container-mru-next|container-mru-prev) only supports --ignore-floating",
        )
        XCTAssertNotNil(parseCommand("focus container-mru-next --wrap-around").errorOrNil)
        XCTAssertNotNil(parseCommand("focus container-mru-prev --boundaries workspace").errorOrNil)
        XCTAssertNotNil(parseCommand("focus container-mru-next --fail-if-fullscreen").errorOrNil)

        assertEquals(
            parseCommand("focus --window-id 42 --wrap-around").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertEquals(
            parseCommand("focus left --boundaries-action wrap-around-the-workspace --wrap-around").errorOrNil,
            "ERROR: Conflicting options: --boundaries-action, --wrap-around",
        )
        assertEquals(
            parseCommand("focus dfs-next --fail-if-fullscreen").errorOrNil,
            "--fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument",
        )
        assertEquals(
            parseCommand("focus --fail-if-macos-native-fullscreen --window-id 42").errorOrNil,
            "--window-id is incompatible with other options",
        )
        assertNil(parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen left").errorOrNil)
    }

    func testFailIfFullscreen() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isFullscreen = true
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("focus --fail-if-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFailIfMacosNativeFullscreen() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isMacosFullscreenForTest = true

            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("focus --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFailIfFullscreenAllowsRegularWindows() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocus() {
        assertEquals(focus.windowOrNil, nil)
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusOverFloatingWindows() async {
        assertEquals(focus.windowOrNil, nil)
        Workspace.get(byName: name).floatingWindowsContainer.apply {
            TestWindow.new(id: 1, parent: $0, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
            assertEquals(TestWindow.new(id: 2, parent: $0, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100)).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
    }

    func testFocusAlongTheContainerOrientation() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusAcrossTheContainerOrientation() async {
        Workspace.get(byName: name).apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
            TestWindow.new(id: 2, parent: $0.rootTilingContainer)
            assertEquals($0.focusWorkspace(), true)
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus down").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusNoWrapping() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusWrapping() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        await parseCommand("focus --boundaries workspace --boundaries-action wrap-around-the-workspace left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusFindMruLeaf() async {
        let workspace = Workspace.get(byName: name)
        var startWindow: Window!
        var window2: Window!
        var window3: Window!
        var unrelatedWindow: Window!
        workspace.rootTilingContainer.apply {
            startWindow = TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    window2 = TestWindow.new(id: 2, parent: $0)
                    unrelatedWindow = TestWindow.new(id: 5, parent: $0)
                }
                window3 = TestWindow.new(id: 3, parent: $0)
            }
        }

        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3) // The latest bound
        _ = startWindow.focusWindow()
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)

        window2.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)

        window3.markAsMostRecentChild()
        unrelatedWindow.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusOutsideOfTheContainer() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusOutsideOfTheContainer2() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusContainerRelative() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                $0.layout = .accordion
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
            }
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus container-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        await parseCommand("focus container-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus container-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        assertNotEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusContainerRelativeFallsBackToWorkspaceAncestor() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                $0.layout = .accordion
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus container-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
        await parseCommand("focus container-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusContainerRelativeFallsBackToNestedAncestor() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    $0.layout = .accordion
                    assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                }
                TestWindow.new(id: 3, parent: $0)
            }
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus container-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        await parseCommand("focus container-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusContainerRelativeNoopWithoutWiderAncestor() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        await parseCommand("focus container-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusContainerMruCyclesStableSnapshot() async {
        var window1: Window!
        var window2: Window!
        var window3: Window!
        Workspace.get(byName: name).rootTilingContainer.apply {
            $0.layout = .accordion
            window1 = TestWindow.new(id: 1, parent: $0)
            window2 = TestWindow.new(id: 2, parent: $0)
            window3 = TestWindow.new(id: 3, parent: $0)
            TestWindow.new(id: 4, parent: $0)
        }

        assertEquals(window1.focusWindow(), true)
        assertEquals(window3.focusWindow(), true)
        assertEquals(window2.focusWindow(), true)

        for expectedWindowId: UInt32 in [3, 1, 4, 2] {
            await parseCommand("focus container-mru-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, expectedWindowId)
        }
    }

    func testFocusContainerMruPrevStartsAtOldestAndCanChangeDirection() {
        let (windows, current) = makeMruFocusHistory()
        let now = ContinuousClock.now

        assertEquals(
            focusInAncestorContainerMru(current, nextPrev: .containerMruPrev, now: now),
            true,
        )
        assertEquals(focus.windowOrNil?.windowId, 4)
        assertEquals(
            focusInAncestorContainerMru(windows[3], nextPrev: .containerMruNext, now: now.advanced(by: .milliseconds(100))),
            true,
        )
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusContainerMruRestartsAfterTimeout() {
        let (windows, current) = makeMruFocusHistory()
        let now = ContinuousClock.now

        assertEquals(focusInAncestorContainerMru(current, nextPrev: .containerMruNext, now: now), true)
        assertEquals(focus.windowOrNil?.windowId, 3)
        assertEquals(
            focusInAncestorContainerMru(
                windows[2],
                nextPrev: .containerMruNext,
                now: now.advanced(by: .milliseconds(751)),
            ),
            true,
        )
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusContainerMruRestartsAfterExternalFocusChange() {
        let (windows, current) = makeMruFocusHistory()
        let now = ContinuousClock.now

        assertEquals(focusInAncestorContainerMru(current, nextPrev: .containerMruNext, now: now), true)
        assertEquals(windows[3].focusWindow(), true)
        assertEquals(windows[2].focusWindow(), true)
        assertEquals(
            focusInAncestorContainerMru(
                windows[2],
                nextPrev: .containerMruNext,
                now: now.advanced(by: .milliseconds(100)),
            ),
            true,
        )
        assertEquals(focus.windowOrNil?.windowId, 4)
    }

    func testFocusContainerMruRestartsWhenWindowSetChanges() {
        let (windows, current) = makeMruFocusHistory()
        let now = ContinuousClock.now

        assertEquals(focusInAncestorContainerMru(current, nextPrev: .containerMruNext, now: now), true)
        TestWindow.new(id: 5, parent: current.parent.orDie())
        assertEquals(
            focusInAncestorContainerMru(
                windows[2],
                nextPrev: .containerMruNext,
                now: now.advanced(by: .milliseconds(100)),
            ),
            true,
        )
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusContainerMruRestartsWhenContainerChanges() {
        let workspace = Workspace.get(byName: name)
        var firstContainer: TilingContainer!
        var secondContainer: TilingContainer!
        workspace.rootTilingContainer.apply {
            firstContainer = TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1)
            secondContainer = TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1)
        }
        let window1 = TestWindow.new(id: 1, parent: firstContainer)
        let window2 = TestWindow.new(id: 2, parent: firstContainer)
        let window3 = TestWindow.new(id: 3, parent: firstContainer)
        TestWindow.new(id: 4, parent: secondContainer)
        TestWindow.new(id: 5, parent: secondContainer)
        assertEquals(window1.focusWindow(), true)
        assertEquals(window3.focusWindow(), true)
        assertEquals(window2.focusWindow(), true)
        let now = ContinuousClock.now

        assertEquals(focusInAncestorContainerMru(window2, nextPrev: .containerMruNext, now: now), true)
        window3.bind(to: secondContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        assertEquals(
            focusInAncestorContainerMru(
                window3,
                nextPrev: .containerMruNext,
                now: now.advanced(by: .milliseconds(100)),
            ),
            true,
        )
        assertEquals(focus.windowOrNil?.windowId, 4)
    }

    func testFocusContainerMruIncludesFloatingWindowsByDefault() async {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(
            id: 1,
            parent: workspace.rootTilingContainer,
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100),
        )
        let floatingWindow = TestWindow.new(
            id: 2,
            parent: workspace.floatingWindowsContainer,
            rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100),
        )
        assertEquals(floatingWindow.focusWindow(), true)

        await parseCommand("focus container-mru-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
        await parseCommand("focus container-mru-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusContainerMruCanIgnoreFloatingWindows() async {
        let workspace = Workspace.get(byName: name)
        let firstTilingWindow = TestWindow.new(
            id: 1,
            parent: workspace.rootTilingContainer,
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100),
        )
        let secondTilingWindow = TestWindow.new(
            id: 2,
            parent: workspace.rootTilingContainer,
            rect: Rect(topLeftX: 100, topLeftY: 0, width: 100, height: 100),
        )
        TestWindow.new(
            id: 3,
            parent: workspace.floatingWindowsContainer,
            rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100),
        )
        assertEquals(firstTilingWindow.focusWindow(), true)
        assertEquals(secondTilingWindow.focusWindow(), true)

        await parseCommand("focus --ignore-floating container-mru-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusContainerMruFallsBackToNearestWiderAncestor() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                }
                TestWindow.new(id: 3, parent: $0)
            }
        }

        await parseCommand("focus container-mru-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        assertNotEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusContainerMruNoopWithoutWiderAncestor() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        await parseCommand("focus container-mru-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusContainerMruFailsWithoutFocusedWindow() async {
        let result = await parseCommand("focus container-mru-next").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 2)
    }

    private func makeMruFocusHistory() -> ([Window], Window) {
        var windows: [Window] = []
        Workspace.get(byName: name).rootTilingContainer.apply { parent in
            parent.layout = .accordion
            windows = (1 ... 4).map { TestWindow.new(id: UInt32($0), parent: parent) }
        }
        assertEquals(windows[0].focusWindow(), true)
        assertEquals(windows[2].focusWindow(), true)
        assertEquals(windows[1].focusWindow(), true)
        return (windows, windows[1])
    }

    func testFocusDfsRelative() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                    TestWindow.new(id: 3, parent: $0)
                }
            }
            TestWindow.new(id: 4, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)

        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 4)

        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusDfsRelativeWrapping() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)

        assertEquals(await parseCommand("focus --boundaries-action stop dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 1)

        assertEquals(await parseCommand("focus --boundaries-action fail dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
        assertEquals(focus.windowOrNil?.windowId, 1)

        assertEquals(await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 2)

        assertEquals(await parseCommand("focus --boundaries-action stop dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 2)

        assertEquals(await parseCommand("focus --boundaries-action fail dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
        assertEquals(focus.windowOrNil?.windowId, 2)

        assertEquals(await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }
}
