import Foundation
import VoyagerModel

public enum ErrorMapping {
    /// Maps a non-2xx response. `detail` may be a string, a list (422) or `{code, message}`.
    /// A 429 keeps the backend string as-is and reads `Retry-After` (seconds).
    public static func map(status: Int, body: Data?, headers: [String: String]) -> APIError {
        let json = body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } ?? .null
        let (detail, code) = parseDetail(json["detail"])
        switch status {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden(detail)
        case 404:
            return .notFound(detail)
        case 429:
            let retry = header("Retry-After", in: headers).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return .rateLimited(message: detail ?? "", retryAfter: retry.flatMap { $0 >= 0 ? $0 : nil })
        case 500...:
            return .server(status: status, detail: detail, code: code ?? json["error_code"].string)
        default:
            return .client(status: status, detail: detail, code: code, body: json)
        }
    }

    public static func map(response: HTTPURLResponse, body: Data?) -> APIError {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return map(status: response.statusCode, body: body, headers: headers)
    }

    private static func parseDetail(_ detail: JSONValue) -> (String?, String?) {
        switch detail {
        case .string(let text):
            return (text.isEmpty ? nil : text, nil)
        case .object:
            let message = detail["message"].string
            return (message?.isEmpty == false ? message : nil, detail["code"].string)
        default:
            return (nil, nil)
        }
    }

    private static func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
