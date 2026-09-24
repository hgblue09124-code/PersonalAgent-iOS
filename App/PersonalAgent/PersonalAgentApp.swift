import SwiftUI
import PAComposition
import PAKernel

@main
struct PersonalAgentApp: App {
    @State private var session: KernelSession?
    @State private var initializationError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let session {
                    RootView(session: session)
                        .onOpenURL { url in
                            Task {
                                await session.importModel(from: url)
                            }
                        }
                } else if let initializationError {
                    VStack(spacing: 12) {
                        Text("Initialization failed: \(initializationError)")
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await initialize()
                            }
                        }
                    }
                    .padding()
                } else {
                    ProgressView("Starting kernel")
                        .task {
                            await initialize()
                        }
                }
            }
            .dynamicTypeSize(.xSmall ... .accessibility3)
        }
    }

    private func initialize() async {
        initializationError = nil
        do {
            let root = try await M8CompositionRoot()
            let state = await root.session.currentState()
            session = KernelSession(composition: root, state: state)
        } catch {
            initializationError = String(describing: error)
        }
    }
}
