import Foundation

public enum MLBControls {
    public static let pauseOrPlay = RemoteCommand.key(KeyStroke(key: .space))
    public static let fullScreen = RemoteCommand.key(KeyStroke(key: .f))
    public static let skipForward = RemoteCommand.key(KeyStroke(key: .rightArrow))
    public static let skipBackward = RemoteCommand.key(KeyStroke(key: .leftArrow))

    public static let skipCommercials: RemoteCommand = {
        var steps = [
            KeySequenceStep(stroke: KeyStroke(key: .escape)),
            KeySequenceStep(stroke: KeyStroke(key: .rightArrow)),
        ]

        steps.append(
            contentsOf: (0 ..< 11).map { _ in
                KeySequenceStep(
                    delayMilliseconds: 1_000,
                    stroke: KeyStroke(key: .rightArrow)
                )
            }
        )
        steps.append(
            KeySequenceStep(
                delayMilliseconds: 3_000,
                stroke: KeyStroke(key: .f)
            )
        )
        return .keySequence(steps)
    }()
}
