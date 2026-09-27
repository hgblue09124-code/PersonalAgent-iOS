public struct SchemaDocument: Hashable, Sendable, Codable {
    public let identifier: String
    public let rawJSON: String
    public init(identifier: String, rawJSON: String = "{}") {
        self.identifier = identifier
        self.rawJSON = rawJSON
    }
}
