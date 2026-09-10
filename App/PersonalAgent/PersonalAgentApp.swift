import SwiftUI
import PAComposition
import PAKernel

@main
struct PersonalAgentApp: App {
    @State private var session: KernelSession?

    var body: some Scene {
        WindowGroup {
            Group {
                if let session {
                    RootView(session: session)
                } else {
                    ProgressView("Starting kernel")
                        .task {
                            guard let root = try? await M3CompositionRoot() else { return }
                            let state = await root.runtime.currentState()
                            session = KernelSession(composition: root, state: state)
                        }
                }
            }
            .dynamicTypeSize(.xSmall ... .accessibility3)
        }
    }
}
