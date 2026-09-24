import SwiftUI
import PAComposition
import PAKernel

@main
struct PersonalAgentApp: App {
    @StateObject private var sessionHolder = SessionHolder()

    var body: some Scene {
        WindowGroup {
            Group {
                if let session = sessionHolder.session {
                    RootView(session: session)
                        .onOpenURL { url in
                            let isAccessing = url.startAccessingSecurityScopedResource()
                            Task {
                                defer {
                                    if isAccessing {
                                        url.stopAccessingSecurityScopedResource()
                                    }
                                }
                                await session.importModel(from: url)
                            }
                        }
                } else if let initializationError = sessionHolder.initializationError {
                    VStack(spacing: 12) {
                        Text("Initialization failed: \(initializationError)")
                            .font(.callout)
                            .foregroundStyle(.red)
                        Button("Retry") {
                            sessionHolder.reload()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    ProgressView("Initializing Agent...")
                }
            }
            .task {
                await sessionHolder.load()
            }
        }
    }
}

@MainActor
private final class SessionHolder: ObservableObject {
    @Published var session: KernelSession?
    @Published var initializationError: String?

    func load() async {
        guard session == nil else { return }
        do {
            let composition = try await M8CompositionRoot()
            let agentSession = composition.session
            let state = await agentSession.currentState()
            let newSession = KernelSession(composition: composition, state: state)
            await newSession.refresh()
            self.session = newSession
            self.initializationError = nil
        } catch {
            self.initializationError = error.localizedDescription
        }
    }

    func reload() {
        self.session = nil
        self.initializationError = nil
        Task {
            await load()
        }
    }
}
