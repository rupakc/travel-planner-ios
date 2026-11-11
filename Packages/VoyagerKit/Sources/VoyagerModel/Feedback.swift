import Foundation

/// `POST /api/feedback`: rating 1-5; category bug, feature_request, general or praise; message at most 500 characters.
public struct FeedbackSubmission: Codable, Sendable, Hashable {
    public var page: String
    public var rating: Int
    public var category: String
    public var message: String?
    public var metadata: JSONValue?

    public init(
        page: String,
        rating: Int,
        category: String,
        message: String? = nil,
        metadata: JSONValue? = nil
    ) {
        self.page = page
        self.rating = rating
        self.category = category
        self.message = message
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case page
        case rating
        case category
        case message
        case metadata
    }

    public init(from decoder: any Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        page = try box.reqString(.page)
        rating = try box.reqInt(.rating)
        category = try box.reqString(.category)
        message = box.lString(.message)
        metadata = box.lAny(JSONValue.self, .metadata)
    }
}
