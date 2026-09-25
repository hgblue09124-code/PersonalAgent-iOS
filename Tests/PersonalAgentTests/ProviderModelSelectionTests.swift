import Foundation
import Testing
import PAFoundation
@testable import PAProviders

@Suite("Provider model selection")
struct ProviderModelSelectionTests {
    @Test("selection persists and restores")
    func selectionPersistsAndRestores() async {
        let suiteName = "ProviderModelSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ProviderModelSelectionStore(
            initialModel: ModelID(rawValue: "gpt-5.6-luna"),
            suiteName: suiteName,
            persistenceKey: "selected"
        )
        #expect(await first.selectedModel() == ModelID(rawValue: "gpt-5.6-luna"))

        await first.select(ModelID(rawValue: "gpt-5.6-terra"))

        let restored = ProviderModelSelectionStore(
            initialModel: ModelID(rawValue: "fallback"),
            suiteName: suiteName,
            persistenceKey: "selected"
        )
        #expect(await restored.selectedModel() == ModelID(rawValue: "gpt-5.6-terra"))
    }

    @Test("selection can be cleared")
    func selectionCanBeCleared() async {
        let suiteName = "ProviderModelSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProviderModelSelectionStore(
            initialModel: ModelID(rawValue: "gpt-5.6-luna"),
            defaults: defaults,
            persistenceKey: "selected"
        )

        await store.select(nil)
        #expect(await store.selectedModel() == nil)
        #expect(defaults.string(forKey: "selected") == nil)
    }
}
