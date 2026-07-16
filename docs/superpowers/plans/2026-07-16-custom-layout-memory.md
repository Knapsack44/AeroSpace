# AeroSpace Custom Layout Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Custom-only, event-driven layout-memory subsystem that stores complete AeroSpace workspace state per physical monitor topology and safely restores the matching profile after dock, sleep, lock, login, or app-restart transitions.

**Architecture:** The feature is split into pure value-model layers for monitor signatures, snapshots, matching, and restore planning, followed by one serialized `@MainActor` coordinator that owns event coalescing, persistence, and mutation. Every restore is fully resolved and validated into an immutable plan before a synchronous tree commit; callbacks and automatic rules are suppressed only during that transaction. The feature is opt-in, starts in shadow mode, uses no LaunchAgent, and is enabled only in `AeroSpace Custom`.

**Tech Stack:** Swift 6, AppKit, CoreGraphics, AX APIs already wrapped by AeroSpace, TOML configuration, Codable JSON, XCTest, existing AeroSpace command parser and release pipeline, small compatibility shell wrappers.

## Global Constraints

- Preserve Vanilla AeroSpace behavior. Initialize the coordinator only when `aeroSpaceAppId == customAeroSpaceAppId`.
- Treat the current working tree as valuable and dirty. Do not discard unrelated files or generated artifacts.
- Do not use the existing TSV snapshot as an automatic restore source. Preserve it on disk and document it as legacy.
- Do not launch closed applications, unhide hidden applications, unminimize windows, or manipulate native macOS fullscreen windows.
- Do not move the mouse during snapshot or restore.
- Do not call workspace-specific repair scripts after a restore.
- Do not create an automatic undo snapshot before restore.
- Keep snapshots, titles, monitor identifiers, state, and logs local. Add no telemetry, sync, or cloud integration.
- Add no menu-bar UI in v1. Keep AeroBar and AeroMux integrations unchanged; JSON output is the future integration surface.
- Keep this feature private to AeroSpace Custom until the shadow, manual, and automatic field-test phases pass.
- Never restore from an approximate or nearest monitor profile. Profile matching is exact after documented geometric rounding.
- Never mutate the live tree until monitor topology, snapshot compatibility, window matches, and the complete target tree have passed preflight.
- Abort without error or sound if the monitor topology changes before commit.
- Serialize snapshot, restore, pause, profile deletion, and manual-layout transactions through one coordinator.
- Keep normal logs compact. Store detailed tree dumps only at debug level.
- Enforce `0700` directories and `0600` snapshot/state files.
- Enforce hard limits of 500 stored windows and 10 MB per snapshot.
- Use these time budgets:
  - snapshot: warn at 2 seconds, fail at 5 seconds;
  - dry-run: warn at 3 seconds, fail at 10 seconds;
  - restore: warn at 5 seconds, preflight fail at 10 seconds.
- Keep five changed regular snapshots per profile. Pinned snapshots are outside that limit and require explicit deletion.
- Before each commit, run the focused tests for that task and `git diff --check`.

---

## Task 1: Secure the Current Custom Build and Create an Isolated Feature Branch

**Files:**
- Inspect: all tracked changes shown by `git status --short`
- Exclude: `.graphify_python`, `.local-backup/`, `.xcode-build-custom/`, `Sources/AppBundle/graphify-out/`, `graphify-out/`, `Window`, `swift-test`, `xcode/.xcode-build-custom/`, local `AGENTS.md`
- Create worktree: sibling directory selected by `superpowers:using-git-worktrees`

- [ ] **Step 1: Inspect the current diff and recent commit style**

Run:

```bash
git status --short
git diff --stat
git log -8 --oneline
```

Expected: the tracked focus-follows-mouse and custom release changes are visible; recent subjects use short imperative English without a Conventional Commit prefix.

- [ ] **Step 2: Review every tracked file before checkpointing**

Run:

```bash
git diff -- Sources/AppBundle/config/Config.swift
git diff -- Sources/AppBundle/config/parseFocusFollowsMouse.swift
git diff -- Sources/AppBundle/mouse/focusFollowsMouse.swift
git diff -- Sources/AppBundleTests/config/ConfigTest.swift
git diff -- docs/config-examples/default-config.toml
git diff -- install-custom-from-sources.sh
```

Expected: only intended current Custom behavior is included. Stop and ask Markus if an unexpected conflicting edit appears.

- [ ] **Step 3: Create a narrow checkpoint commit**

Stage only the reviewed tracked files. Do not add excluded artifacts.

```bash
git add Sources/AppBundle/config/Config.swift
git add Sources/AppBundle/config/parseFocusFollowsMouse.swift
git add Sources/AppBundle/mouse/focusFollowsMouse.swift
git add Sources/AppBundleTests/config/ConfigTest.swift
git add docs/config-examples/default-config.toml
git add install-custom-from-sources.sh
git diff --cached --check
git commit -m "Preserve current custom window focus behavior"
```

Expected: the working tree still contains excluded untracked files but no uncommitted tracked feature changes.

- [ ] **Step 4: Commit the implementation plan**

```bash
git add docs/superpowers/plans/2026-07-16-custom-layout-memory.md
git diff --cached --check
git commit -m "Document custom layout memory implementation"
```

Expected: the plan is available to the isolated implementation worktree.

- [ ] **Step 5: Create the isolated branch and worktree**

Use `superpowers:using-git-worktrees`. Name the branch:

```text
feature/custom-layout-memory
```

