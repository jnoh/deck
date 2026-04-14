import SwiftUI
import DeckLib

struct MainView: View {
    @Bindable var coordinator: AppCoordinator
    @State private var didSetup = false
    @State private var sidebarWidth: CGFloat = 260

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SidebarView(
                sessionManager: coordinator.sessionManager,
                selectedSessionId: $coordinator.selectedSessionId,
                onCreateSession: { blueprint, name, dir in
                    coordinator.createAndStartSession(from: blueprint, name: name, workingDir: dir)
                }
            )
            .frame(width: sidebarWidth)

            // Draggable divider
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let new = sidebarWidth + value.translation.width
                            sidebarWidth = max(200, min(400, new))
                        }
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }

            // Detail
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: coordinator.selectedSessionId) { _, newId in
            if let id = newId, let session = coordinator.sessionManager.session(byId: id) {
                session.status.clearAttention()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            guard !didSetup else { return }
            didSetup = true

            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            coordinator.setup()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = NSApp.windows.first(where: { $0.isKeyWindow || $0.title == "Deck" }) {
                    let screen = window.screen ?? NSScreen.main!
                    let w: CGFloat = 1100
                    let h: CGFloat = 700
                    let x = screen.visibleFrame.origin.x + (screen.visibleFrame.width - w) / 2
                    let y = screen.visibleFrame.origin.y + (screen.visibleFrame.height - h) / 2
                    window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: false)
                }
            }
        }
        .onOpenURL { url in
            handleURL(url)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        ZStack {
            ForEach(coordinator.sessionManager.sessions.filter {
                $0.state == .running || $0.state == .degraded || $0.state == .starting
            }) { session in
                TerminalSessionView(session: session) { exitCode in
                    coordinator.handleProcessExit(session: session, exitCode: exitCode)
                }
                .id(session.id)
                .opacity(session.id == coordinator.selectedSessionId ? 1 : 0)
                .allowsHitTesting(session.id == coordinator.selectedSessionId)
            }

            if let sessionId = coordinator.selectedSessionId,
               let session = coordinator.sessionManager.session(byId: sessionId) {
                if session.state == .stopped {
                    stoppedSessionView(session)
                }
            } else if coordinator.sessionManager.sessions.filter({
                $0.state == .running || $0.state == .degraded || $0.state == .starting
            }).isEmpty {
                emptyDetailView
            }
        }
    }

    private func stoppedSessionView(_ session: Session) -> some View {
        VStack(spacing: 16) {
            Text(session.config.icon)
                .font(.system(size: 48))
            Text(session.displayName)
                .font(.title2)
                .fontWeight(.medium)
            Text(session.state.rawValue.capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if session.state == .stopped {
                Button("Start Session") {
                    coordinator.startSession(session)
                }
                .accessibilityIdentifier("startSessionButton")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Session Selected")
                .font(.title2)
                .foregroundStyle(.secondary)
            if coordinator.sessionManager.blueprints.isEmpty {
                Text("Add .deck packages to ~/.deck/apps/")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Click + to create a session")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleURL(_ url: URL) {
        let action = URLSchemeHandler.parse(url: url)
        switch action {
        case .start(let name):
            if let blueprint = coordinator.sessionManager.blueprint(named: name) {
                coordinator.createAndStartSession(from: blueprint)
            }
        case .stop(let name):
            for session in coordinator.sessionManager.sessions where session.config.name == name {
                coordinator.stopSession(session)
            }
        case .open(let name):
            if let session = coordinator.sessionManager.sessions.first(where: { $0.config.name == name }) {
                coordinator.selectedSessionId = session.id
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        case .unknown:
            break
        }
    }
}
