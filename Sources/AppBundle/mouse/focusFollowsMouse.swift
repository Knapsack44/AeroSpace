import AppKit

@MainActor private var focusFollowsMouseMonitor: Any? = nil
@MainActor private var focusFollowsTask: Task<(), any Error>? = nil
@MainActor private var focusFollowsMouseDelayMs: Int = 0

@MainActor func syncFocusFollowsMouse(_ config: Config) {
    let isEnabled = config.focusFollowsMouse.enabled
    let delayMs = config.focusFollowsMouse.delayMs
    if isEnabled == (focusFollowsMouseMonitor != nil), (!isEnabled || delayMs == focusFollowsMouseDelayMs) {
        return
    }

    if let existingMonitor = focusFollowsMouseMonitor {
        NSEvent.removeMonitor(existingMonitor)
        focusFollowsMouseMonitor = nil
        focusFollowsTask?.cancel()
        focusFollowsTask = nil
    }

    if !isEnabled {
        return
    }
    focusFollowsMouseDelayMs = delayMs

    // Interestingly, this callback seems to not fire when the mouse is down which is good,
    // because this is how I want it to work for windows/tabs/files dragging
    focusFollowsMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { @MainActor event in
        let location = event.locationInWindow.withYAxisFlipped
        focusFollowsTask?.cancel()
        focusFollowsTask = Task.startUnstructured { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try checkCancellation()
            if delayMs > 0 {
                try await Task.sleep(for: .milliseconds(delayMs))
                try checkCancellation()
            }
            // Ignores macOS menubar dropdown, but, unfortunately, it doesn't ignore non-native menu-like fake windows.
            // todo: It would be cool to somehow reuse isWindowHeuristic logic here
            let axWindowUnderMouse = await getAxWindowUnderMouse(location)
            if axWindowUnderMouse == .noWindow { return }
            try checkCancellation()
            let workspace = location.monitorApproximation.activeWorkspace
            let window: Window?
            switch axWindowUnderMouse {
                case .window(let windowId):
                    window = Window.get(byId: windowId)
                case .unknown:
                    var foundWindow: Window? = nil
                    for child in workspace.floatingWindowsContainer.mruChildren {
                        try checkCancellation()
                        guard let child = child as? Window else { continue }
                        guard let rect = try await child.getAxRect(.cancellable) else { continue }
                        if rect.contains(location) {
                            foundWindow = child
                            break
                        }
                    }
                    window = foundWindow ?? location.findWindowRecursively(in: workspace.rootTilingContainer, virtual: false, fullscreenCoversAll: true)
                case .noWindow:
                    window = nil
            }
            if let window {
                try await runLightSession(.focusFollowsMouse, token) {
                    _ = window.focusWindow()
                    window.nativeFocus()
                }
            }
        }
    }
}

private enum AxWindowUnderMouse: Equatable {
    case unknown
    case noWindow
    case window(UInt32)
}

@concurrent
private nonisolated func getAxWindowUnderMouse(_ location: CGPoint) async -> AxWindowUnderMouse {
    let systemwide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    if unsafe AXUIElementCopyElementAtPosition(systemwide, Float(location.x), Float(location.y), &element) != .success {
        return .unknown
    }
    guard let element else { return .unknown }
    let windowElement = element.get(Ax.roleAttr) == kAXWindowRole ? element : element.get(Ax.parentWindowRecursive)
    guard let windowElement else { return .noWindow }
    return windowElement.containingWindowId().map { .window($0) } ?? .unknown
}
