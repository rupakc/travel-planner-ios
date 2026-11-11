import Foundation

/// What the build says about the backend and the app (Info.plist keys filled from the xcconfig).
public struct AppBuildConfig: Sendable, Equatable {
    /// `VOYAGER_BASE_URL`; nil when the build left it empty (Release before the owner sets it).
    public var baseURL: URL?
    /// `VOYAGER_TRUSTED_HOSTS` (space-separated), lowercased.
    public var trustedHosts: Set<String>
    public var appVersion: String
    public var isDebug: Bool

    public init(baseURL: URL?, trustedHosts: Set<String>, appVersion: String, isDebug: Bool) {
        self.baseURL = baseURL
        self.trustedHosts = Set(trustedHosts.map { $0.lowercased() })
        self.appVersion = appVersion
        self.isDebug = isDebug
    }

    public static let baseURLKey = "VoyagerBaseURL"
    public static let trustedHostsKey = "VoyagerTrustedHosts"

    /// Whether this code was compiled with `DEBUG` (Xcode Debug configuration).
    #if DEBUG
    public static let compiledDebug = true
    #else
    public static let compiledDebug = false
    #endif

    /// Reads `VoyagerBaseURL`, `VoyagerTrustedHosts` and `CFBundleShortVersionString` from `bundle`.
    /// In Debug, a `-VoyagerBaseURL <url>` launch argument (UI tests) overrides the base URL.
    public static func fromBundle(
        _ bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isDebug: Bool = compiledDebug
    ) -> AppBuildConfig {
        func string(_ key: String) -> String? {
            (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var baseURL = url(string(baseURLKey))
        if isDebug, let index = arguments.firstIndex(of: "-\(baseURLKey)"), arguments.indices.contains(index + 1),
            let override = url(arguments[index + 1]) {
            baseURL = override
        }
        let hosts = (string(trustedHostsKey) ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
        return AppBuildConfig(
            baseURL: baseURL,
            trustedHosts: Set(hosts),
            appVersion: string("CFBundleShortVersionString").flatMap { $0.isEmpty ? nil : $0 } ?? "0.0.0",
            isDebug: isDebug)
    }

    /// An absolute http(s) URL, or nil (empty, unexpanded `$(...)`, or junk).
    static func url(_ text: String?) -> URL? {
        guard let text, !text.isEmpty, !text.contains("$("), let url = URL(string: text),
            let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host != nil
        else { return nil }
        return url
    }
}
