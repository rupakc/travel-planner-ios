import Foundation
import L10n
import Networking
import VoyagerData
import VoyagerModel

/// Country names in the app language from the ISO alpha-2 codes the contract uses (`home_country`, `countries`).
enum CountryNames {
    static func name(_ code: String) -> String {
        let locale = LanguageController.current.intlLocale
        return locale.localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
    }

    /// Every ISO country, sorted by its name in the app language.
    static func all() -> [(code: String, name: String)] {
        let locale = LanguageController.current.intlLocale
        return Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .compactMap { code in locale.localizedString(forRegionCode: code).map { (code: code, name: $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Names of the game badges shown on a public profile (`game:badges.<id>.name`); an id this build does not know shows as
/// plain words.
enum BadgeNames {
    static let known: Set<String> = [
        "verified", "first_steps", "traveller", "first_trip", "trip_ready", "ready_regular", "smart_planner", "on_the_road",
        "road_warrior", "local_explorer", "local_legend", "countries_3", "countries_10", "countries_30", "continents_3",
        "continents_6", "storyteller", "memory_keeper", "deal_hunter", "deal_hunter_silver", "deal_hunter_gold", "bullseye",
        "saver_50", "saver_200", "saver_1000", "quiz_regular", "quiz_devoted", "quiz_ace", "quiz_master", "inspirer", "muse",
        "helpful_voice", "h2h_rival", "h2h_veteran", "challenge_explorer", "challenge_regular",
    ]

    static func name(_ id: String) -> String {
        if known.contains(id) { return L10n.text(LKey("game:badges.\(id).name", placeholders: [], plural: false)) }
        return id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// The handle as the contract stores it: lower-case, 3 to 20 letters, digits or underscores.
enum HandleRules {
    static let minLength = 3
    static let maxLength = 20

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "").lowercased()
    }

    static func isValid(_ handle: String) -> Bool {
        (minLength...maxLength).contains(handle.count)
            && handle.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII && (scalar.properties.isAlphabetic || (48...57).contains(scalar.value) || scalar == "_")
            }
    }
}

/// The user-facing text of a social failure: the translated message for a code the contract names, else the backend's own
/// text (a 429 says when to retry), else the generic copy.
enum SocialMessage {
    static func text(for error: any Error, fallback: LKey = K.social.feed.error) -> String {
        guard let api = error as? APIError else { return L10n.text(fallback) }
        if let failure = SocialFailure.from(api), let key = key(for: failure) { return L10n.text(key) }
        switch api {
        case .rateLimited, .network, .unauthorized: return ErrorCopy.message(kind: api.presentationKind, detail: api.userFacingDetail)
        default: return L10n.text(fallback)
        }
    }

    static func key(for failure: SocialFailure) -> LKey? {
        switch failure {
        case .handleTaken: K.social.errors.handle_taken
        case .handleInvalid: K.social.errors.handle_invalid
        case .handleReserved: K.social.errors.handle_reserved
        case .handleRateLimited: K.social.errors.handle_rate_limited
        case .countryInvalid: K.social.errors.country_invalid
        case .contentRejected: K.social.errors.content_rejected
        case .profileRequired: K.social.errors.profile_required
        case .emailUnverified: K.social.errors.email_unverified
        case .restricted: K.social.errors.restricted
        case .profileNotFound: K.social.errors.profile_not_found
        case .requestNotFound: nil
        case .ideaNotFound: K.social.errors.idea_not_found
        case .commentNotFound: K.social.errors.comment_not_found
        case .cannotFollowSelf: K.social.errors.cannot_follow_self
        case .cannotBlockSelf: K.social.errors.cannot_block_self
        case .limitReached: K.social.errors.limit_reached
        case .notFound: K.social.errors.not_found
        case .ideaUnavailable: K.social.errors.idea_unavailable
        default: nil
        }
    }
}
