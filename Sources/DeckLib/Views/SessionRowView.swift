import SwiftUI

public struct SessionRowView: View {
    @Bindable var session: Session

    public init(session: Session) {
        self.session = session
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(session.status.icon ?? session.config.icon)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(.headline)
                    .lineLimit(1)

                // Dynamic status description takes priority over static config description
                if let statusDesc = session.status.desc {
                    Text(statusDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !session.config.description.isEmpty {
                    Text(session.config.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Notification badge
            if session.status.notificationCount > 0 {
                Text("\(session.status.notificationCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.red))
            }

            statusDot
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusDot: some View {
        if let customState = session.status.customState {
            // Dynamic status from program
            Circle()
                .fill(colorForCustomState(customState))
                .frame(width: 10, height: 10)
                .overlay {
                    if customState == "working" {
                        Circle()
                            .fill(colorForCustomState(customState))
                            .frame(width: 10, height: 10)
                            .opacity(0.5)
                            .scaleEffect(1.5)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: customState
                            )
                    }
                }
        } else {
            StatusDotView(state: session.state)
        }
    }

    private func colorForCustomState(_ state: String) -> Color {
        switch state {
        case "working": return .green
        case "idle": return .green
        case "needs-input": return .yellow
        case "error": return .red
        case "connected": return .blue
        default: return .gray
        }
    }
}
