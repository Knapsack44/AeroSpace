# Teams Cross-Workspace Container Focus Race Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `focus container-next` and `focus container-prev` focus a Teams `Shared content` window on WS4 without raising or focusing another Teams window on WS5.

**Architecture:** Keep container traversal native and unchanged. Fix the macOS synchronization boundary in `MacApp.nativeFocus(_:)`: AeroSpace must identify the selected AX window as both main and focused before raising it and activating Teams. Validate the logical traversal separately from the asynchronous AX/app-activation behavior, then rebuild and install AeroSpace Custom for the real multi-monitor regression test.

**Tech Stack:** Swift 6, AppKit, macOS Accessibility API, AeroSpace tree model, XCTest, existing Custom release/install pipeline, live CoreGraphics Z-order verification.

## Global Constraints

- Keep `focus container-next` and `focus container-prev` as first-class native commands.
- Do not replace the commands with shell wrappers, chained CLI calls, simulated key presses, Karabiner delays, or app-specific workspace scripts.
- Do not change DFS, cardinal, workspace-wide, or container ancestor-fallback semantics.
- Do not special-case Teams inside `FocusCommand`; the defect is in native window synchronization after the logical target has already been selected.
- Preserve the current Karabiner mapping: `Ctrl+Tab -> F19` and `Ctrl+Shift+Tab -> F20`.
- Preserve the current AeroSpace bindings: `F19 -> focus container-next` and `F20 -> focus container-prev`.
- Preserve the WS4 `Shared content` routing rule and delayed title detector.
- Preserve the visible-WS5 rule in `focus-workspace-stable.sh`: use monitor focus only and never fall through to Teams AX/window focus.
- Keep all changes compatible with the normal app and AeroSpace Custom unless evidence proves Custom-only gating is required.
- Do not remove or commit unrelated untracked artifacts such as `.local-backup/`, `.xcode-build-custom/`, `graphify-out/`, `Window`, or local `AGENTS.md`.
- Before editing tracked source, recheck `git status --short`. The 2026-08-13 checkout had no tracked modifications but did contain unrelated untracked artifacts.
- Before any push, inspect the diff and related files for secrets and credentials.

---

## Persisted Diagnosis

### Exact live scenario

- WS4 on `DELL U4025QW` contains one horizontal accordion with:
  - Screen Sharing window `21658`, title prefix `MBP-MFEI`.
  - Microsoft Teams window `22097`, title prefix `Shared content`.
- WS5 on `Built-in Retina Display` contains:
  - IntelliJ IDEA window `17709`, title prefix `terraform-aws-promise-iam`.
  - Teams meeting window `21567`, title prefix `Meeting in P3`.
  - Additional VS Code, Teams chat, and Warp windows.
- Initial state:
  - IntelliJ is visually in front on WS5.
  - Screen Sharing is focused and visually in front on WS4.
- Trigger: `Ctrl+Tab`, mapped by Karabiner to `F19`, bound to `focus container-next`.
- Expected:
  - Shared Content becomes focused on WS4.
  - IntelliJ remains visually in front of Teams on WS5.
- Observed failure:
  - Teams meeting window moves in front of IntelliJ on WS5.
  - Frequently AeroSpace focus also changes from WS4 to Teams window `21567` on WS5.

### Captured evidence

- Original real-binding reproduction: 3 failures in 5 runs.
- In every failed run both symptoms occurred together:
  - Teams meeting Z-index became lower than IntelliJ's, meaning Teams moved in front.
  - Focus ended as `5<TAB>21567<TAB>Microsoft Teams` instead of `4<TAB>22097<TAB>Microsoft Teams`.
- Direct `aerospace-custom focus --window-id 22097`: 0 failures in 8 runs.
- `aerospace-custom focus container-next` after a synchronous `list-windows --focused` read: 0 failures in 8 runs.
- Relative focus without that synchronization read: one unstable run in six; it remained on Screen Sharing instead of Shared Content.
- The logical container implementation in `FocusCommand.focusInAncestorContainer` selected the expected sibling. Evidence points after target selection, not at traversal or ancestor fallback.

### Root-cause hypothesis

`runLightSession` updates AeroSpace's model synchronously, but `MacApp.nativeFocus(_:)` dispatches an asynchronous AX job. That job currently performs:

```swift
window.set(Ax.isMainAttr, true)
AXUIElementPerformAction(window, kAXRaiseAction as CFString)
nsApp.activate(options: .activateIgnoringOtherApps)
```

