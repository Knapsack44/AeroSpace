@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil
@MainActor private var nativeFocusRetry = NativeFocusRetry()

struct NativeFocusRetry {
    private(set) var pendingWindowId: UInt32?

    mutating func request(windowId: UInt32) {
        pendingWindowId = windowId
    }

    mutating func cancel() {
        pendingWindowId = nil
    }

    func acceptsNativeFocus(windowId: UInt32) -> Bool {
        pendingWindowId == nil || pendingWindowId == windowId
    }

    mutating func consume(requestedWindowId: UInt32, focusedWindowId: UInt32?) -> UInt32? {
        guard pendingWindowId == requestedWindowId else { return nil }
        self.pendingWindowId = nil
        return focusedWindowId == requestedWindowId ? requestedWindowId : nil
    }
}

@MainActor func cancelNativeFocusRetry() {
    nativeFocusRetry.cancel()
}

@MainActor func scheduleNativeFocusRetry(windowId: UInt32, _ retry: @escaping @MainActor () -> Void) {
    nativeFocusRetry.request(windowId: windowId)
    Task.startUnstructured { @MainActor in
        // Some apps honor AX mainness only after their activation reaches the event loop.
        try? await Task.sleep(for: .milliseconds(75))
        guard nativeFocusRetry.consume(requestedWindowId: windowId, focusedWindowId: focus.windowOrNil?.windowId) != nil else {
            return
        }
        retry()
    }
}

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    if nativeFocused?.parent is MacosPopupWindowsContainer {
        return
    }
    if let nativeFocused, !nativeFocusRetry.acceptsNativeFocus(windowId: nativeFocused.windowId) {
        return
    }
    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        _ = nativeFocused?.focusWindow()
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
    }
    nativeFocused?.macAppUnsafe.lastNativeFocusedWindowId = nativeFocused?.windowId
}
