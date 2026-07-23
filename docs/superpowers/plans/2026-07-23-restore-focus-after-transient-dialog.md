# Restore Focus After a Transient Dialog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the exact previously focused workspace window after a transient dialog closes, without focus loops.

**Architecture:** Add a small focus resolver that prefers an exact, still-live previous window on the same workspace and otherwise preserves the existing workspace-MRU fallback. Remove the local focus-change mouse movement that amplifies wrong focus decisions. Extend the lifecycle manager's release-tag calculation so this fix can be installed as the next rollback-safe Custom patch release on the existing upstream version.

**Tech Stack:** Swift 6, XCTest, Bash, TOML, AeroSpace Custom lifecycle manager

## Global Constraints

- Do not special-case the 1Password bundle ID or window title.
- Do not change dialog or popup classification heuristics.
- Do not re-enable focus-follows-mouse as part of this fix.
- Preserve the existing fallback when no valid previous window exists.
- Keep only the immediately previous installed release as rollback state.

---

### Task 1: Restore the Previous Focused Window

**Files:**
- Create: `Sources/AppBundleTests/tree/FocusAfterWindowRemovalTest.swift`
- Modify: `Sources/AppBundle/focus.swift:116-118`
- Modify: `Sources/AppBundle/tree/MacWindow.swift:79-102`

**Interfaces:**
- Consumes: `Window.visualWorkspace`, `Workspace.toLiveFocus()`, and the frozen `_prevFocus`.
- Produces: `previousFocusedWindowOrNil: Window?` and `resolveFocusAfterWindowRemoval(previousWindow:workspace:) -> LiveFocus`.

- [ ] **Step 1: Write the failing same-workspace test**

```swift
@testable import AppBundle
import XCTest

@MainActor
final class FocusAfterWindowRemovalTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
    }

    func testPrefersPreviousWindowOnSameWorkspace() {
        let workspace = Workspace.get(byName: "a")
        let previous = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let fallback = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        fallback.markAsMostRecentChild()

        let resolved = resolveFocusAfterWindowRemoval(previousWindow: previous, workspace: workspace)

        assertEquals(resolved.windowOrNil, previous)
        assertEquals(resolved.workspace, workspace)
    }
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter FocusAfterWindowRemovalTest
```

Expected: compilation fails because `resolveFocusAfterWindowRemoval` does not exist.

- [ ] **Step 3: Add the minimal resolver**

Add to `Sources/AppBundle/focus.swift`:

```swift
@MainActor
func resolveFocusAfterWindowRemoval(previousWindow: Window?, workspace: Workspace) -> LiveFocus {
    if let previousWindow, previousWindow.visualWorkspace == workspace {
        return LiveFocus(windowOrNil: previousWindow, workspace: workspace)
    }
    return workspace.toLiveFocus()
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
swift test --filter FocusAfterWindowRemovalTest
```

Expected: `FocusAfterWindowRemovalTest.testPrefersPreviousWindowOnSameWorkspace` passes.

- [ ] **Step 5: Add fallback tests**

Append:

```swift
func testFallsBackWhenPreviousWindowBelongsToAnotherWorkspace() {
    let workspace = Workspace.get(byName: "a")
    let fallback = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
    let previous = TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)

    let resolved = resolveFocusAfterWindowRemoval(previousWindow: previous, workspace: workspace)

    assertEquals(resolved.windowOrNil, fallback)
}

func testFallsBackWhenPreviousWindowNoLongerExists() {
    let workspace = Workspace.get(byName: "a")
    let fallback = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

    let resolved = resolveFocusAfterWindowRemoval(previousWindow: nil, workspace: workspace)

    assertEquals(resolved.windowOrNil, fallback)
}
```

- [ ] **Step 6: Expose the exact previous window and use the resolver**

Add beside `prevFocus` in `Sources/AppBundle/focus.swift`:

```swift
@MainActor
var previousFocusedWindowOrNil: Window? {
    _prevFocus?.windowId.flatMap { Window.get(byId: $0) }
}
```

Replace the focus selection in `MacWindow.garbageCollect` with:

```swift
let deadWindowFocus = resolveFocusAfterWindowRemoval(
    previousWindow: previousFocusedWindowOrNil,
    workspace: deadWindowWorkspace,
)
```

