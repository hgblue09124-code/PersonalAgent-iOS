import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: Role
    let content: String
    let createdAt: Date
    enum Role: String { case user, assistant, system }
    init(id: String = UUID().uuidString, role: Role, content: String, createdAt: Date = Date()) {
        self.id = id; self.role = role; self.content = content; self.createdAt = createdAt
    }
}
