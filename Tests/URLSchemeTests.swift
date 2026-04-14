import Testing
import Foundation
@testable import DeckLib

@Suite("URL Scheme Handler")
struct URLSchemeTests {

    @Test func parsesStartURL() {
        let url = URL(string: "deck://start/my-session")!
        let action = URLSchemeHandler.parse(url: url)
        if case .start(let name) = action {
            #expect(name == "my-session")
        } else {
            #expect(Bool(false), "Expected .start action")
        }
    }

    @Test func parsesStopURL() {
        let url = URL(string: "deck://stop/my-session")!
        let action = URLSchemeHandler.parse(url: url)
        if case .stop(let name) = action {
            #expect(name == "my-session")
        } else {
            #expect(Bool(false), "Expected .stop action")
        }
    }

    @Test func parsesOpenURL() {
        let url = URL(string: "deck://open/my-session")!
        let action = URLSchemeHandler.parse(url: url)
        if case .open(let name) = action {
            #expect(name == "my-session")
        } else {
            #expect(Bool(false), "Expected .open action")
        }
    }

    @Test func unknownActionReturnsUnknown() {
        let url = URL(string: "deck://restart/my-session")!
        let action = URLSchemeHandler.parse(url: url)
        if case .unknown = action {
            // Expected
        } else {
            #expect(Bool(false), "Expected .unknown action")
        }
    }

    @Test func missingSessionNameReturnsUnknown() {
        let url = URL(string: "deck://start")!
        let action = URLSchemeHandler.parse(url: url)
        if case .unknown = action {
            // Expected
        } else {
            #expect(Bool(false), "Expected .unknown for missing session name")
        }
    }

    @Test func wrongSchemeReturnsUnknown() {
        let url = URL(string: "http://start/my-session")!
        let action = URLSchemeHandler.parse(url: url)
        if case .unknown = action {
            // Expected
        } else {
            #expect(Bool(false), "Expected .unknown for wrong scheme")
        }
    }

    @Test func handlesHyphenatedSessionNames() {
        let url = URL(string: "deck://start/my-long-session-name")!
        let action = URLSchemeHandler.parse(url: url)
        if case .start(let name) = action {
            #expect(name == "my-long-session-name")
        } else {
            #expect(Bool(false), "Expected .start action")
        }
    }
}
