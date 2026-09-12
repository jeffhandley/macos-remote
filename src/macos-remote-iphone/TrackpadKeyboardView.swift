import MacOSRemote
import SwiftUI
import UIKit

struct TrackpadKeyboardView: View {
    @ObservedObject var model: RemoteAppModel

    var body: some View {
        VStack(spacing: 0) {
            ModeHeaderView(model: model, currentMode: .trackpad)

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(uiColor: .secondarySystemBackground))
                TrackpadSurface { action in
                    model.send(.pointer(action))
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack {
                    Label("Trackpad", systemImage: "hand.draw")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("1 finger moves • 2 fingers scroll • 3 fingers swipe")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.separator.opacity(0.45))
            }
            .padding()

            KeyboardCaptureView(
                onText: sendText,
                onDelete: {
                    model.send(.key(KeyStroke(key: .delete)))
                }
            )
            .frame(height: 1)
            .opacity(0.02)
            .accessibilityHidden(true)
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            AppOrientation.request(.portrait)
        }
    }

    private func sendText(_ text: String) {
        var accumulated = ""
        for character in text {
            if character == "\n" {
                if !accumulated.isEmpty {
                    model.send(.text(accumulated))
                    accumulated.removeAll(keepingCapacity: true)
                }
                model.send(.key(KeyStroke(key: .return)))
            } else {
                accumulated.append(character)
            }
        }
        if !accumulated.isEmpty {
            model.send(.text(accumulated))
        }
    }
}

private struct TrackpadSurface: UIViewRepresentable {
    let onAction: (PointerAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAction: onAction)
    }

    func makeUIView(context: Context) -> TouchTrackpadView {
        let view = TouchTrackpadView()
        view.actionHandler = context.coordinator.onAction
        return view
    }

    func updateUIView(_ uiView: TouchTrackpadView, context: Context) {
        uiView.actionHandler = context.coordinator.onAction
    }

    final class Coordinator {
        let onAction: (PointerAction) -> Void

        init(onAction: @escaping (PointerAction) -> Void) {
            self.onAction = onAction
        }
    }
}

private final class TouchTrackpadView: UIView {
    var actionHandler: ((PointerAction) -> Void)?

    private var gestureStartedAt = Date()
    private var lastCentroid: CGPoint?
    private var lastTwoFingerDistance: CGFloat?
    private var initialTwoFingerDistance: CGFloat?
    private var totalTranslation = CGPoint.zero
    private var totalMovement: CGFloat = 0
    private var maximumTouchCount = 0
    private var maximumTapCount = 1
    private var isDragging = false
    private var twoFingerMode = TwoFingerMode.undecided