Expected: the new worktree starts at the checkpoint commit and contains none of the excluded build artifacts.

---

## Task 2: Add Custom-Only Configuration and Runtime Gating

**Files:**
- Modify: `Sources/AppBundle/config/Config.swift`
- Modify: `Sources/AppBundle/config/parseConfig.swift`
- Create: `Sources/AppBundle/config/parseCustomLayoutMemory.swift`
- Modify: `Sources/AppBundle/command/impl/ConfigCommand.swift`
- Modify: `Sources/AppBundle/initAppBundle.swift`
- Modify: `docs/config-examples/default-config.toml`
- Test: `Sources/AppBundleTests/config/CustomLayoutMemoryConfigTest.swift`

- [ ] **Step 1: Write failing configuration tests**

Cover:

```swift
@Test func customLayoutMemoryIsDisabledByDefault()
@Test func parsesCompleteCustomLayoutMemoryBlock()
@Test func rejectsUnknownMode()
@Test func rejectsNonPositiveTimingAndHistoryValues()
@Test func stableAppNeverStartsLayoutMemoryCoordinator()
```

The complete parsed configuration must use this value shape:

```swift
enum CustomLayoutMemoryMode: String, Sendable {
    case shadow
    case manual
    case automatic
}

struct CustomLayoutMemoryConfig: ConvenienceMutable, Sendable {
    var enabled = false
    var mode: CustomLayoutMemoryMode = .shadow
    var stabilityDelayMs = 5_000
    var topologySampleIntervalMs = 2_000
    var snapshotIntervalSeconds = 300
    var postTransitionSaveDelaySeconds = 60
    var layoutIdleSeconds = 30
    var historyLimit = 5
    var loginRestoreWindowSeconds = 90
    var failureCooldownSeconds = 600
    var nativeFullscreenDeferralSeconds = 300
    var playSoundAfterAutoRestore = true
    var successSound = "/System/Library/Sounds/Glass.aiff"
    var failureSound = "/System/Library/Sounds/Basso.aiff"
    var pauseSound = "/System/Library/Sounds/Pop.aiff"
    var resumeSound = "/System/Library/Sounds/Ping.aiff"
    var temporaryWindowTitleRegexSubstrings: [String] = []
    var excludedWorkspaces = ["NULL-WORKSPACE", "WS2TMP", "WS3TMP", "WSRESTORETMP"]
}
```

- [ ] **Step 2: Run the tests and confirm failure**

```bash
swift test --filter CustomLayoutMemoryConfigTest
```

Expected: compilation or assertions fail because the configuration does not exist.

- [ ] **Step 3: Implement the parser**

Add `var customLayoutMemory = CustomLayoutMemoryConfig()` to `Config`.

Add:

```swift
"custom-layout-memory": Parser(\.customLayoutMemory, parseCustomLayoutMemory),
```

Implement `parseCustomLayoutMemory` with the existing ordered TOML parser helpers. Reject:

- unknown keys;
- negative or zero timing values;
- `history-limit < 1`;
- invalid regular expressions;
- empty excluded workspace names;
- relative or empty sound paths when sounds are enabled.

The default config source must not enable the feature. Add a fully commented example block to `docs/config-examples/default-config.toml`.

- [ ] **Step 4: Add a single Custom-app gate**

In app startup, create the coordinator only when all are true:

```swift
aeroSpaceAppId == customAeroSpaceAppId
config.customLayoutMemory.enabled
TrayMenuModel.shared.isEnabled
```

When server mode is disabled, keep status inspection available but suspend automatic snapshot and restore work.

- [ ] **Step 5: Run focused verification**

```bash
swift test --filter CustomLayoutMemoryConfigTest
git diff --check
```

Expected: all configuration tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/AppBundle/config Sources/AppBundle/initAppBundle.swift Sources/AppBundleTests/config docs/config-examples/default-config.toml
git commit -m "Add custom layout memory configuration"
```

---

## Task 3: Model Stable Physical Monitor Profiles

**Files:**
- Modify: `Sources/AppBundle/model/Monitor.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryMonitorProfile.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryMonitorProvider.swift`
- Test: `Sources/AppBundleTests/layoutMemory/LayoutMemoryMonitorProfileTest.swift`

- [ ] **Step 1: Write monitor-profile tests**

Test all of these cases:

- monitor enumeration order does not change the signature;
- UUID/vendor/model/serial identity takes priority over names;
- normalized names are fallback only;
- main monitor is part of the profile;
- resolution, backing scale, rotation, and relative placement are part of the profile;
- subpixel coordinate noise inside the rounding tolerance does not change the signature;
- moving the same displays to a different relative arrangement changes the signature;
- clamshell mode is a different active monitor set;
- virtual, Sidecar, and AirPlay displays are accepted only with stable identity;
- two samples with different signatures are not stable.

Use pure test values:

```swift
struct LayoutMemoryMonitorSnapshot: Codable, Equatable, Sendable {
    let displayUuid: String?
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let normalizedName: String
    let frame: CodableRect
    let visibleFrame: CodableRect
    let backingScale: Double
    let rotationDegrees: Double
    let isMain: Bool
}

