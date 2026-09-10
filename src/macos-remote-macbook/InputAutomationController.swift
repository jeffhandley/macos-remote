import AppKit
import ApplicationServices
import MacOSRemote

@MainActor
final class InputAutomationController {
    private var isDragging = false

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func execute(_ command: RemoteCommand) async {
        guard isAccessibilityGranted else {
            return
        }

        switch command {
        case let .key(stroke):
            post(stroke)
        case let .text(text):
            post(text: text)
        case let .pointer(action):
            post(pointer: action)
        case let .keySequence(steps):
            for step in steps {
                guard !Task.isCancelled else {
                    return
                }
                if step.delayMilliseconds > 0 {
                    try? await Task.sleep(
                        for: .milliseconds(step.delayMilliseconds)
                    )
                }
                guard !Task.isCancelled else {
                    return
                }
                post(step.stroke)
            }
        }
    }

    func cancelInteractions() {
        if isDragging {
            postMouse(type: .leftMouseUp, button: .left)
            isDragging = false
        }
    }

    private func post(_ stroke: KeyStroke) {
        guard let keyCode = keyCode(for: stroke.key) else {
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = eventFlags(for: stroke.modifiers)
        let down = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        )
        let up = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        )
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func post(text: String) {
        for chunk in text.utf16.chunked(maximumCount: 20) {
            let source = CGEventSource(stateID: .hidSystemState)
            guard let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
            ),
                let up = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: 0,
                    keyDown: false
                )
            else {
                continue
            }
            chunk.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: buffer.baseAddress
                )
                up.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: buffer.baseAddress
                )
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private func post(pointer action: PointerAction) {
        switch action {
        case let .move(deltaX, deltaY):
            moveMouse(deltaX: deltaX, deltaY: deltaY, dragging: false)
        case let .scroll(deltaX, deltaY):
            guard deltaX.isFinite, deltaY.isFinite else {
                return
            }
            let event = CGEvent(
                scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
                units: .pixel,
                wheelCount: 2,
                wheel1: clampedScrollValue(-deltaY),
                wheel2: clampedScrollValue(-deltaX),
                wheel3: 0
            )
            event?.post(tap: .cghidEventTap)
        case let .click(button, count):
            let mouseButton: CGMouseButton = button == .primary ? .left : .right
            let downType: CGEventType = button == .primary ? .leftMouseDown : .rightMouseDown
            let upType: CGEventType = button == .primary ? .leftMouseUp : .rightMouseUp
            postMouse(type: downType, button: mouseButton, clickCount: count)
            postMouse(type: upType, button: mouseButton, clickCount: count)
        case let .drag(deltaX, deltaY):
            if !isDragging {
                postMouse(type: .leftMouseDown, button: .left)
                isDragging = true
            }
            moveMouse(deltaX: deltaX, deltaY: deltaY, dragging: true)
        case .endDrag:
            cancelInteractions()
        case let .magnify(scale):
            guard abs(scale - 1) > 0.02 else {
                return
            }
            post(KeyStroke(
                key: scale > 1 ? .equal : .minus,
                modifiers: .command
            ))
        case let .threeFingerSwipe(direction):
            let key: RemoteKey = switch direction {
            case .up: .upArrow
            case .down: .downArrow
            case .left: .leftArrow
            case .right: .rightArrow
            }
            post(KeyStroke(key: key, modifiers: .control))
        }
    }

    private func moveMouse(deltaX: Double, deltaY: Double, dragging: Bool) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let destination = CGPoint(
            x: current.x + deltaX,
            y: current.y + deltaY
        )
        let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: dragging ? .leftMouseDragged : .mouseMoved,
            mouseCursorPosition: destination,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
    }

    private func postMouse(
        type: CGEventType,
        button: CGMouseButton,
        clickCount: Int = 1
    ) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        )
        event?.setIntegerValueField(
            .mouseEventClickState,
            value: Int64(max(1, clickCount))
        )
        event?.post(tap: .cghidEventTap)
    }

    private func eventFlags(for modifiers: ModifierKeys) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private func clampedScrollValue(_ value: Double) -> Int32 {
        Int32(min(max(value.rounded(), Double(Int32.min)), Double(Int32.max)))
    }

    private func keyCode(for key: RemoteKey) -> CGKeyCode? {
        switch key {
        case .a: 0
        case .s: 1
        case .d: 2
        case .f: 3
        case .h: 4
        case .g: 5
        case .z: 6
        case .x: 7
        case .c: 8
        case .v: 9
        case .b: 11
        case .q: 12
        case .w: 13
        case .e: 14
        case .r: 15
        case .y: 16
        case .t: 17
        case .one: 18
        case .two: 19
        case .three: 20
        case .four: 21
        case .six: 22
        case .five: 23
        case .equal: 24
        case .nine: 25
        case .seven: 26
        case .minus: 27
        case .eight: 28
        case .zero: 29
        case .rightBracket: 30
        case .o: 31
        case .u: 32
        case .leftBracket: 33
        case .i: 34
        case .p: 35
        case .return: 36
        case .l: 37
        case .j: 38
        case .quote: 39
        case .k: 40
        case .semicolon: 41
        case .backslash: 42
        case .comma: 43
        case .slash: 44
        case .n: 45
        case .m: 46
        case .period: 47
        case .tab: 48
        case .space: 49
        case .grave: 50
        case .delete: 51
        case .escape: 53
        case .capsLock: 57
        case .f1: 122
        case .f2: 120
        case .f3: 99
        case .f4: 118
        case .f5: 96
        case .f6: 97
        case .f7: 98
        case .f8: 100
        case .f9: 101
        case .f10: 109
        case .f11: 103
        case .f12: 111
        case .home: 115
        case .pageUp: 116
        case .forwardDelete: 117
        case .end: 119
        case .pageDown: 121
        case .leftArrow: 123
        case .rightArrow: 124
        case .downArrow: 125
        case .upArrow: 126
        }
    }
}

private extension Collection {
    func chunked(maximumCount: Int) -> [[Element]] {
        var result: [[Element]] = []
        var chunk: [Element] = []
        chunk.reserveCapacity(maximumCount)
        for element in self {
            chunk.append(element)
            if chunk.count == maximumCount {
                result.append(chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            result.append(chunk)
        }
        return result
    }
}
