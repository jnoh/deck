import SwiftUI
import AppKit
import DeckLib

@main
struct DeckApp: App {
    @State private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            MainView(coordinator: coordinator)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            DeckCommands(
                selectedSessionId: $coordinator.selectedSessionId,
                sessionManager: coordinator.sessionManager,
                onStart: { coordinator.startSession($0) },
                onStop: { coordinator.stopSession($0) },
                onRestart: { coordinator.restartSession($0) },
                onNewSession: { createNewSession() }
            )
        }

        MenuBarExtra("Deck", systemImage: menuBarIcon) {
            MenuBarView(
                sessionManager: coordinator.sessionManager,
                onSelectSession: { sessionId in
                    coordinator.selectedSessionId = sessionId
                    NSApplication.shared.activate(ignoringOtherApps: true)
                },
                onStartAll: { coordinator.startAllSessions() },
                onStopAll: { coordinator.stopAllSessions() }
            )
        }
    }

    private func createNewSession() {
        let configDir = ConfigLoader.defaultConfigDirectory
        try? ConfigLoader.ensureConfigDirectory(at: configDir)
        NSWorkspace.shared.open(configDir)
    }

    private var menuBarIcon: String {
        let hasRunning = !coordinator.sessionManager.runningSessions.isEmpty
        let hasDegraded = !coordinator.sessionManager.degradedSessions.isEmpty

        if hasDegraded {
            return "exclamationmark.terminal"
        } else if hasRunning {
            return "terminal.fill"
        } else {
            return "terminal"
        }
    }
}