struct LayoutMemoryMonitorProfile: Codable, Equatable, Sendable {
    let signature: String
    let monitors: [LayoutMemoryMonitorSnapshot]
}
```

- [ ] **Step 2: Confirm the tests fail**

```bash
swift test --filter LayoutMemoryMonitorProfileTest
```

- [ ] **Step 3: Extend `Monitor` with stable CoreGraphics metadata**

Derive `CGDirectDisplayID` from `NSScreenNumber`, then read:

```swift
CGDisplayCreateUUIDFromDisplayID(displayId)
CGDisplayVendorNumber(displayId)
CGDisplayModelNumber(displayId)
CGDisplaySerialNumber(displayId)
CGDisplayRotation(displayId)
screen.backingScaleFactor
```

Do not use transient AeroSpace monitor indexes in signatures.

- [ ] **Step 4: Implement deterministic signature generation**

Normalize names by trimming, collapsing whitespace, and lowercasing only for fallback comparison. Round positions and dimensions to whole logical points and rotation to whole degrees. Sort monitors by stable identity before canonical JSON encoding, then hash with SHA-256.

Include relative topology by translating all frames so the main monitor origin is `(0, 0)`.

- [ ] **Step 5: Verify and commit**

```bash
swift test --filter LayoutMemoryMonitorProfileTest
git diff --check
git add Sources/AppBundle/model/Monitor.swift Sources/AppBundle/layoutMemory Sources/AppBundleTests/layoutMemory
git commit -m "Identify physical monitor layout profiles"
```

---

## Task 4: Define the Versioned Snapshot Schema and Durable Store

**Files:**
- Create: `Sources/AppBundle/layoutMemory/LayoutMemorySnapshot.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryStore.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryState.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryLogger.swift`
- Test: `Sources/AppBundleTests/layoutMemory/LayoutMemoryStoreTest.swift`

- [ ] **Step 1: Write failing schema and store tests**

Cover:

- JSON round trip;
- required `schemaVersion`, app version, build hash, profile, creation time, and fingerprint;
- reject a newer unsupported schema;
- reject snapshots larger than 10 MB or containing more than 500 windows;
- atomic temporary write, decode validation, rename, and directory sync;
- `0700` directories and `0600` files;
- no duplicate regular snapshot for an unchanged fingerprint;
- retain five newest regular changed snapshots;
- pinned versions survive rotation;
- preferred pinned version is selected before latest regular;
- automatic regular snapshots continue while a preferred pinned version exists;
- deleting a pinned or preferred version requires `--force`;
- no automatic profile deletion;
- legacy `latest.tsv` remains untouched and is not loaded.

- [ ] **Step 2: Define the snapshot types**

Use explicit Codable value types:

```swift
struct LayoutMemorySnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let snapshotId: UUID
    let createdAt: Date
    let appVersion: String
    let appBuildHash: String
    let monitorProfile: LayoutMemoryMonitorProfile
    let fingerprint: String
    let workspaces: [LayoutMemoryWorkspaceSnapshot]
    let windows: [LayoutMemoryWindowSnapshot]
    let focus: LayoutMemoryFocusSnapshot
    let label: String?
    let isPinned: Bool
}
```

Represent geometry through Codable scalar structs, not `CGRect`, to keep decoding stable:

```swift
struct CodableRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}
```

Store full nested tiling nodes recursively:

```swift
indirect enum LayoutMemoryTreeNodeSnapshot: Codable, Sendable {
    case container(LayoutMemoryContainerSnapshot)
    case window(LayoutMemoryWindowReference)
}
```

Each container stores orientation, layout, normalized child weights, and active accordion child index. Each floating window stores normalized visible-frame geometry plus absolute geometry for diagnostics.

- [ ] **Step 3: Implement the store layout**

Use:

```text
~/Library/Application Support/AeroSpace Custom/layout-memory/
  state.json
  layout-memory.log
  profiles/<signature>/
    profile.json
    preferred.json
    snapshots/<timestamp>-<uuid>.json
```

`state.json` stores pause state, safety-pause counters, per-profile cooldowns, blocked snapshot IDs, and last successful fingerprints.

- [ ] **Step 4: Implement atomic writes and rotation**

Write to a sibling temporary file, `fsync` it, decode it back, apply limits, rename it atomically, then sync the containing directory. Only then rotate old regular versions.

Rotate logs at 10 MB, retaining five files.

- [ ] **Step 5: Verify and commit**

```bash
swift test --filter LayoutMemoryStoreTest
git diff --check
git add Sources/AppBundle/layoutMemory Sources/AppBundleTests/layoutMemory
git commit -m "Persist versioned layout memory snapshots"
```

---

## Task 5: Export Complete Runtime State Without Side Effects

**Files:**
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryExporter.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryWindowClassifier.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryFingerprint.swift`
- Modify: `Sources/AppBundle/tree/TreeNode.swift`
- Modify: `Sources/AppBundle/tree/TilingContainer.swift`
- Modify: `Sources/AppBundle/tree/Workspace.swift`
- Modify: `Sources/AppBundle/tree/MacWindow.swift`
- Modify: `Sources/AppBundle/command/Command.swift`
- Modify: `Sources/AppBundle/mouse/moveWithMouse.swift`
- Modify: `Sources/AppBundle/mouse/resizeWithMouse.swift`
- Test: `Sources/AppBundleTests/layoutMemory/LayoutMemoryExporterTest.swift`

- [ ] **Step 1: Write failing exporter tests**

Build test trees with `setUpWorkspacesForTests()` and `TestWindow`. Cover:

