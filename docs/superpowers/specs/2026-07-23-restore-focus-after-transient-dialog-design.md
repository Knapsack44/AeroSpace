# Restore Focus After a Transient Dialog Closes

## Problem

1Password Quick Access reports itself as an `AXStandardWindow`. AeroSpace therefore classifies it as a dialog and
binds it to the focused workspace's `FloatingWindowsContainer`.

When the dialog closes, `MacWindow.garbageCollect` currently resolves a new focus from the workspace MRU tree. The
now-empty floating container can remain the workspace's most-recent child, causing `Workspace.toLiveFocus()` to fall
back to an unrelated window such as NotePlan or Warp instead of the window focused before Quick Access opened.

The local `on-focus-changed` command `move-mouse window-lazy-center` amplifies the incorrect fallback into repeated
focus changes.

## Design

When a focused window is removed from a regular workspace container:

1. Prefer `prevFocus` when its window still exists and belongs to the same workspace.
2. Otherwise retain the existing `Workspace.toLiveFocus()` fallback.
3. Keep the existing native-focus guard and popup-container behavior unchanged.

This restores the pre-dialog window without adding application-specific 1Password matching or changing window-type
heuristics.

The managed and active AeroSpace configurations will also remove `move-mouse window-lazy-center` from
`on-focus-changed`. The remaining tracking callbacks stay unchanged.

## Testing

- Add a focused unit test for selecting a valid previous focus in the same workspace.
- Add fallback tests for a missing previous window and a previous window on another workspace.
- Run the focused Swift tests and the complete Swift package test suite.
- Validate and reload the managed AeroSpace configuration.
- Reproduce Quick Access with ChatGPT focused and confirm that closing it restores ChatGPT without a focus loop.

## Non-Goals

- Do not special-case the 1Password bundle ID or window title.
- Do not change dialog or popup classification heuristics.
- Do not re-enable focus-follows-mouse as part of this fix.
