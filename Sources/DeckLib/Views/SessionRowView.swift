import SwiftUI

public struct SessionRowView: View {
    @Bindable var session: Session

    public init(session: Session) {
        self.session = session
    }

    public var body: some View {
        HStack(spacing: 8) {
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

            statusDot
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusDot: some View {
        if let customState = session.status.customState {
            let dotColor = colorForCustomState(customState)
            let isBusy = customState == "working" || customState == "starting"
                || customState == "connected" || customState == "idle"
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .overlay {
                    if isBusy {
                        Circle()
                            .fill(dotColor)
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
        case "working", "starting", "connected", "idle":
            return .white
        case "needs-input":
            return .orange
        case "error":
            return .red
        default:
            return .gray
        }
    }
}
