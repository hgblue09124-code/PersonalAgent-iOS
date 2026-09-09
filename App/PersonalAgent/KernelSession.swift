import Foundation
import SwiftUI
import PAKernel
import PAComposition
import PAArchitecture

@MainActor
final class KernelSession: ObservableObject {
    let composition: M1CompositionRoot
    @Published var state: AgentState
    @Published var goals: [Goal]
    @Published var lastError: String?

    init(composition: M1CompositionRoot, state: AgentState) {
        self.composition = composition
        self.state = state
        self.goals = []
        self.lastError = nil
    }

    var milestone: MilestoneGate { composition.milestone }

    func refresh() async {
        state = await composition.runtime.currentState()
        goals = await composition.runtime.goals()
    }

    func start() async { await run { try await composition.runtime.start() } }
    func pause() async { await run { try await composition.runtime.pause() } }
    func resume() async { await run { try await composition.runtime.resume() } }
    func stop() async { await run { try await composition.runtime.stop() } }

    func submitGoal(_ statement: String) async {
        await run {
            try await composition.runtime.submit(goal: Goal(statement: statement))
        }
    }

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
        await refresh()
    }
}
