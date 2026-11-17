import Foundation
import L10n
import VoyagerModel

/// The wording of a head-to-head match (web `H2HSection` / `H2HMatch`). The opponent's score exists only once both
/// players are done, and the server already hides it until then; the app never shows one earlier either.
enum H2HText {
    static func state(_ state: H2HState) -> String {
        switch state {
        case .waitingYou: L10n.text(K.play.h2h.state_waiting_you)
        case .done: L10n.text(K.play.h2h.state_done)
        case .declined: L10n.text(K.play.h2h.state_declined)
        case .expired: L10n.text(K.play.h2h.state_expired)
        // An unknown state reads as a plain "waiting" row without actions.
        case .waitingThem, .unknown: L10n.text(K.play.h2h.state_waiting_them)
        }
    }

    /// "4 to 3", only for a finished match.
    static func score(_ match: H2HMatch) -> String? {
        guard match.state == .done, let you = match.you, let them = match.them else { return nil }
        return L10n.text(K.play.h2h.score, ["you": String(you), "them": String(them)])
    }

    static func winner(_ winner: H2HWinner?) -> String {
        switch winner ?? .draw {
        case .you: L10n.text(K.play.h2h.winner_you)
        case .them: L10n.text(K.play.h2h.winner_them)
        case .draw: L10n.text(K.play.h2h.winner_draw)
        }
    }
}