- nested tiles and accordions;
- orientation, layout, normalized weights, and active accordion child;
- floating normalized geometry;
- AeroSpace fullscreen;
- minimized and hidden workspace assignment without changing visibility;
- native fullscreen recorded as ignored;
- relative floating z-order;
- visible workspace per monitor and global focus;
- persistent empty workspace monitor mapping;
- excluded staging workspaces block snapshots if they contain windows;
- temporary windows are excluded but do not block snapshots;
- snapshot/export does not mutate focus, layout, mouse position, or window geometry;
- identical state produces the same fingerprint.

- [ ] **Step 2: Add a layout-generation counter**

Introduce a monotonic `UInt64` generation owned by the app runtime. Increment it for:

```swift
@MainActor
final class LayoutMemoryRuntime {
    static let shared = LayoutMemoryRuntime()

    private let clock = ContinuousClock()
    private(set) var layoutGeneration: UInt64 = 0
    private(set) var lastLayoutMutationAt: ContinuousClock.Instant?

    func noteLayoutMutation() {
        layoutGeneration &+= 1
        lastLayoutMutationAt = clock.now
    }
}
```

- tree bind/unbind and container layout changes;
- weight changes;
- workspace moves;
- floating move/resize completion;
- fullscreen and tiling/floating transitions;
- monitor/workspace visibility changes.

Do not increment while merely reading or exporting. The coordinator uses the generation to enforce 30 seconds of layout quietness and to revalidate before commit.

- [ ] **Step 3: Implement conservative temporary-window classification**

Exclude a window only when one of these is true:

- AX role/subrole identifies a dialog, sheet, system dialog, popover, tooltip, or utility window;
- it is a known small helper window and not a standard application window;
- its title matches a configured exclusion regex.

If classification is unclear, include the window. Include only windows already managed by AeroSpace.

- [ ] **Step 4: Implement pure tree export**

Read all tree state on `MainActor`, copy it into Sendable value types, and perform JSON encoding and hashing off the main actor. Normalize sibling weights so their sum is `1.0`.

Do not save gaps, keybindings, app rules, global configuration, Mission Control space ordering, AeroBar order, or AeroMux order.

- [ ] **Step 5: Verify and commit**

```bash
swift test --filter LayoutMemoryExporterTest
git diff --check
git add Sources/AppBundle/layoutMemory Sources/AppBundle/tree Sources/AppBundleTests/layoutMemory
git commit -m "Export complete AeroSpace layout state"
```

---

## Task 6: Match Live Windows Conservatively

**Files:**
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryWindowMatcher.swift`
- Test: `Sources/AppBundleTests/layoutMemory/LayoutMemoryWindowMatcherTest.swift`

- [ ] **Step 1: Write failing matcher tests**

Cover the ordered strategy:

1. same live window ID;
2. bundle ID plus exact title;
3. bundle ID plus unique saved title prefix;
4. unique one-to-one unmatched window in the same app;
5. conservative app-order fallback only when the mapping is uniquely determined.

Also test:

- duplicate titles remain ambiguous;
- app-ID-only matching is forbidden when several candidates remain;
- missing windows are reported, not fatal;
- closed applications are not launched;
- native fullscreen windows are unavailable for mutation;
- minimized and hidden windows remain eligible for workspace assignment only;
- new unmatched windows stay unmatched.

- [ ] **Step 2: Implement the stable title-prefix algorithm**

Trim the saved title. Search, in order, for the first separator among:

```text
" — "  " – "  " | "  " • "  " - "
```

Use the text before that separator only when it contains at least four non-whitespace characters. Otherwise use the full title. A prefix match is valid only when exactly one remaining live window from the same bundle ID matches it.

- [ ] **Step 3: Return an auditable result**

```swift
struct LayoutMemoryWindowMatchResult: Sendable {
    let matches: [LayoutMemoryWindowReference: UInt32]
    let missing: [LayoutMemoryWindowReference]
    let ambiguous: [LayoutMemoryAmbiguousWindow]
    let untouchedLiveWindowIds: Set<UInt32>
}
```

Each match records its strategy for dry-run and logs.

- [ ] **Step 4: Verify and commit**

```bash
swift test --filter LayoutMemoryWindowMatcherTest
git diff --check
git add Sources/AppBundle/layoutMemory Sources/AppBundleTests/layoutMemory
git commit -m "Match stored windows conservatively"
```

---

## Task 7: Build and Validate an Immutable Restore Plan

**Files:**
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryRestorePlan.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryRestorePlanner.swift`
- Test: `Sources/AppBundleTests/layoutMemory/LayoutMemoryRestorePlannerTest.swift`

- [ ] **Step 1: Write failing planner tests**

Cover:

- exact monitor profile required;
- no minimum match ratio;
- zero matches is a no-op failure;
- one or more matches produces a partial plan;
- missing windows are removed;
- empty containers are pruned;
- one-child containers are collapsed;
- sibling weights are normalized proportionally;
- missing active accordion child selects the next saved sibling, then previous;
- unmatched tiling windows in a restored workspace are appended in one separate local accordion container;
- unmatched floating windows remain unchanged;
- workspace-to-monitor assignment and visible workspace are planned;
- saved global focus is used when available, otherwise saved focused workspace;
- native fullscreen causes automatic deferral but remains available to manual restore;
- a topology or layout-generation mismatch invalidates the plan.

- [ ] **Step 2: Define detached target types**

The planner must not construct `TreeNode` instances:

