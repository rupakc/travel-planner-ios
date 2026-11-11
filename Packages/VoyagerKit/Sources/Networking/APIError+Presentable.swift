import VoyagerModel

extension APIError: ErrorPresentable {
    public var presentationKind: ErrorPresentationKind {
        switch self {
        case .unauthorized: .unauthorized
        case .rateLimited: .rateLimited
        case .network, .interrupted: .network
        case .server: .server
        case .forbidden, .notFound, .client, .decoding, .notConfigured, .cancelled: .other
        }
    }
}
