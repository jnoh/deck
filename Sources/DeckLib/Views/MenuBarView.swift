import SwiftUI

public struct MenuBarView: View {
    let sessionManager: SessionManager
    let onSelectSession: (String) -> Void
    let onStartAll: () -> Void
    let onStopAll: () -> Void

    public init(
        sessionManager: SessionManager,
        onSelectSession: @escaping (String) -> Void,
        onStartAll: @escaping () -> Void,
        onStopAll: @escaping () -> Void
    ) {
        self.sessionManager = sessionManager
        self.onSelectSession = onSelectSession
        self.onStartAll = onStartAll
        self.onStopAll = onStopAll
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sessionManager.sessions.isEmpty {
                Text("No sessions configured")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(sessionManager.sessions) { session in
                    Button {
                        onSelectSession(session.id)
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor(for: session.state))
                                .frame(width: 8, height: 8)
                            Text(session.config.icon)
                            Text(session.displayName)
                            Spacer()
                            Text(session.state.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            Button("Start All") {
                onStartAll()
            }
            .disabled(sessionManager.stoppedSessions.isEmpty)

            Button("Stop All") {
                onStopAll()
            }
            .disabled(sessionManager.runningSessions.isEmpty && sessionManager.degradedSessions.isEmpty)

            Divider()
                .padding(.vertical, 4)

            Button("Quit Deck") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(4)
    }

    private func statusColor(for state: SessionState) -> Color {
        switch state {
        case .running: return .green
        case .degraded: return .yellow
        case .stopped: return .gray
        default: return .blue
        }
    }
}