    private enum TwoFingerMode {
        case undecided
        case scroll
        case magnify
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let active = activeTouches(in: event)
        if maximumTouchCount == 0 {
            gestureStartedAt = Date()
            totalTranslation = .zero
            totalMovement = 0
            maximumTapCount = touches.map(\.tapCount).max() ?? 1
        }
        maximumTouchCount = max(maximumTouchCount, active.count)
        lastCentroid = centroid(of: active)
        if active.count == 2 {
            let distance = distance(between: active)
            lastTwoFingerDistance = distance
            initialTwoFingerDistance = distance
            twoFingerMode = .undecided
        } else {
            lastTwoFingerDistance = nil
            initialTwoFingerDistance = nil
        }
        if active.count > 1, isDragging {
            actionHandler?(.endDrag)
            isDragging = false
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let active = activeTouches(in: event)
        guard !active.isEmpty, let currentCentroid = centroid(of: active) else {
            return
        }
        maximumTouchCount = max(maximumTouchCount, active.count)

        guard let previousCentroid = lastCentroid else {
            lastCentroid = currentCentroid
            return
        }
        let delta = CGPoint(
            x: currentCentroid.x - previousCentroid.x,
            y: currentCentroid.y - previousCentroid.y
        )
        lastCentroid = currentCentroid
        totalTranslation.x += delta.x
        totalTranslation.y += delta.y
        totalMovement += hypot(delta.x, delta.y)

        switch active.count {
        case 1:
            if !isDragging,
               Date().timeIntervalSince(gestureStartedAt) >= 0.35 {
                isDragging = true
            }
            let action: PointerAction = isDragging
                ? .drag(
                    deltaX: Double(delta.x * 1.6),
                    deltaY: Double(delta.y * 1.6)
                )
                : .move(
                    deltaX: Double(delta.x * 1.6),
                    deltaY: Double(delta.y * 1.6)
                )
            actionHandler?(action)
        case 2:
            let currentDistance = distance(between: active)
            if twoFingerMode == .undecided,
               let initialDistance = initialTwoFingerDistance,
               initialDistance > 0,
               abs(currentDistance - initialDistance) / initialDistance > 0.08 {
                twoFingerMode = .magnify
            } else if twoFingerMode == .undecided, totalMovement > 6 {
                twoFingerMode = .scroll
            }

            if twoFingerMode == .magnify,
               let previousDistance = lastTwoFingerDistance,
               previousDistance > 0,
               abs(currentDistance - previousDistance) / previousDistance > 0.01 {
                actionHandler?(.magnify(
                    scale: Double(currentDistance / previousDistance)
                ))
            } else if twoFingerMode == .scroll {
                actionHandler?(.scroll(
                    deltaX: Double(delta.x * 1.2),
                    deltaY: Double(delta.y * 1.2)
                ))
            }
            lastTwoFingerDistance = currentDistance
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let active = activeTouches(in: event)
        if !active.isEmpty {
            lastCentroid = centroid(of: active)
            if active.count == 2 {
                let distance = distance(between: active)
                lastTwoFingerDistance = distance
                initialTwoFingerDistance = distance
                twoFingerMode = .undecided
            } else {
                lastTwoFingerDistance = nil
                initialTwoFingerDistance = nil
            }
            return
        }
        finishGesture(cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishGesture(cancelled: true)
    }

    private func finishGesture(cancelled: Bool) {
        if isDragging {
            actionHandler?(.endDrag)
        } else if !cancelled, totalMovement < 12 {
            if maximumTouchCount == 1 {
                actionHandler?(.click(
                    button: .primary,
                    count: min(maximumTapCount, 2)
                ))
            } else if maximumTouchCount == 2 {
                actionHandler?(.click(button: .secondary, count: 1))
            }
        } else if !cancelled, maximumTouchCount >= 3 {
            let horizontal = abs(totalTranslation.x) > abs(totalTranslation.y)
            let distance = horizontal ? abs(totalTranslation.x) : abs(totalTranslation.y)
            if distance > 40 {
                let direction: SwipeDirection
                if horizontal {
                    direction = totalTranslation.x < 0 ? .left : .right
                } else {
                    direction = totalTranslation.y < 0 ? .up : .down
                }
                actionHandler?(.threeFingerSwipe(direction))
            }
        }

        gestureStartedAt = Date()
        lastCentroid = nil
        lastTwoFingerDistance = nil
        initialTwoFingerDistance = nil
        totalTranslation = .zero
        totalMovement = 0
        maximumTouchCount = 0
        maximumTapCount = 1
        isDragging = false
        twoFingerMode = .undecided
    }

    private func activeTouches(in event: UIEvent?) -> [UITouch] {
        (event?.allTouches ?? [])
            .filter { touch in
                touch.phase == .began || touch.phase == .moved || touch.phase == .stationary
            }
    }

    private func centroid(of touches: [UITouch]) -> CGPoint? {
        guard !touches.isEmpty else {
            return nil
        }
        let total = touches.reduce(CGPoint.zero) { result, touch in
            let point = touch.location(in: self)
            return CGPoint(x: result.x + point.x, y: result.y + point.y)
        }
        return CGPoint(
            x: total.x / CGFloat(touches.count),
            y: total.y / CGFloat(touches.count)
        )
    }

    private func distance(between touches: [UITouch]) -> CGFloat {
        guard touches.count == 2 else {
            return 0
        }
        let first = touches[0].location(in: self)
        let second = touches[1].location(in: self)
        return hypot(second.x - first.x, second.y - first.y)
    }
}

private struct KeyboardCaptureView: UIViewRepresentable {
    let onText: (String) -> Void
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onText: onText, onDelete: onDelete)
    }

    func makeUIView(context: Context) -> CaptureTextView {
        let textView = CaptureTextView()
        textView.delegate = context.coordinator
        textView.emptyDeleteHandler = context.coordinator.onDelete
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.smartQuotesType = .yes
        textView.smartDashesType = .yes
        textView.keyboardType = .default
        textView.returnKeyType = .default
        textView.backgroundColor = .clear
        textView.textColor = .clear
        textView.tintColor = .clear
        textView.isAccessibilityElement = false
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }
        return textView
    }

    func updateUIView(_ textView: CaptureTextView, context: Context) {
        context.coordinator.onText = onText
        context.coordinator.onDelete = onDelete
        textView.emptyDeleteHandler = onDelete
        if !textView.isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onText: (String) -> Void
        var onDelete: () -> Void
        private var previousText = ""

        init(
            onText: @escaping (String) -> Void,
            onDelete: @escaping () -> Void
        ) {
            self.onText = onText
            self.onDelete = onDelete
        }

        func textViewDidChange(_ textView: UITextView) {
            let old = Array(previousText)
            let new = Array(textView.text ?? "")
            let prefixCount = commonPrefixCount(old, new)
            let suffixCount = commonSuffixCount(old, new, after: prefixCount)
            let removedCount = old.count - prefixCount - suffixCount
            let insertedEnd = new.count - suffixCount

            for _ in 0 ..< max(0, removedCount) {
                onDelete()
            }
            if prefixCount < insertedEnd {
                onText(String(new[prefixCount ..< insertedEnd]))
            }
            previousText = String(new)

            if new.count > 256, textView.markedTextRange == nil {
                textView.delegate = nil
                textView.text = ""
                previousText = ""
                textView.delegate = self
            }
        }

        private func commonPrefixCount(_ lhs: [Character], _ rhs: [Character]) -> Int {
            var index = 0
            while index < lhs.count, index < rhs.count, lhs[index] == rhs[index] {
                index += 1
            }
            return index
        }

        private func commonSuffixCount(
            _ lhs: [Character],
            _ rhs: [Character],
            after prefixCount: Int
        ) -> Int {
            var count = 0
            while count < lhs.count - prefixCount,
                  count < rhs.count - prefixCount,
                  lhs[lhs.count - 1 - count] == rhs[rhs.count - 1 - count] {
                count += 1
            }
            return count
        }
    }
}

private final class CaptureTextView: UITextView {
    var emptyDeleteHandler: (() -> Void)?

    override func deleteBackward() {
        if text.isEmpty {
            emptyDeleteHandler?()
        } else {
            super.deleteBackward()
        }
    }
}