- [ ] **Step 7: Run focused and full Swift tests**

Run:

```bash
swift test --filter FocusAfterWindowRemovalTest
make swift-test
git diff --check
```

Expected: all commands pass.

- [ ] **Step 8: Commit the Core fix**

```bash
git add Sources/AppBundle/focus.swift Sources/AppBundle/tree/MacWindow.swift \
    Sources/AppBundleTests/tree/FocusAfterWindowRemovalTest.swift
git commit -m "Restore focus after transient dialogs close"
```

### Task 2: Register the Custom Patch

**Files:**
- Modify: `custom/patches.toml`

**Interfaces:**
- Consumes: the test class `FocusAfterWindowRemovalTest`.
- Produces: patch-stack metadata for future upstream rebases.

- [ ] **Step 1: Add the patch entry**

```toml
[[patch]]
id = 'restore-focus-after-transient-dialog'
commit-subject = 'Restore focus after transient dialogs close'
status = 'custom-only'
upstream-reference = ''
tests = ['FocusAfterWindowRemovalTest']
retire-when = 'Upstream restores the exact previous live workspace window after a focused transient dialog closes.'
```

- [ ] **Step 2: Verify and commit the patch stack**

Run:

```bash
./script/verify-custom-patch-stack.sh
git diff --check
git add custom/patches.toml
git commit -m "Register transient dialog focus patch"
```

Expected: patch-stack verification passes and the manifest commit succeeds.

### Task 3: Make the Config Hardening Permanent

**Files:**
- Modify: `/Users/markus_feilen/.aerospace.toml`
- Modify: `/Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config/hosts/markus-macbook/home/.aerospace.toml`

**Interfaces:**
- Consumes: the existing `on-focus-changed` callback list.
- Produces: identical active and managed configs without automatic mouse movement and with focus-follows-mouse remaining disabled.

- [ ] **Step 1: Keep the active callback list without mouse movement**

The resulting block must be:

```toml
on-focus-changed = [
    'exec-and-forget /bin/bash /Users/markus_feilen/.config/aerospace/track-ws3-focus-state.sh',
    'exec-and-forget /bin/bash /Users/markus_feilen/.config/aerospace/track-workspace-window-focus.sh',
    'exec-and-forget /bin/bash /Users/markus_feilen/.config/aerospace/sanitize-languagetool-overlays.sh',
]
```

- [ ] **Step 2: Match the managed config**

Keep this line commented and remove the mouse command from the managed callback list:

```toml
# focus-follows-mouse = { enabled = true, delay-ms = 50 }
```

- [ ] **Step 3: Validate both copies**

Run:

```bash
aerospace-custom reload-config --dry-run
cmp /Users/markus_feilen/.aerospace.toml \
    /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config/hosts/markus-macbook/home/.aerospace.toml
/Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config/tests/config-sync-test.sh
```

Expected: dry-run succeeds, `cmp` reports no differences, and config-sync tests pass.

- [ ] **Step 4: Reload and commit the managed config**

Run:

```bash
aerospace-custom reload-config
git -C /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config add \
    hosts/markus-macbook/home/.aerospace.toml
git -C /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config commit \
    -m "Avoid focus-change mouse feedback"
```

Expected: the active app accepts the config and the private repository is clean after the commit.

### Task 4: Support Repeated Custom Releases on One Upstream Version

**Files:**
- Modify: `/Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config/lib/release-package.sh`
- Modify: `/Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config/tests/release-package-test.sh`

**Interfaces:**
- Consumes: local tags matching `custom-<normalized-upstream>.<number>`.
- Produces: `release_tag_for_upstream(upstream_tag)` returning the next unused patch number.

- [ ] **Step 1: Write the failing release-tag test**

Add:

