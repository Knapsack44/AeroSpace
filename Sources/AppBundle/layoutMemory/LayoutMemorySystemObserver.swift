import AppKit

@MainActor
final class LayoutMemorySystemObserver {
    private let handler: (LayoutMemoryEvent) -> Void
    private var observers: [NSObjectProtocol] = []

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
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handler(event)
            }
        })
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers = []
    }
}
