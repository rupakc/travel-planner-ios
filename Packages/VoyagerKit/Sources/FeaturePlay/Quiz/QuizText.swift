import Foundation
import L10n
import Networking
import SharedUI
import VoyagerData
import VoyagerModel

/// Localised bits of a quiz question (web `quizText.js`): prompts are catalogue templates; country names are written in the
/// app language from their ISO code; capitals, landmarks and dishes ship in English.
enum QuizText {
    static func regionName(code: String?, fallback: String?) -> String {
        guard let code, code.count == 2 else { return fallback ?? "" }
        let upper = code.uppercased()
        let name = LanguageController.current.intlLocale.localizedString(forRegionCode: upper)
        guard let name, name != upper else { return fallback ?? upper }
        return name
    }

    static func optionLabel(_ option: PlayOption) -> String {
        option.code == nil ? option.label : regionName(code: option.code, fallback: option.label)
    }

    /// The question text; nil for a template this app version does not know (the view says "update the app").
    static func prompt(_ question: PlayQuestion) -> String? {
        let prompt = question.prompt
        switch question.template {
        case .flag:
            return L10n.text(K.play.quiz.prompt.flag)
        case .capitalOf:
            let country = regionName(code: prompt["code"].string, fallback: prompt["country"].string)
            return L10n.text(K.play.quiz.prompt.capital_of, ["country": country])
        case .countryOfCapital:
            return L10n.text(K.play.quiz.prompt.country_of_capital, ["capital": prompt["capital"].string ?? ""])
        case .landmarkCountry:
            return L10n.text(K.play.quiz.prompt.landmark_country, ["landmark": prompt["landmark"].string ?? ""])
        case .dishCountry:
            return L10n.text(K.play.quiz.prompt.dish_country, ["dish": prompt["dish"].string ?? ""])
        case .unknown:
            return nil
        }
    }

    /// The flag emoji of a `flag` question (the server sends it ready to show).
    static func flag(_ question: PlayQuestion) -> String? {
        question.template == .flag ? question.prompt["flag"].string : nil
    }

    static func packName(_ id: String?) -> String {
        switch id {
        case "flags": L10n.text(K.play.pack.flags)
        case "capitals": L10n.text(K.play.pack.capitals)
        case "landmarks": L10n.text(K.play.pack.landmarks)
        case "cuisine": L10n.text(K.play.pack.cuisine)
        case .some(let other): other.replacingOccurrences(of: "_", with: " ").capitalized
        case nil: ""
        }
    }

    /// What a history row or result calls a finished game.
    static func modeName(mode: String, pack: String?) -> String {
        switch mode {
        case "daily": L10n.text(K.play.daily.title)
        case "challenge": L10n.text(K.play.challenge.title)
        case "h2h": L10n.text(K.play.h2h.title)
        default: pack.map(packName) ?? mode.capitalized
        }
    }
}

/// The user-facing text of a Play failure: the translated copy for a code the contract names, else the backend's own text
/// (a 429 says when to retry), else the generic copy.
enum PlayMessage {
    static func text(for error: any Error) -> String {
        guard let api = error as? APIError else { return ErrorCopy.message(kind: .other, detail: nil) }
        if let failure = PlayFailure.from(api) {
            switch failure {
            case .alreadyDone: return L10n.text(K.play.quiz.alreadyDone)
            case .sessionExpired, .sessionNotFound: return L10n.text(K.play.quiz.expired)
            case .gameHidden: return L10n.text(K.playYou.hidden.note)
            case .limitReached: return L10n.text(K.social.errors.limit_reached)
            case .matchExpired: return L10n.text(K.play.quiz.expired)
            case .matchNotFound: return L10n.text(K.play.h2h.missing)
            case .profileNotFound: return L10n.text(K.social.errors.profile_not_found)
            case .profileRequired: return L10n.text(K.social.errors.profile_required)
            case .restricted: return L10n.text(K.social.errors.restricted)
            default: break
            }
        }
        return ErrorCopy.message(kind: api.presentationKind, detail: api.userFacingDetail)
    }
}