```bash
test_release_tag_increments_for_same_upstream() (
    prepare_release_fixture
    export AEROSPACE_CUSTOM_SOURCE_REPO="$FIXTURE/source"
    mkdir -p "$AEROSPACE_CUSTOM_SOURCE_REPO"
    SOURCE_REPO="$AEROSPACE_CUSTOM_SOURCE_REPO"
    git -C "$AEROSPACE_CUSTOM_SOURCE_REPO" init -q
    git -C "$AEROSPACE_CUSTOM_SOURCE_REPO" config user.name Test
    git -C "$AEROSPACE_CUSTOM_SOURCE_REPO" config user.email test@example.com
    printf 'fixture\n' > "$AEROSPACE_CUSTOM_SOURCE_REPO/file"
    git -C "$AEROSPACE_CUSTOM_SOURCE_REPO" add file
    git -C "$AEROSPACE_CUSTOM_SOURCE_REPO" commit -qm fixture
    git -C "$AEROSPACE_CUSTOM_SOURCE_REPO" tag custom-v0.21.2-beta.1

    assert_equal 'custom-v0.21.2-beta.2' "$(release_tag_for_upstream v0.21.2-Beta)"
)
```

Register it at the bottom:

```bash
test_release_tag_increments_for_same_upstream
pass_test 'increments Custom patch releases on the same upstream tag'
```

- [ ] **Step 2: Run the manager test and verify RED**

Run:

```bash
tests/release-package-test.sh
```

Expected: the new assertion receives `.1` instead of `.2`.

- [ ] **Step 3: Implement next-tag calculation**

Replace `release_tag_for_upstream` with:

```bash
release_tag_for_upstream() {
    upstream_tag="$1"
    normalized="$(printf '%s' "$upstream_tag" | tr '[:upper:]' '[:lower:]')"
    base="custom-$normalized"
    latest="$(
        git -C "$SOURCE_REPO" tag --list "$base.*" |
            while IFS= read -r tag; do
                suffix="${tag#"$base."}"
                case "$suffix" in
                    ''|*[!0-9]*) continue ;;
                esac
                printf '%s\n' "$suffix"
            done |
            sort -n |
            tail -1
    )"
    printf '%s.%s\n' "$base" "$(( ${latest:-0} + 1 ))"
}
```

- [ ] **Step 4: Run all manager tests and commit**

Run:

```bash
tests/release-package-test.sh
for test_file in tests/*-test.sh; do "$test_file"; done
git diff --check
git add lib/release-package.sh tests/release-package-test.sh
git commit -m "Increment repeated Custom release tags"
```

Expected: all manager tests pass.

### Task 5: Build, Install, and Validate

**Files:**
- Verify: all files changed in Tasks 1-4

**Interfaces:**
- Consumes: the clean Custom source candidate and managed configuration.
- Produces: installed `custom-v0.21.2-beta.2` with one rollback release.

- [ ] **Step 1: Run final source verification**

```bash
make swift-test
./script/verify-custom-patch-stack.sh
git diff --check
```

Expected: all commands pass and both repositories are clean.

- [ ] **Step 2: Scan changes for secrets**

```bash
/bin/bash -c '
    . /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config/lib/secret-scan.sh
    secret_scan_paths \
        /Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-stack-rebuild/custom \
        /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config/hosts \
        /Users/markus_feilen/Code/github/Knapsack44/aerospace-custom-config/manifest
'
```

Expected: no credentials, API keys, tokens, or private payloads are reported.

- [ ] **Step 3: Build and install through the lifecycle manager**

```bash
AEROSPACE_CUSTOM_SOURCE_CANDIDATE=/Users/markus_feilen/Code/github/nikitabobko/AeroSpace/.worktrees/custom-stack-rebuild \
    /usr/local/bin/aerospace-custom-manager update --tag v0.21.2-Beta
```

Expected: `custom-v0.21.2-beta.2` builds, installs, passes smoke tests, and preserves `.1` as the sole rollback release.

- [ ] **Step 4: Run the live regression**

1. Focus ChatGPT on WS5.
2. Open 1Password Quick Access with `Cmd+Alt+.`.
3. Copy a username with `Cmd+C`.
4. Confirm ChatGPT remains focused after Quick Access closes.
5. Confirm no NotePlan/Warp focus event and no focus loop occur.

- [ ] **Step 5: Verify rollback metadata**

```bash
/usr/local/bin/aerospace-custom-manager status
aerospace-custom --version
```

Expected: current release is `.2`, the previous `.1` package is the only rollback state, and the Custom CLI is reachable.