It does not set `kAXFocusedAttribute` on the selected window. With multiple visible Teams windows across monitors, Teams/macOS can keep or restore the previous Teams window as the app's focused window. The subsequent AX focused-window notification then overwrites AeroSpace focus with WS5 window `21567`.

The primary proposed correction is:

```swift
window.set(Ax.isMainAttr, true)
window.set(Ax.isFocusedAttr, true)
AXUIElementPerformAction(window, kAXRaiseAction as CFString)
nsApp.activate(options: .activateIgnoringOtherApps)
```

This is a hypothesis until the failing live loop passes after the rebuilt Custom app is installed. If `AXFocused=true` is unsupported or does not eliminate the race, do not add sleeps or shell workarounds; continue with the fallback investigation described in Task 4.

---

## File Map

- Modify `Sources/AppBundle/util/accessibility.swift`: expose the existing `kAXFocusedAttribute` as a writable Boolean AX attribute named `Ax.isFocusedAttr`.
- Modify `Sources/AppBundle/tree/MacApp.swift`: set the selected window focused before raising it and activating its app.
- Create `Sources/AppBundleTests/AccessibilityAttributeTest.swift`: verify writable focused-attribute metadata.
- Inspect `Sources/AppBundle/command/impl/FocusCommand.swift`: confirm no container traversal change is needed.
- Use `build-release.sh` and the existing Custom installer only after Swift tests pass.
- Do not modify `.aerospace.toml`, Karabiner, `focus-workspace-stable.sh`, or Teams-routing scripts for this fix.

---

### Task 1: Lock Down the AX Focus Contract

**Files:**
- Modify: `Sources/AppBundle/util/accessibility.swift:239-247`
- Test: `Sources/AppBundleTests/AccessibilityAttributeTest.swift`

**Interfaces:**
- Consumes: existing `Ax.WritableAttrImpl<Bool>` and `AXUIElement.set(_:_:)`.
- Produces: `Ax.isFocusedAttr: Ax.WritableAttrImpl<Bool>` with key `kAXFocusedAttribute` and Boolean getter/setter.

- [ ] **Step 1: Recheck the working tree and relevant source**

Run:

```bash
git status --short
sed -n '225,255p' Sources/AppBundle/util/accessibility.swift
sed -n '135,165p' Sources/AppBundle/tree/MacApp.swift
```

Expected: no tracked edits overlap the two target files. If tracked overlap exists, stop and reconcile it explicitly; do not overwrite it.

- [ ] **Step 2: Add a failing focused-attribute test**

Create `Sources/AppBundleTests/AccessibilityAttributeTest.swift`:

```swift
@testable import AppBundle
import AppKit
import Testing

struct AccessibilityAttributeTest {
    @Test func focusedAttributeIsWritableBoolean() {
        #expect(Ax.isFocusedAttr.key == kAXFocusedAttribute)
        #expect(Ax.isFocusedAttr.getter(kCFBooleanTrue) == true)
        #expect(Ax.isFocusedAttr.getter(kCFBooleanFalse) == false)
        #expect(Ax.isFocusedAttr.setter(true) as? Bool == true)
        #expect(Ax.isFocusedAttr.setter(false) as? Bool == false)
    }
}
```

- [ ] **Step 3: Run the test and confirm failure**

Run:

```bash
swift test --filter AccessibilityAttributeTest
```

Expected: compilation fails because `Ax.isFocusedAttr` does not exist.

- [ ] **Step 4: Make the focused attribute writable**

Replace the current read-only declaration:

```swift
static let isFocused = ReadableAttrImpl<Bool>(
    key: kAXFocusedAttribute,
    getter: { $0 as? Bool },
)
```

with:

```swift
static let isFocusedAttr = WritableAttrImpl<Bool>(
    key: kAXFocusedAttribute,
    getter: { $0 as? Bool },
    setter: { $0 as CFTypeRef },
)
```

Update the existing read sites in `AxUiElementWindowType.swift` from `Ax.isFocused` to `Ax.isFocusedAttr`.

- [ ] **Step 5: Run focused tests**

Run:

```bash
swift test --filter AccessibilityAttributeTest
swift test --filter AxWindowKindTest
git diff --check
```

Expected: all tests pass and the diff has no whitespace errors.

- [ ] **Step 6: Commit the AX contract change**

First inspect recent history and match its subject style:

```bash
git log -8 --oneline
git add Sources/AppBundle/util/accessibility.swift Sources/AppBundle/model/AxUiElementWindowType.swift Sources/AppBundleTests/AccessibilityAttributeTest.swift
git diff --cached --check
git commit -m "Make focused AX window attribute writable"
```

