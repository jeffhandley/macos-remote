import MacOSRemote
import SwiftUI

struct MLBTVRemoteView: View {
    @ObservedObject var model: RemoteAppModel

    var body: some View {
        VStack(spacing: 0) {
            ModeHeaderView(model: model, currentMode: .mlbTV)

            GeometryReader { geometry in
                let spacing: CGFloat = 14
                VStack(spacing: spacing) {
                    HStack(spacing: spacing) {
                        RemoteButton(
                            title: "Pause / Play",
                            systemImage: "playpause.fill",
                            color: .blue
                        ) {
                            model.send(MLBControls.pauseOrPlay)
                        }
                        RemoteButton(
                            title: "Full Screen",
                            systemImage: "arrow.up.left.and.arrow.down.right",
                            color: .indigo
                        ) {
                            model.send(MLBControls.fullScreen)
                        }
                    }

                    RemoteButton(
                        title: "Skip Commercials",
                        subtitle: "About 2 minutes forward",
                        systemImage: "forward.end.fill",
                        color: .orange
                    ) {
                        model.send(MLBControls.skipCommercials)
                    }
                    .frame(height: geometry.size.height * 0.38)

                    HStack(spacing: spacing) {
                        RemoteButton(
                            title: "Back 10s",
                            systemImage: "gobackward.10",
                            color: .gray
                        ) {
                            model.send(MLBControls.skipBackward)
                        }
                        RemoteButton(
                            title: "Forward 10s",
                            systemImage: "goforward.10",
                            color: .green
                        ) {
                            model.send(MLBControls.skipForward)
                        }
                    }
                }
                .padding(spacing)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            AppOrientation.request(.portrait)
        }
    }
}

private struct RemoteButton: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 38, weight: .semibold))
                Text(title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .foregroundStyle(.white)
            .background(color.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}
