import Foundation

public struct URLSchemeHandler {
    public enum Action: Sendable {
        case start(sessionName: String)
        case stop(sessionName: String)
        case open(sessionName: String)
        case unknown
    }

    public static func parse(url: URL) -> Action {
        guard url.scheme == "deck" else { return .unknown }

        let host = url.host ?? ""
        let pathComponent = url.pathComponents.dropFirst().first ?? ""

        // deck://start/<session-name>
        // deck://stop/<session-name>
        // deck://open/<session-name>
        let sessionName = pathComponent.isEmpty ? "" : pathComponent

        guard !sessionName.isEmpty else { return .unknown }

        switch host {
        case "start": return .start(sessionName: sessionName)
        case "stop": return .stop(sessionName: sessionName)
        case "open": return .open(sessionName: sessionName)
        default: return .unknown
        }
    }
}
