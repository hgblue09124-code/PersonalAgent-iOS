import XCTest
import PASkills

final class SkillChatInputNormalizationTests: XCTestCase {
    func testPreservesFileCreateCommandAfterPoliteLeadIns() {
        let cases: [(String, String)] = [
            ("Hãy tạo file note.md with content: hello", "tạo file note.md with content: hello"),
            ("Vui lòng tạo tệp note.txt with content: hello", "tạo tệp note.txt with content: hello"),
            ("Giúp tôi create file notes.json with content: {}", "create file notes.json with content: {}"),
            ("Anh hãy write file draft.md with content: hi", "write file draft.md with content: hi")
        ]

        for (input, expected) in cases {
            XCTAssertEqual(SkillRuntime.chatInputText(from: input), expected, "Input: \(input)")
        }
    }

    func testOrdinaryColonPromptStillExtractsPayload() {
        XCTAssertEqual(
            SkillRuntime.chatInputText(from: "Question: explain this"),
            "explain this"
        )
    }
}
