import Foundation
import Networking
import VoyagerModel

/// Re-emits `source` through `transform` without touching the main actor; cancelling the output cancels the source.
func mapStream<T: Sendable>(
    _ source: AsyncThrowingStream<JSONValue, Error>, _ transform: @escaping @Sendable (JSONValue) -> T
) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await value in source { continuation.yield(transform(value)) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

func failedStream<T: Sendable>(_ error: Error) -> AsyncThrowingStream<T, Error> {
    AsyncThrowingStream { $0.finish(throwing: error) }
}

/// `POST /api/search`. Never retries: an interrupted stream throws `APIError.interrupted` or just ends without
/// `.done`, and Results decides on the single retry.
public struct LiveSearchRepository: SearchRepository {
    private let sse: SSEClient
    private let locale: @Sendable () -> AppLanguage
    public init(sse: SSEClient, locale: @escaping @Sendable () -> AppLanguage) {
        self.sse = sse
        self.locale = locale
    }

    public func stream(_ request: TravelSearchRequest) -> AsyncThrowingStream<SearchStreamEvent, Error> {
        do {
            let body = try RequestBody.withLocale(request, locale())
            return mapStream(
                sse.stream(path: Endpoints.searchPath, telemetryName: "/api/search", body: body, auth: Endpoints.searchAuth),
                SearchStreamEvent.init(json:))
        } catch {
            return failedStream(APIError.decoding)
        }
    }
}
