import Foundation
import L10n
import VoyagerModel

/// What the drop card says for one `data.drop`: "Caught a drop of $46.00 (9%)", the two observed prices, the
/// target-hit variant, and (only when the game is visible) the notification's own XP and badges (plan ruling R4: the
/// app shows the server's award, never a sum of its own).
struct DropMomentContent: Equatable {
    var heading: String
    var amountText: String
    var percentText: String
    var spoken: String
    var fromText: String?
    var toText: String?
    var xpText: String?
    var badgeTexts: [String]
    var note: String
    var watchTitle: String?
    var targetHit: Bool

    init(drop: DropData, game: GameDelta?, showsGame: Bool, watchTitle: String? = nil) {
        let code = drop.currency ?? "USD"
        targetHit = drop.targetHit
        heading = L10n.text(drop.targetHit ? K.dropMoment.titleTarget : K.dropMoment.title)
        let amount = Fmt.currency(drop.amount, code: code)
        let percent = drop.pct.map { Self.percent($0) } ?? ""
        amountText = "−" + amount
        percentText = percent.isEmpty ? "" : "−" + percent
        spoken = L10n.text(K.dropMoment.caught, ["amount": amount, "percent": percent.isEmpty ? "0%" : percent])
        fromText = drop.from.map { Fmt.currency($0, code: code) }
        toText = drop.to.map { Fmt.currency($0, code: code) }
        note = L10n.text(K.dropMoment.note)
        self.watchTitle = watchTitle?.isEmpty == false ? watchTitle : nil
        if showsGame, let game {
            let xp = game.awardedPoints
            xpText = xp > 0 ? L10n.text(K.dropMoment.xp, ["xp": String(xp)]) : nil
            badgeTexts = game.badges.map { L10n.text(K.dropMoment.badge, ["name": Self.badgeName($0.id)]) }
        } else {
            xpText = nil
            badgeTexts = []
        }
    }

    /// "12%" in the app language from the server's whole-number-with-one-decimal share (12.4 means 12.4 %).
    static func percent(_ pct: Double) -> String {
        let locale = LanguageController.current.intlLocale
        return (abs(pct) / 100).formatted(.percent.locale(locale).precision(.fractionLength(0)))
    }

    /// The catalogue name of a badge (`game:badges.<id>.name`); an id this build does not know shows as itself.
    static func badgeName(_ id: String) -> String {
        let key = LKey("game:badges.\(id).name", placeholders: [], plural: false)
        let name = L10n.text(key)
        return name == "name" ? id : name
    }
}
