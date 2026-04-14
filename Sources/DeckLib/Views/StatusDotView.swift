import SwiftUI

public struct StatusDotView: View {
    let state: SessionState
    @State private var isPulsing = false

    public init(state: SessionState) {
        self.state = state
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .opacity(state.isTransitional ? (isPulsing ? 0.3 : 1.0) : 1.0)
            .animation(
                state.isTransitional
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                if state.isTransitional {
                    isPulsing = true
                }
            }
            .onChange(of: state) { _, newState in
                isPulsing = newState.isTransitional
            }
    }

    private var color: Color {
        switch state {
        case .running:
            return .green
        case .degraded:
            return .yellow
        case .stopped:
            return .gray
        case .provisioning, .starting, .stopping, .deprovisioning:
            return .blue
        }
    }
}
