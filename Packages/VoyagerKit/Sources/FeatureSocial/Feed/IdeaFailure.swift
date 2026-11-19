import L10n
import Networking
import SharedUI
import VoyagerData
import VoyagerEnv
import VoyagerModel

/// Why a social call failed: the translated code when the contract has one, else the generic kind and the backend's
/// own text (a rate limit shows it as-is).
struct IdeaFailure: Error, Equatable {
    var failure: SocialFailure?
    var kind: ErrorPresentationKind
    var detail: String?
    /// The call never went out (`features.social` off, or the route turned out to be missing).
    var unavailable = false

    init(_ error: any Error) {
        if error is SocialService.Unavailable {
            self.init(failure: .socialDisabled, kind: .other, detail: nil)
            unavailable = true
        } else if let api = error as? APIError {
            self.init(failure: SocialFailure.from(api), kind: api.presentationKind, detail: api.userFacingDetail)
            unavailable = SocialFailure.isFeatureOff(api)
        } else {
            self.init(failure: nil, kind: .other, detail: nil)
        }
    }

    init(failure: SocialFailure?, kind: ErrorPresentationKind, detail: String?) {
        self.failure = failure
        self.kind = kind
        self.detail = detail
    }

    /// The profile editor can fix this.
    var needsProfile: Bool { failure == .profileRequired }

    /// The idea (or comment) is gone: removed, hidden, blocked or never there.
    var isGone: Bool {
        switch failure {
        case .ideaNotFound, .ideaUnavailable, .commentNotFound, .profileNotFound, .notFound: true
        default: false
        }
    }

    var message: String {
        switch failure {
        case .contentRejected: L10n.text(K.social.errors.content_rejected)
        case .profileRequired: L10n.text(K.social.errors.profile_required)
        case .emailUnverified: L10n.text(K.social.errors.email_unverified)
        case .restricted: L10n.text(K.social.errors.restricted)
        case .limitReached: L10n.text(K.social.errors.limit_reached)
        case .ideaUnavailable: L10n.text(K.social.errors.idea_unavailable)
        case .ideaNotFound: L10n.text(K.social.errors.idea_not_found)
        case .commentNotFound: L10n.text(K.social.errors.comment_not_found)
        case .profileNotFound: L10n.text(K.social.errors.profile_not_found)
        case .notFound: L10n.text(K.social.errors.not_found)
        case .cannotBlockSelf: L10n.text(K.social.errors.cannot_block_self)
        case .textInvalid: L10n.text(K.social.errors.content_rejected)
        case .handleRateLimited: L10n.text(K.social.errors.handle_rate_limited)
        // No catalogue line for this one: the generic text, never the backend's English.
        case .snapshotTooLarge: ErrorCopy.message(kind: kind, detail: nil)
        case .titleInvalid: L10n.text(K.socialShare.errors.title_invalid)
        case .planNotFound: L10n.text(K.socialShare.errors.plan_not_found)
        default: ErrorCopy.message(kind: kind, detail: detail)
        }
    }
}
