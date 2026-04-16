import SwiftUI

public struct SidebarView: View {
    @Bindable var sessionManager: SessionManager
    @Binding var selectedSessionId: String?
    var onCreateSession: ((SessionConfig, String, [String: String]) -> Void)?

    @State private var renamingSession: Session?
    @State private var renameText: String = ""
    @State private var blueprintForSheet: SessionConfig?

    public init(
        sessionManager: SessionManager,
        selectedSessionId: Binding<String?>,
        onCreateSession: ((SessionConfig, String, [String: String]) -> Void)? = nil
    ) {
        self.sessionManager = sessionManager
        self._selectedSessionId = selectedSessionId
        self.onCreateSession = onCreateSession
    }

    public var body: some View {
        List(selection: $selectedSessionId) {
            if sessionManager.sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "terminal")
                } description: {
                    Text("Click + to create a session.")
                }
            } else {
                ForEach(sessionManager.sessions) { session in
                    sessionRow(session)
                }
                .onMove { source, destination in
                    sessionManager.moveSessions(from: source, to: destination)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if sessionManager.blueprints.isEmpty {
                        Text("No apps found")
                        Text("Add .deck packages to ~/.deck/apps/")
                    } else {
                        ForEach(sessionManager.blueprints, id: \.name) { blueprint in
                            Button {
                                blueprintForSheet = blueprint
                            } label: {
                                Label(
                                    "\(blueprint.icon) \(blueprint.name)",
                                    systemImage: blueprint.type == .local ? "terminal" : "network"
                                )
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Session")
            }
        }
        .sheet(item: $blueprintForSheet) { blueprint in
            CreateSessionSheet(blueprint: blueprint) { name, params in
                onCreateSession?(blueprint, name, params)
            }
        }
        .alert("Rename Session", isPresented: .init(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    renamingSession?.displayName = trimmed
                }
                renamingSession = nil
            }
            Button("Cancel", role: .cancel) {
                renamingSession = nil
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        SessionRowView(session: session)
            .tag(session.id)
            .contextMenu { sessionContextMenu(session) }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: Session) -> some View {
        Button("Rename") {
            renameText = session.displayName
            renamingSession = session
        }

        if session.state != .stopped {
            Button("Force Kill", role: .destructive) {
                NotificationCenter.default.post(
                    name: .deckSessionAction,
                    object: nil,
                    userInfo: ["action": "force-kill", "session": session.id]
                )
            }
        }

        Button("Close", role: .destructive) {
            NotificationCenter.default.post(
                name: .deckSessionAction,
                object: nil,
                userInfo: ["action": "remove", "session": session.id]
            )
        }
    }
}

// MARK: - Make SessionConfig identifiable for .sheet(item:)

extension SessionConfig: Identifiable {
    public var id: String { name }
}

// MARK: - Notification for session actions

public extension Notification.Name {
    static let deckSessionAction = Notification.Name("deckSessionAction")
}
