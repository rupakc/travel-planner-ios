import Foundation
import Networking
import VoyagerModel

/// `POST /api/chat` (signed-in users only). Never retries.
public struct LiveChatRepository: ChatRepository {
    private let sse: SSEClient
    private let locale: @Sendable () -> AppLanguage
    public init(sse: SSEClient, locale: @escaping @Sendable () -> AppLanguage) {
        self.sse = sse
        self.locale = locale
    }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        do {
            let body = try RequestBody.withLocale(request, locale())
            return mapStream(
                sse.stream(path: Endpoints.chatPath, telemetryName: "/api/chat", body: body, auth: Endpoints.chatAuth),
                ChatStreamEvent.init(json:))
        } catch {
            return failedStream(APIError.decoding)
        }
    }
}