Expected: one atomic commit containing only the AX attribute contract and its tests.

---

### Task 2: Apply Focus to the Selected Native Window

**Files:**
- Modify: `Sources/AppBundle/tree/MacApp.swift:142-162`

**Interfaces:**
- Consumes: `Ax.isFocusedAttr` from Task 1.
- Produces: native focus sequence `AXMain=true`, `AXFocused=true`, `AXRaise`, app activation.

- [ ] **Step 1: Confirm that the live loop is the regression seam**

Inspect the production boundary:

```bash
sed -n '135,165p' Sources/AppBundle/tree/MacApp.swift
sed -n '55,95p' Sources/AppBundle/layout/refresh.swift
```

Expected: `MacApp.nativeFocus(_:)` accepts concrete `NSRunningApplication` and `AXUIElement` values and dispatches the operation asynchronously. Existing test doubles stop at AeroSpace's logical `Window.nativeFocus()` boundary. Therefore an operation-order unit test would merely copy the production statements into closures and would not reproduce the macOS/Teams race. Record Task 3's live harness as the regression seam; do not introduce a mock framework or broaden `AxUiElementMock` solely for this fix.

- [ ] **Step 2: Apply the minimal native-focus change**

In the asynchronous `withWindowAsync` body, use:

```swift
window.set(Ax.isMainAttr, true)
window.set(Ax.isFocusedAttr, true)
AXUIElementPerformAction(window, kAXRaiseAction as CFString)
nsApp.activate(options: .activateIgnoringOtherApps)
```

Do not reorder app activation ahead of AX window selection. Do not add sleeps or retries in this task.

- [ ] **Step 3: Run focused and broad Swift tests**

Run:

```bash
swift test --filter AccessibilityAttributeTest
swift test --filter FocusCommandTest
make swift-test
git diff --check
```

Expected: tests pass; container target-selection tests remain unchanged; only native synchronization behavior changes.

- [ ] **Step 4: Run formatting and lint checks**

Run:

```bash
make format
make lint
git diff --check
```

Expected: no new lint or formatting violations. Review formatter output and exclude unrelated changes.

- [ ] **Step 5: Commit the native-focus correction**

```bash
git add Sources/AppBundle/tree/MacApp.swift
git diff --cached --check
git commit -m "Focus the selected native window before activation"
```

---

### Task 3: Build, Install, and Run the Exact Live Regression

**Files:**
- Build artifact: `.release/AeroSpace Custom.app`
- Installed app: `/Applications/AeroSpace Custom.app`
- CLI: `/opt/homebrew/bin/aerospace-custom`
- Temporary test harness: `/tmp/repro-ctrl-tab-teams-cross-workspace.sh`

**Interfaces:**
- Consumes: rebuilt Custom app containing Tasks 1 and 2.
- Produces: measured pass/fail evidence for focus workspace/window and per-monitor Z-order.

- [ ] **Step 1: Build the Custom release**

Run the repository's current documented Custom release path. At the time this plan was written, the expected command was:

```bash
./build-release.sh --build-version 0.21.2-Beta --custom-app --codesign-identity -
```

Expected: `.release/AeroSpace Custom.app` and `.release/aerospace` exist and validate. If the branch has a newer release version or manager workflow, use that workflow rather than hard-coding an obsolete version.

- [ ] **Step 2: Install with rollback preserved**

Use the existing `aerospace-custom-manager` or Custom install script so the immediately previous installed version remains available for rollback. Do not manually delete the previous app first.

Expected: exactly one running `AeroSpace Custom` process after restart, and both `aerospace` and `aerospace-custom` route to it.

- [ ] **Step 3: Recreate the exact window state**

Required live state:

```text
WS4 / DELL U4025QW:
  Screen Sharing (front)
  Shared content (behind)

WS5 / Built-in Retina Display:
  IntelliJ IDEA (front)
  Teams meeting (behind)
```

Abort the live test if either Shared Content or Screen Sharing is absent; substituting another app would not exercise the reported bug.

- [ ] **Step 4: Run the original trigger loop at least 20 times**

For every iteration:

1. Focus IntelliJ on WS5.
2. Focus Screen Sharing on WS4.
3. Confirm AeroSpace focus is `WS4 + Screen Sharing`.
4. Trigger the real `F19` binding, equivalent to physical `Ctrl+Tab` through Karabiner.
5. Wait 750 ms for AX/app activation to settle.
6. Assert AeroSpace focus is `WS4 + Shared content`.
7. Read CoreGraphics on-screen window ordering and assert IntelliJ remains before the Teams meeting window on the internal-display coordinates.

