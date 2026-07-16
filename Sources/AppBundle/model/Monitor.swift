import AppKit
import Common

private struct MonitorImpl {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
    let displayUuid: String?
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let backingScale: Double
    let rotationDegrees: Double
}

extension MonitorImpl: Monitor {
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

/// Use it instead of NSScreen because it can be mocked in tests
protocol Monitor: AeroAny {
    /// The index in NSScreen.screens array. 1-based index
    var monitorAppKitNsScreenScreensId: Int { get }
    var name: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
    var isMain: Bool { get }
    var displayUuid: String? { get }
    var vendorNumber: UInt32 { get }
    var modelNumber: UInt32 { get }
    var serialNumber: UInt32 { get }
    var backingScale: Double { get }
    var rotationDegrees: Double { get }
}

final class LazyMonitor: Monitor {
    private let screen: NSScreen
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let width: CGFloat
    let height: CGFloat
    let isMain: Bool
    let displayUuid: String?
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let backingScale: Double
    let rotationDegrees: Double
    private var _rect: Rect?
    private var _visibleRect: Rect?

    init(monitorAppKitNsScreenScreensId: Int, isMain: Bool, _ screen: NSScreen) {
        self.monitorAppKitNsScreenScreensId = monitorAppKitNsScreenScreensId
        self.name = screen.localizedName
        self.width = screen.frame.width // Don't call rect because it would cause recursion during mainMonitor init
        self.height = screen.frame.height // Don't call rect because it would cause recursion during mainMonitor init
        self.screen = screen
        self.isMain = isMain
        let metadata = screen.layoutMemoryDisplayMetadata
        self.displayUuid = metadata.displayUuid
        self.vendorNumber = metadata.vendorNumber
        self.modelNumber = metadata.modelNumber
        self.serialNumber = metadata.serialNumber
        self.backingScale = Double(screen.backingScaleFactor)
        self.rotationDegrees = metadata.rotationDegrees
    }

    var rect: Rect {
        _rect ?? screen.rect.also { _rect = $0 }
    }

    var visibleRect: Rect {
        _visibleRect ?? screen.visibleRect.also { _visibleRect = $0 }
    }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    fileprivate func toMonitor(monitorAppKitNsScreenScreensId: Int) -> Monitor {
        let metadata = layoutMemoryDisplayMetadata
        return MonitorImpl(
            monitorAppKitNsScreenScreensId: monitorAppKitNsScreenScreensId,
            name: localizedName,
            rect: rect,
            visibleRect: visibleRect,
            isMain: isMainScreen,
            displayUuid: metadata.displayUuid,
            vendorNumber: metadata.vendorNumber,
            modelNumber: metadata.modelNumber,
            serialNumber: metadata.serialNumber,
            backingScale: Double(backingScaleFactor),
            rotationDegrees: metadata.rotationDegrees,
        )
    }

    fileprivate var layoutMemoryDisplayMetadata: (
        displayUuid: String?,
        vendorNumber: UInt32,
        modelNumber: UInt32,
        serialNumber: UInt32,
        rotationDegrees: Double,
    ) {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return (nil, 0, 0, 0, 0)
        }
        let displayId = CGDirectDisplayID(number.uint32Value)
        let uuid = unsafe CGDisplayCreateUUIDFromDisplayID(displayId)?.takeRetainedValue()
        let uuidString = uuid.flatMap { CFUUIDCreateString(nil, $0) as String? }
        return (
            uuidString,
            CGDisplayVendorNumber(displayId),
            CGDisplayModelNumber(displayId),
            CGDisplaySerialNumber(displayId),
            CGDisplayRotation(displayId),
        )
    }

    fileprivate var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }

    /// The property is a replacement for Apple's crazy ``frame``
    ///
    /// - For ``MacWindow.topLeftCorner``, (0, 0) is main screen top left corner, and positive y-axis goes down.
    /// - For ``frame``, (0, 0) is main screen bottom left corner, and positive y-axis goes up (which is crazy).
    ///
    /// The property "normalizes" ``frame``
    fileprivate var rect: Rect { frame.monitorFrameNormalized() }

    /// Same as ``rect`` but for ``visibleFrame``
    fileprivate var visibleRect: Rect { visibleFrame.monitorFrameNormalized() }
}

private let testMonitorRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
private let testMonitor = MonitorImpl(
    monitorAppKitNsScreenScreensId: 1,
    name: "Test Monitor",
    rect: testMonitorRect,
    visibleRect: testMonitorRect,
    isMain: true,
    displayUuid: "test-monitor",
    vendorNumber: 0,
    modelNumber: 0,
    serialNumber: 0,
    backingScale: 1,
    rotationDegrees: 0,
)

var mainMonitor: Monitor {
    if isUnitTest { return testMonitor }
    let screens = NSScreen.screens
    // Fallback: If main screen can't be found (e.g., during display reconfiguration),
    // return screens.first or testMonitor to avoid crash
    let screen = screens.withIndex.singleOrNil(where: \.value.isMainScreen) ?? screens.first.map { (0, $0) }
    guard let screen else { return testMonitor }
    return LazyMonitor(monitorAppKitNsScreenScreensId: screen.index + 1, isMain: true, screen.value)
}

var monitors: [Monitor] {
    isUnitTest
        ? [testMonitor]
        : NSScreen.screens.enumerated().map { $0.element.toMonitor(monitorAppKitNsScreenScreensId: $0.offset + 1) }
}

var sortedMonitors: [Monitor] {
    monitors.sortedBy([\.rect.minX, \.rect.minY])
}
