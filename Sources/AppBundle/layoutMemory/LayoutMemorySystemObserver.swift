import AppKit

@MainActor
final class LayoutMemorySystemObserver {
    private let handler: (LayoutMemoryEvent) -> Void

    init(handler: @escaping (LayoutMemoryEvent) -> Void) {
        self.handler = handler
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, .willSleep)
        observe(workspace, NSWorkspace.didWakeNotification, .didWake)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionResigned)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive)
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, .monitorParametersChanged)

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenUnlocked)
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ event: LayoutMemoryEvent,
    ) {
        _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handler(event)
            }
        }
    }
}