Pass criterion:

```text
20/20 iterations:
focused workspace = 4
focused window = Shared content
IntelliJ Z-index < Teams meeting Z-index
```

The pre-fix baseline was 3 failures in 5 runs. Any post-fix focus jump or WS5 Z-order inversion is a failure.

- [ ] **Step 5: Run reverse-cycle and non-Teams regressions**

Verify:

```text
F20: Shared content -> Screen Sharing, focus remains on WS4
F19: Screen Sharing -> Shared content, focus remains on WS4
Ctrl+Tab on an accordion without Teams: unchanged
Ctrl+5 while Screen Sharing is front on WS4: Teams focuses on WS5 without raising Shared content on WS4
```

- [ ] **Step 6: Remove temporary instrumentation**

Delete `/tmp/repro-ctrl-tab-teams-cross-workspace.sh`, temporary compiled Z-order helpers, and any uniquely tagged debug logging. Do not delete persistent operational logs or unrelated `/tmp` files.

- [ ] **Step 7: Record validation in the final commit or PR body**

Include:

```text
Before: 3/5 Ctrl+Tab runs raised/focused Teams on WS5.
After: 20/20 runs focused Shared content on WS4 and preserved IntelliJ over Teams on WS5.
```

Do not claim the issue fixed without this live evidence.

---

### Task 4: Fallback Investigation if `AXFocused=true` Is Insufficient

**Files:**
- Inspect: `Sources/AppBundle/layout/refresh.swift`
- Inspect: `Sources/AppBundle/tree/MacApp.swift`
- Inspect: `Sources/AppBundle/focusCache.swift`
- Create on proven stale-job diagnosis: `Sources/AppBundleTests/model/NativeFocusGenerationTest.swift`

**Interfaces:**
- Consumes: failed Task 3 trace after the focused-attribute change.
- Produces: cancellation/generation guard only if evidence proves a stale native-focus job wins.

- [ ] **Step 1: Capture the winning focus sequence**

Instrument only these boundaries with one removable prefix such as `[DEBUG-native-focus-race]`:

```text
runLightSession focusBefore/focusAfter window IDs
MacApp.nativeFocus requested window ID and app PID
native focus job start/completion/cancellation
updateFocusCache native window ID
```

Run the exact Task 3 loop until one failure occurs. Do not log titles or unrelated AX traffic.

- [ ] **Step 2: Classify the failed trace**

Use these decisions:

```text
If a stale focus job completes after the newer job:
  add a monotonically increasing native-focus generation and ignore stale completion.

If Teams reports window 21567 after job 22097 completed correctly:
  confirm AXFocused writability/result and test setting focused-window attribute on the AX application.

If move-mouse callback initiates the WS5 focus:
  fix focus-follows-mouse suppression during programmatic focus; do not special-case Teams.
```

- [ ] **Step 3: Write a failing test for the proven branch**

For a stale-job diagnosis, test this exact ordering:

```swift
requestFocus(windowId: 21567)
requestFocus(windowId: 22097)
completeJob(windowId: 21567)
completeJob(windowId: 22097)
#expect(appliedWindowIds == [22097])
```

Do not implement a generation guard unless the captured trace proves stale completion.

- [ ] **Step 4: Implement only the proven correction**

Keep the correction in the generic native-focus subsystem. Do not modify `FocusCommand`, Teams routing, workspace bindings, or Karabiner.

- [ ] **Step 5: Repeat all Task 2 and Task 3 verification**

Expected: focused tests pass and the exact live loop reaches 20/20 successful iterations.

---

## Completion Criteria

- `focus container-next` and `focus container-prev` remain native commands.
- No shell wrapper or timing delay is introduced into F19/F20.
- Screen Sharing and Shared Content cycle locally on WS4.
- Cycling to Shared Content never raises the Teams meeting window above the previously frontmost non-Teams window on WS5.
- AeroSpace focus remains on WS4 throughout the cycle.
- Existing WS5 `Ctrl+5`, WS6, DFS, cardinal, and non-Teams container focus behavior remain unchanged.
- Focused tests, `make swift-test`, formatting, lint, and `git diff --check` pass.
- Rebuilt and installed AeroSpace Custom passes the exact live regression 20/20 times.

## Resume Prompt

Use this prompt in a future session:

```text
Implement docs/superpowers/plans/2026-08-13-teams-cross-workspace-container-focus-race.md. Recheck the live window IDs and current upstream source before editing. Preserve native container focus; do not use a shell wrapper.
```