```swift
struct ResolvedLayoutMemoryPlan: Sendable {
    let expectedMonitorSignature: String
    let expectedLayoutGeneration: UInt64
    let workspaces: [ResolvedWorkspacePlan]
    let floatingWindows: [ResolvedFloatingWindowPlan]
    let visibility: ResolvedVisibilityPlan
    let focus: ResolvedFocusPlan
    let resultKind: LayoutMemoryRestoreResultKind
}

indirect enum ResolvedLayoutMemoryNode: Sendable {
    case container(ResolvedLayoutMemoryContainer)
    case window(windowId: UInt32, weight: Double)
}
```

- [ ] **Step 3: Validate all invariants before returning a plan**

Reject:

- duplicate window IDs in target trees;
- non-positive or non-finite weights;
- references to unknown monitors or workspaces;
- a target window appearing in both tiling and floating state;
- over-limit or incompatible snapshots;
- an active accordion index outside the post-pruning child range.

- [ ] **Step 4: Verify and commit**

```bash
swift test --filter LayoutMemoryRestorePlannerTest
git diff --check
git add Sources/AppBundle/layoutMemory Sources/AppBundleTests/layoutMemory
git commit -m "Plan layout restores before mutation"
```

---

## Task 8: Commit the Restore Atomically and Suppress Competing Callbacks

**Files:**
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryTransaction.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryRestorer.swift`
- Modify: `Sources/AppBundle/tree/Workspace.swift`
- Modify: `Sources/AppBundle/tree/MacWindow.swift`
- Modify: `Sources/AppBundle/focus.swift`
- Modify: `Sources/AppBundle/layout/refresh.swift`
- Modify: callback entry points for `on-window-detected`, `on-focus-changed`, monitor callbacks, and mouse-follow focus
- Test: `Sources/AppBundleTests/layoutMemory/LayoutMemoryRestorerTest.swift`

- [ ] **Step 1: Write failing atomic-restore tests**

Cover:

- two workspaces restored in one transaction;
- no tree mutation when preflight fails;
- callback suppression during commit;
- new windows discovered during restore are queued and processed once afterward;
- no mouse movement;
- workspace visibility and accordion active children are restored before global focus;
- topology change before commit aborts without mutation;
- topology change after tree commit stops floating/focus follow-up and reports an aborted transition;
- partial success returns success-with-warnings;
- identical fingerprint is a no-op;
- minimized and hidden windows are not unhidden;
- native fullscreen windows are untouched;
- existing workspace-specific repair scripts are never invoked.

- [ ] **Step 2: Add a transaction state**

Use one global MainActor-owned state:

```swift
enum LayoutMemoryTransactionPhase: Sendable {
    case idle
    case preflight
    case committing
}

@MainActor
final class LayoutMemoryTransaction {
    private(set) var phase: LayoutMemoryTransactionPhase = .idle
    private(set) var queuedDetectedWindowIds: Set<UInt32> = []

    var suppressesCallbacks: Bool { phase == .committing }
}
```

Callback sites must check this state. Only `on-window-detected` events for genuinely new non-snapshot windows are queued; focus and monitor callbacks are dropped because the coordinator already owns the transition.

- [ ] **Step 3: Implement synchronous tree commit**

Immediately before commit, re-read:

- current monitor signature;
- current layout generation;
- live window availability.

If any expected value changed, abort before mutation.

Inside one synchronous `@MainActor` section:

1. capture old root references, parent bindings, workspace visibility, and focus for recoverable rollback;
2. unbind only windows included in resolved target workspaces;
3. construct new `TilingContainer` trees from `ResolvedLayoutMemoryNode`;
4. bind matched windows and apply normalized weights;
5. preserve unmatched windows according to the plan;
6. replace all targeted workspace roots;
7. restore accordion active children;
8. restore workspace-to-monitor visibility;
9. apply floating geometry relative to the current monitor visible frame;
10. restore focus last.

No `await`, shell command, refresh session, or AX discovery may occur between steps 2 and 7.

- [ ] **Step 4: Add recoverable rollback**

If a recoverable floating-geometry or focus operation fails after tree commit, keep the valid tree and report partial success. If a recoverable tree operation fails before root replacement, restore captured parents and roots. The planner must eliminate all inputs that would reach `die` or `check` paths.

- [ ] **Step 5: Verify and commit**

```bash
swift test --filter LayoutMemoryRestorerTest
git diff --check
git add Sources/AppBundle/layoutMemory Sources/AppBundle/tree/Workspace.swift Sources/AppBundle/tree/MacWindow.swift Sources/AppBundle/focus.swift Sources/AppBundle/layout/refresh.swift Sources/AppBundleTests/layoutMemory
git commit -m "Restore stored layouts atomically"
```

---

## Task 9: Add Event-Driven Coordination, Shadow Mode, and Safety Controls

**Files:**
- Create: `Sources/AppBundle/layoutMemory/LayoutMemoryCoordinator.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemorySystemObserver.swift`
- Create: `Sources/AppBundle/layoutMemory/LayoutMemorySoundPlayer.swift`
- Modify: `Sources/AppBundle/GlobalObserver.swift`
- Modify: `Sources/AppBundle/initAppBundle.swift`
- Test: `Sources/AppBundleTests/layoutMemory/LayoutMemoryCoordinatorTest.swift`

- [ ] **Step 1: Write coordinator tests with an injected clock**

Use a fake clock, monitor provider, store, exporter, restorer, logger, and sound player. Cover:

- initial Custom app start schedules one restore after five stable seconds;
- two matching topology readings two seconds apart are required;
- the five-second stability timer starts at the first matching reading;
- topology changes restart stabilization;
- wake plus unlock plus display change coalesce into one pending restore;
- one attempt per event outside the login window;
- login window lasts 90 seconds and only integrates windows known by the selected snapshot;
- monitor change ends the login window and does not restart it for the new profile;
- one-monitor known profiles auto-restore in automatic mode;
- unknown profiles learn silently and do not restore;
- shadow mode snapshots and logs plans but never mutates;
- manual mode snapshots automatically but restores only on command;
- automatic mode snapshots and restores;
- no snapshot while locked, sleeping, session-inactive, staging workspaces occupied, inside 60-second transition cooldown, or before 30 seconds of layout quietness;
- snapshots are due at most every five minutes and only when fingerprint changed;
- pre-lock/pre-sleep snapshot is nonblocking and only runs when already eligible;
- native fullscreen defers automatic restore up to five minutes, then abandons it;
- pause persists, records events, and permits manual commands;
- pause requested during preflight aborts before commit, while pause requested after synchronous commit begins waits for that commit to finish safely;
- resume does not retroactively restore or snapshot;
- ordinary keyboard and mouse activity does not postpone an already stable restore;
- manual layout transaction cancels a pending auto restore and starts fresh save gates;
- manual restore remains allowed during pause;
- full auto failure plays Basso and starts a 10-minute per-profile cooldown;
- successful or partial mutation plays Glass only after tree, floating geometry, visibility, and focus work have finished;
- no-op and topology-abort play no sound;
- pause plays Pop and resume plays Ping;
- three full failures for one snapshot/profile auto-block it;
- partial restore does not increment failures;
- a new successful snapshot clears the block;
- manually invoked dry-run and restore remain available for an auto-blocked snapshot;
- repeated internal timeout safety pauses last ten minutes;
- after three consecutive safety pauses, manual resume is required;
- cooldown expiry does not itself trigger a retry.

- [ ] **Step 2: Define the coordinator event model**

```swift
enum LayoutMemoryEvent: Sendable {
    case appStarted
    case monitorParametersChanged
    case willSleep
    case didWake
    case screenLocked
    case screenUnlocked
    case sessionResigned
    case sessionBecameActive
    case safetyTick
}
```

Observe:

```swift
NSWorkspace.willSleepNotification
NSWorkspace.didWakeNotification
NSWorkspace.sessionDidResignActiveNotification
NSWorkspace.sessionDidBecomeActiveNotification
NSApplication.didChangeScreenParametersNotification
DistributedNotificationCenter.default notifications:
    com.apple.screenIsLocked
    com.apple.screenIsUnlocked
