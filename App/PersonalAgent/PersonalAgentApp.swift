import SwiftUI
import PAComposition

@main
struct PersonalAgentApp: App {
    private let composition = M0CompositionRoot()

    var body: some Scene {
        WindowGroup {
            RootView(composition: composition)
                .dynamicTypeSize(.xSmall ... .accessibility3)
        }
    }
}
