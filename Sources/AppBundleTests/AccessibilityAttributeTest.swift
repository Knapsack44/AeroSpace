@testable import AppBundle
import AppKit
import Testing

struct AccessibilityAttributeTest {
    @Test func focusedWindowAttributeIsWritableBoolean() {
        #expect(Ax.isFocusedAttr.key == kAXFocusedAttribute)
        #expect(Ax.isFocusedAttr.getter(kCFBooleanTrue) == true)
        #expect(Ax.isFocusedAttr.getter(kCFBooleanFalse) == false)
        #expect(Ax.isFocusedAttr.setter(true) as? Bool == true)
        #expect(Ax.isFocusedAttr.setter(false) as? Bool == false)
    }

    @Test func focusedApplicationWindowAttributeIsWritable() {
        let window = AXUIElementCreateSystemWide()
        let value: WindowIdAndAxUiElementMock = (windowId: 42, ax: window)

        #expect(Ax.focusedWindowAttr.key == kAXFocusedWindowAttribute)
        #expect(Ax.focusedWindowAttr.setter(value).map { CFEqual($0, window) } == true)
    }
}
