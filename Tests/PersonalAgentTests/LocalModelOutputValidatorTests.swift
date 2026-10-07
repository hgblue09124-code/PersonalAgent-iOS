import Testing
@testable import PAProvidersLocal

@Suite("Local Model Output Quality")
struct LocalModelOutputValidatorTests {
    @Test func repeatedTailIsCollapsed() {
        let input = "I am your personal agent and I can help you. I am your personal agent and I can help you."
        #expect(LocalModelOutputValidator.sanitize(text: input) == "I am your personal agent and I can help you.")
    }

    @Test func tripleRepeatedTailIsCollapsedToOne() {
        let block = "The Agent is ready to help with your request."
        let input = "\(block) \(block) \(block)"
        #expect(LocalModelOutputValidator.sanitize(text: input) == block)
    }

    @Test func normalResponseIsPreserved() {
        let input = "I found the model and imported it successfully."
        #expect(LocalModelOutputValidator.sanitize(text: input) == input)
    }

    @Test func intentionalShortRepetitionIsPreserved() {
        let input = "very very good"
        #expect(LocalModelOutputValidator.sanitize(text: input) == input)
    }
}