```

Use an internal two-second timer only for topology confirmation and due-work checks. Do not recreate a LaunchAgent.

- [ ] **Step 3: Implement event coalescing and mode behavior**

Maintain one pending transition identified by the candidate monitor signature. Wake, unlock, and display changes update that transition instead of adding jobs.

For `shadow`, execute profile resolution, snapshot selection, window matching, and restore planning, then log the exact planned changes without calling the restorer.

User input does not reset the five-second profile timer. Revalidate topology and layout generation immediately before commit instead.

- [ ] **Step 4: Implement pause and manual-layout priority**

Persist pause state in `state.json`.

`manual-change-begin` must:

- cancel a pending automatic restore;
- prevent a new automatic restore;
- return a unique token.

`manual-change-end --token` must:

- reject an unknown token;
- release inhibition;
- reset the 60-second post-transition and 30-second layout-quiet gates;
- not schedule an immediate restore.

- [ ] **Step 5: Verify and commit**

```bash
swift test --filter LayoutMemoryCoordinatorTest
git diff --check
git add Sources/AppBundle/layoutMemory Sources/AppBundle/GlobalObserver.swift Sources/AppBundle/initAppBundle.swift Sources/AppBundleTests/layoutMemory
git commit -m "Coordinate event-driven layout memory"
```

---

## Task 10: Add the Experimental CLI Surface

**Files:**
- Modify: `Sources/Common/cmdArgs/cmdArgsManifest.swift`
- Create: `Sources/Common/cmdArgs/impl/LayoutMemoryCmdArgs.swift`
- Modify: `Sources/AppBundle/command/cmdManifest.swift`
- Create: `Sources/AppBundle/command/impl/LayoutMemoryCommand.swift`
- Create: `docs/aerospace-layout-memory.adoc`
- Modify: `grammar/commands-bnf-grammar.txt`
- Test: `Sources/AppBundleTests/command/LayoutMemoryCmdArgsTest.swift`
- Test: `Sources/AppBundleTests/command/LayoutMemoryCommandTest.swift`

- [ ] **Step 1: Write failing parser and command tests**

Support exactly:

```text
aerospace-custom layout-memory export --output <file>
aerospace-custom layout-memory restore [--input <file>|--version <id>] [--dry-run] [--json]
aerospace-custom layout-memory status [--json]
aerospace-custom layout-memory list [--json]
aerospace-custom layout-memory snapshot [--label <text>]
aerospace-custom layout-memory pause
aerospace-custom layout-memory resume
aerospace-custom layout-memory toggle-pause
aerospace-custom layout-memory pin --version <id> [--label <text>]
aerospace-custom layout-memory prefer --version <id>
aerospace-custom layout-memory unprefer
aerospace-custom layout-memory delete-version --version <id> [--force]
aerospace-custom layout-memory delete-profile --signature <id> [--force]
aerospace-custom layout-memory manual-change-begin
aerospace-custom layout-memory manual-change-end --token <token>
```

Reject conflicting `--input` and `--version`. Default output is human-readable; `--json` emits one stable Codable response object.

- [ ] **Step 2: Add the command kind and parser**

Add:

```swift
case layoutMemory = "layout-memory"
```

Use one top-level `LayoutMemoryCmdArgs` with:

```swift
enum LayoutMemoryAction: Equatable, Sendable {
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
```

- [ ] **Step 3: Implement command behavior**

- `status` and `list` remain readable when disabled or server mode is off.
- Explicit mutation commands return a clear disabled error when `[custom-layout-memory] enabled = false`.
- `restore --dry-run` performs all matching and planning but no mutation.
- `restore` without a target uses the profile's preferred pinned snapshot, otherwise latest regular.
- `snapshot --label` creates a pinned snapshot.
- `export` always writes a standalone compatible JSON snapshot and never changes store history.
- `delete-profile` refuses profiles containing pinned or preferred versions unless `--force`.

- [ ] **Step 4: Generate help and grammar artifacts**

Document the feature as experimental and Custom-only. Run:

```bash
./generate.sh
```

Inspect generated changes; do not hand-edit `ShellParserGenerated/`.

- [ ] **Step 5: Verify and commit**

```bash
swift test --filter LayoutMemory
git diff --check
git add Sources/Common/cmdArgs Sources/AppBundle/command grammar docs ShellParserGenerated
git commit -m "Expose custom layout memory commands"
```

---

## Task 11: Replace the Legacy Automation with Thin Local Integration

**Files outside the repository, applied only after repository tests pass:**
- Modify: `/Users/markus_feilen/.config/aerospace/workspace-layout-memory.sh`
- Modify: `/Users/markus_feilen/.config/aerospace/arrange-workspace-3.sh`
- Modify: `/Users/markus_feilen/.config/aerospace/single-monitor-accordion-reset.sh`
- Modify: `/Users/markus_feilen/.aerospace.toml`
- Keep disabled: `/Users/markus_feilen/Library/LaunchAgents/com.markus-feilen.aerospace-layout-memory.plist`

**Repository documentation:**
- Create: `docs/custom-layout-memory-rollout.adoc`

- [ ] **Step 1: Convert the shell script to a compatibility wrapper**

The wrapper must only translate legacy options to the CLI:

```text
--status
--list
--snapshot [--label <text>]
--restore
--restore-version <id>
--pause
--resume
--toggle-pause
--pin <id> [label]
--prefer <id>
--unprefer
--delete-version <id> [--force]
--delete-profile <signature> [--force]
```

Remove all polling, monitor-signature calculation, snapshot parsing, restore staging, and automatic repair logic from this wrapper. Preserve old TSV files.

- [ ] **Step 2: Enable shadow mode in the personal config**

Add:

```toml
[custom-layout-memory]
enabled = true
mode = 'shadow'
stability-delay-ms = 5000
topology-sample-interval-ms = 2000
snapshot-interval-seconds = 300
post-transition-save-delay-seconds = 60
layout-idle-seconds = 30
history-limit = 5
login-restore-window-seconds = 90
failure-cooldown-seconds = 600
native-fullscreen-deferral-seconds = 300
play-sound-after-auto-restore = true
success-sound = '/System/Library/Sounds/Glass.aiff'
failure-sound = '/System/Library/Sounds/Basso.aiff'
pause-sound = '/System/Library/Sounds/Pop.aiff'
resume-sound = '/System/Library/Sounds/Ping.aiff'
temporary-window-title-regex-substrings = [
    '^Create New Branch',
    '^Push Commits',
    '^Rename Branch',
    '^Git Checkout Problem',
    '^Conflicts',
    '^Commit Changes',
    '^Rollback Changes',
    '^Update Project',
    '^Create New Tag',
    '^Welcome to IntelliJ IDEA',
    '^Unversioned Files',
    '^Move to Another Changelist',
]
excluded-workspaces = ['NULL-WORKSPACE', 'WS2TMP', 'WS3TMP', 'WSRESTORETMP']
```

- [ ] **Step 3: Bind manual restore and persistent pause**

Keep:

```toml
ctrl-alt-cmd-3 = 'exec-and-forget /bin/bash /Users/markus_feilen/.config/aerospace/workspace-layout-memory.sh --restore'
```

Add:

```toml
ctrl-alt-cmd-0 = 'exec-and-forget /bin/bash /Users/markus_feilen/.config/aerospace/workspace-layout-memory.sh --toggle-pause'
```

- [ ] **Step 4: Give manual layout hotkeys priority**

At the start of `arrange-workspace-3.sh` and `single-monitor-accordion-reset.sh`, request a token:

```bash
token="$(aerospace-custom layout-memory manual-change-begin)"
```

Install a trap that always calls:

```bash
aerospace-custom layout-memory manual-change-end --token "$token"
```

The scripts must continue their current layout behavior if layout memory is disabled or the command is unavailable.

- [ ] **Step 5: Ensure the old LaunchAgent stays disabled**

Verify:

```bash
launchctl print-disabled "gui/$(id -u)" | rg 'com.markus-feilen.aerospace-layout-memory'
pgrep -af 'workspace-layout-memory.sh --tick'
```

Expected: disabled is true and no tick process exists.

- [ ] **Step 6: Validate local files**

```bash
bash -n /Users/markus_feilen/.config/aerospace/workspace-layout-memory.sh
bash -n /Users/markus_feilen/.config/aerospace/arrange-workspace-3.sh
bash -n /Users/markus_feilen/.config/aerospace/single-monitor-accordion-reset.sh
aerospace-custom reload-config --dry-run
```

- [ ] **Step 7: Commit repository documentation only**

Do not commit personal config or home-directory scripts to the upstream-derived repository.

```bash
git add docs/custom-layout-memory-rollout.adoc
git commit -m "Document custom layout memory rollout"
```

---

## Task 12: Full Verification, Custom Build, and Staged Rollout

**Files:**
- Review: all changed repository files
- Build artifacts: `.release/AeroSpace Custom.app`, `.release/aerospace`
- Install targets: `/Applications/AeroSpace Custom.app`, `/opt/homebrew/bin/aerospace-custom`

- [ ] **Step 1: Run repository verification**

```bash
git diff --check
./format.sh
./lint.sh
./swift-test.sh
./test.sh
```

Expected: all commands pass. If `./test.sh` is blocked by a dirty-worktree guard, run it from the isolated clean worktree rather than bypassing the guard.

- [ ] **Step 2: Build the Custom release**

```bash
./build-release.sh --build-version 0.21.2-Beta --custom-app --codesign-identity -
```

Verify:

```bash
test -d ".release/AeroSpace Custom.app"
test -x ".release/aerospace"
codesign --verify --deep --strict ".release/AeroSpace Custom.app"
```

- [ ] **Step 3: Install only after build verification**

Install from release artifacts, preserving the existing `aerospace -> aerospace-custom` symlink. Stop any running Custom instance before replacing the app, then launch exactly one Custom instance.

- [ ] **Step 4: Run CLI smoke checks**

```bash
aerospace-custom layout-memory status
aerospace-custom layout-memory status --json
aerospace-custom layout-memory list
aerospace-custom layout-memory snapshot --label "initial-shadow-baseline"
aerospace-custom layout-memory restore --dry-run
```

Expected: status names `AeroSpace Custom`, the snapshot is pinned, and dry-run prints an auditable match/tree plan without changing windows.

- [ ] **Step 5: Complete shadow-mode acceptance**

Keep `mode = 'shadow'` until all are observed:

- one successful single-monitor snapshot;
- one successful three-monitor snapshot;
- one dock disconnect and reconnect;
- one sleep and wake;
- one lock and unlock;
- no monitor-profile churn from enumeration or coordinate noise;
- planned window mapping and tree reconstruction are correct;
- no sustained AeroSpace CPU spike;
- no automatic window mutation.

- [ ] **Step 6: Complete manual-mode acceptance**

Change to:

```toml
mode = 'manual'
```

For both one-monitor and three-monitor profiles:

- alter workspace assignments and nested layout;
- run `restore --dry-run`;
- press `Ctrl+Alt+Cmd+3`;
- verify full tree, floating geometry, workspace visibility, and focus;
- verify native fullscreen, hidden, minimized, unmatched, and ambiguous windows follow the safety rules;
- verify partial restore is reported and plays Glass only after actual mutation.

- [ ] **Step 7: Enable automatic mode**

Only after shadow and manual acceptance:

```toml
mode = 'automatic'
```

Repeat dock, sleep/wake, lock/unlock, app restart, and login scenarios. Verify five-second stabilization, event coalescing, no-op fingerprint skips, sounds, cooldowns, pause hotkey, and manual layout hotkey priority.

- [ ] **Step 8: Final security and scope review**

Before any push:

```bash
git status --short
git diff --check
git diff --cached
rg -n --hidden -g '!/.git' '(api[_-]?key|secret|token|password|Authorization:|BEGIN .*PRIVATE KEY)' .
```

Inspect every match. Do not include personal snapshot data, monitor serials, home-directory configs, logs, or generated local artifacts in a commit.

- [ ] **Step 9: Request a code review**

Use `superpowers:requesting-code-review`. Review specifically for:

- atomicity and callback suppression;
- monitor identity stability;
- fatal tree-invariant paths not eliminated by preflight;
- MainActor blocking and CPU polling;
- snapshot permissions and size limits;
- Vanilla/Custom isolation;
- missing tests for partial and aborted restores.

---

## Acceptance Checklist

- [ ] Vanilla AeroSpace starts with no layout-memory observer, timer, storage access, or command-side mutation.
- [ ] AeroSpace Custom with no `[custom-layout-memory]` block behaves exactly as before.
- [ ] Known one-monitor and multi-monitor profiles restore only after stable exact matching.
- [ ] Unknown profiles are learned without automatic mutation.
- [ ] Sleep, wake, lock, unlock, dock changes, login, and Custom app restart coalesce correctly.
- [ ] Full nested tiling trees, accordions, weights, focus, workspace visibility, and floating geometry restore as specified.
- [ ] Native fullscreen, hidden, minimized, temporary, unmatched, and ambiguous windows follow the conservative rules.
- [ ] Snapshot and restore do not move the mouse or execute workspace repair scripts.
- [ ] Automatic snapshot gates prevent saving transient or actively changing layouts.
- [ ] Pause, safety cooldown, failure blocking, history rotation, pinning, preference, deletion, and export are durable.
- [ ] The legacy LaunchAgent remains disabled and the legacy shell script is only a CLI wrapper.
- [ ] Shadow, manual, and automatic rollout phases have each passed before the next mode is enabled.
