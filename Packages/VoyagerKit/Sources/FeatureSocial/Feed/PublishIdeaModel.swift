import Foundation
import Observation
import Telemetry
import VoyagerEnv
import VoyagerModel

/// Publishing a plan or recap to the feed (`POST /social/ideas`). Needs a handle, a non-private profile and a verified
/// email; a `held` answer is a notice, not an error.
@MainActor @Observable
final class PublishIdeaModel {
    enum Phase: Equatable {
        case form
        case sending
        case published
        case held
        case failed(IdeaFailure)
    }

    /// What the profile check found before the form.
    enum ProfileState: Equatable {
        case unknown, missing, `private`, ready
    }

    let planID: Int
    let kind: IdeaKind
    var title = "" {
        didSet { if title.count > IdeaDraft.maxTitle { title = String(title.prefix(IdeaDraft.maxTitle)) } }
    }
    var caption = "" {
        didSet { if caption.count > IdeaDraft.maxCaption { caption = String(caption.prefix(IdeaDraft.maxCaption)) } }
    }
    private(set) var phase: Phase = .form
    private(set) var profile: ProfileState = .unknown
    /// The rules card is showing: the first publish of this user waits for "I agree" (plan ruling R13).
    private(set) var needsRules = false

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void

    init(
        env: AppEnvironment, planID: Int, kind: IdeaKind, suggestedTitle: String = "",
        track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.planID = planID
        self.kind = kind
        self.title = String(suggestedTitle.prefix(IdeaDraft.maxTitle))
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSubmit: Bool { phase != .sending && profile != .missing && profile != .private && !trimmedTitle.isEmpty }
    var isDone: Bool { phase == .published || phase == .held }
    /// The profile editor can fix the failure (or the pre-check).
    var needsProfileEditor: Bool {
        if profile == .missing || profile == .private { return true }
        if case .failed(let failure) = phase { return failure.needsProfile }
        return false
    }

    func checkProfile() async {
        guard let own = try? await env.social.call({ try await $0.profile() }) else { return }
        if own.handle == nil {
            profile = .missing
        } else {
            profile = own.visibility == .private ? .private : .ready
        }
    }

    private var username: String { env.auth.session?.user.username ?? "" }

    func submit() async {
        guard canSubmit else { return }
        guard env.device.hasAcceptedCommunityRules(for: username) else {
            needsRules = true
            return
        }
        await send()
    }

    func acceptRules() async {
        env.device.acceptCommunityRules(for: username)
        needsRules = false
        await send()
    }

    func declineRules() { needsRules = false }

    private func send() async {
        guard canSubmit else { return }
        phase = .sending
        let draft = IdeaDraft(
            planID: planID, kind: kind, title: trimmedTitle,
            caption: caption.trimmingCharacters(in: .whitespacesAndNewlines), locale: env.language.language.rawValue)
        do {
            let idea = try await env.social.call { try await $0.publish(draft) }
            phase = idea.status == .held ? .held : .published
            emit(.socialIdeaPublish(kind: kind.rawValue))
        } catch is CancellationError {
            phase = .form
        } catch {
            phase = .failed(IdeaFailure(error))
        }
    }

    func openEditor() { env.router.open(.profileEditor) }
    func openFeed() { env.router.open(.ideas) }
}
