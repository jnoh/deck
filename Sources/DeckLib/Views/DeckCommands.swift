import SwiftUI

public struct DeckCommands: Commands {
    @Binding var selectedSessionId: String?
    let sessionManager: SessionManager
    let onStart: (Session) -> Void
    let onStop: (Session) -> Void
    let onRestart: (Session) -> Void
    let onNewSession: () -> Void

    public init(
        selectedSessionId: Binding<String?>,
        sessionManager: SessionManager,
        onStart: @escaping (Session) -> Void,
        onStop: @escaping (Session) -> Void,
        onRestart: @escaping (Session) -> Void,
        onNewSession: @escaping () -> Void
    ) {
        self._selectedSessionId = selectedSessionId
        self.sessionManager = sessionManager
        self.onStart = onStart
        self.onStop = onStop
        self.onRestart = onRestart
        self.onNewSession = onNewSession
    }

    public var body: some Commands {
        // Session menu
        CommandMenu("Session") {
            Button("New Session") {
                onNewSession()
            }
            .keyboardShortcut("n")

            Divider()

            if let session = selectedSession {
                if session.state == .stopped {
                    Button("Start") {
                        onStart(session)
                    }
                    .keyboardShortcut("r")
                }

                if session.state == .running || session.state == .degraded {
                    Button("Restart") {
                        onRestart(session)
                    }
                    .keyboardShortcut("r")

                    Button("Stop") {
                        onStop(session)
                    }
                    .keyboardShortcut("w")
                }
            }

            Divider()

            // Cmd+1 through Cmd+9 to jump to sessions
            ForEach(Array(sessionManager.sessions.prefix(9).enumerated()), id: \.offset) { index, session in
                Button("\(session.config.icon) \(session.displayName)") {
                    selectedSessionId = session.id
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
        }

        // Navigation
        CommandGroup(after: .toolbar) {
            Button("Previous Session") {
                selectPreviousSession()
            }
            .keyboardShortcut("[")

            Button("Next Session") {
                selectNextSession()
            }
            .keyboardShortcut("]")
        }
    }

    private var selectedSession: Session? {
        guard let id = selectedSessionId else { return nil }
        return sessionManager.session(byId: id)
    }

    private func selectPreviousSession() {
        guard !sessionManager.sessions.isEmpty else { return }
        guard let currentId = selectedSessionId,
              let currentIndex = sessionManager.sessions.firstIndex(where: { $0.id == currentId }) else {
            selectedSessionId = sessionManager.sessions.last?.id
            return
        }
        let newIndex = currentIndex > 0 ? currentIndex - 1 : sessionManager.sessions.count - 1
        selectedSessionId = sessionManager.sessions[newIndex].id
    }

    private func selectNextSession() {
        guard !sessionManager.sessions.isEmpty else { return }
        guard let currentId = selectedSessionId,
              let currentIndex = sessionManager.sessions.firstIndex(where: { $0.id == currentId }) else {
            selectedSessionId = sessionManager.sessions.first?.id
            return
        }
        let newIndex = (currentIndex + 1) % sessionManager.sessions.count
        selectedSessionId = sessionManager.sessions[newIndex].id
    }
}
