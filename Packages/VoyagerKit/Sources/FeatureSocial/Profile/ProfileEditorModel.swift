import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerData
import VoyagerEnv
import VoyagerModel

/// Create or edit the caller's own profile (`GET|PUT /social/profile`). Nothing is public until the user chooses it: a new
/// profile is private with every extra switched off. The handle is checked live (debounced) while typing, and the
/// community rules are accepted once per user before the first save (plan ruling R13).
@MainActor @Observable
final class ProfileEditorModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// `features.social` is off, or the route turned out to be missing.
        case unavailable
        case failed(kind: ErrorPresentationKind, detail: String?)
    }

    enum HandleStatus: Equatable {
        case idle
        case checking
        case available
        case unavailable(String)
    }

    enum Notice: Equatable {
        case saved
        case failed(String)
    }

    static let maxBio = 160
    static let debounce: Duration = .milliseconds(450)

    private(set) var phase: Phase = .loading
    private(set) var original = OwnProfile()
    private(set) var handleStatus: HandleStatus = .idle
    private(set) var saving = false
    private(set) var notice: Notice?
    /// The rules card is showing: the first save of this user waits for "I agree".
    private(set) var needsRules = false
    /// Pending follow requests (shown as a count on the row; nil until loaded).
    private(set) var requestCount: Int?

    // The draft.
    private(set) var handle = ""
    var visibility: ProfileVisibility = .private
    private(set) var bio = ""
    var showAvatar = false
    var showHomeCountry = false
    var showCountries = false
    var showLevel = false
    var showBadges = false
    var leaderboardOptIn = false
    var homeCountry: String?

    @ObservationIgnored let env: AppEnvironment
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private let gameVisibility: @MainActor () -> any GameVisibility
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    init(
        env: AppEnvironment, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        gameVisibility: (@MainActor () -> any GameVisibility)? = nil, track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.sleep = sleep
        self.gameVisibility = gameVisibility ?? { Self.defaultGameVisibility(env: env) }
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    @MainActor static func defaultGameVisibility(env: AppEnvironment) -> any GameVisibility {
        StaticGameVisibility.playDriven(
            gameFeature: RemoteFeatures(config: env.clientConfig).game, hideGameSetting: env.play.hideGameSetting(),
            hiddenByServer: env.play.isHiddenByServer)
    }

    // MARK: Derived

    var isNew: Bool { !original.hasProfile }
    /// The level, badges and boards switches are game wording: hidden (and left as they are) when the game is hidden.
    var showsGameFields: Bool { gameVisibility().showsGame }
    var bioCount: Int { bio.count }
    var username: String { env.auth.session?.user.username ?? "" }
    var rulesAccepted: Bool { env.device.hasAcceptedCommunityRules(for: username) }
    var noticeText: String? {
        switch notice {
        case .saved: L10n.text(K.social.editor.saved)
        case .failed(let message): message
        case nil: nil
        }
    }

    var handleMessage: String? {
        switch handleStatus {
        case .idle: nil
        case .checking: L10n.text(K.social.editor.handleChecking)
        case .available: L10n.text(K.social.editor.handleOk)
        case .unavailable(let message): message
        }
    }

    var canSave: Bool {
        guard phase == .loaded, !saving else { return false }
        if handleChanged || isNew {
            guard HandleRules.isValid(handle) else { return false }
            if case .unavailable = handleStatus { return false }
            if handleStatus == .checking { return false }
        }
        return isNew || hasChanges
    }

    private var handleChanged: Bool { handle != (original.handle ?? "") }

    var hasChanges: Bool { !patch(forNew: false).isEmpty }

    // MARK: Loading

    func load() async {
        guard env.social.isAvailable else {
            phase = .unavailable
            return
        }
        if phase != .loaded { phase = .loading }
        do {
            let profile = try await env.social.call { try await $0.profile() }
            guard !Task.isCancelled else { return }
            apply(profile)
            phase = .loaded
            emit(.socialProfileView)
            if profile.hasProfile { await loadRequestCount() }
        } catch is CancellationError {
            return
        } catch is SocialService.Unavailable {
            phase = .unavailable
        } catch let error as APIError {
            if case .cancelled = error { return }
            phase = SocialFailure.isFeatureOff(error) ? .unavailable : .failed(kind: error.presentationKind, detail: error.userFacingDetail)
        } catch {
            phase = .failed(kind: .other, detail: nil)
        }
    }

    private func loadRequestCount() async {
        guard let list = try? await env.social.call({ try await $0.followRequests() }) else { return }
        requestCount = list.count
    }

    private func apply(_ profile: OwnProfile) {
        original = profile
        handle = profile.handle ?? ""
        visibility = profile.visibility
        bio = profile.bio
        showAvatar = profile.showAvatar
        showHomeCountry = profile.showHomeCountry
        showCountries = profile.showCountries
        showLevel = profile.showLevel
        showBadges = profile.showBadges
        leaderboardOptIn = profile.leaderboardOptIn
        homeCountry = profile.homeCountry
        handleStatus = .idle
    }

    // MARK: Editing

    func setBio(_ text: String) {
        bio = String(text.prefix(Self.maxBio))
    }

    /// Typing a handle: the text is cleaned, checked locally at once, and sent to `GET /social/handles/check` only after
    /// the user paused (each keystroke cancels the previous wait, so a burst makes one call).
    func setHandle(_ text: String) {
        let cleaned = HandleRules.normalized(String(text.prefix(HandleRules.maxLength + 1)))
        handle = cleaned
        checkTask?.cancel()
        checkTask = nil
        notice = nil
        if cleaned == (original.handle ?? "") || cleaned.isEmpty {
            handleStatus = .idle
            return
        }
        guard HandleRules.isValid(cleaned) else {
            handleStatus = .unavailable(L10n.text(K.social.editor.handleReason.invalid))
            return
        }
        handleStatus = .checking
        let wait = sleep
        checkTask = Task { [weak self] in
            do { try await wait(Self.debounce) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.runCheck(cleaned)
        }
    }

    /// The pending handle check, for tests to await.
    var pendingCheck: Task<Void, Never>? { checkTask }

    private func runCheck(_ candidate: String) async {
        do {
            let result = try await env.social.call { try await $0.checkHandle(candidate) }
            guard !Task.isCancelled, candidate == handle else { return }
            if result.available {
                handleStatus = .available
            } else {
                handleStatus = .unavailable(Self.reasonText(result.reason))
            }
        } catch is CancellationError {
            return
        } catch {
            // A check that fails says nothing: the save itself answers `handle_taken`.
            guard candidate == handle else { return }
            handleStatus = .idle
        }
    }

    private static func reasonText(_ reason: HandleCheck.Reason?) -> String {
        switch reason {
        case .invalid?: L10n.text(K.social.editor.handleReason.invalid)
        case .reserved?: L10n.text(K.social.editor.handleReason.reserved)
        case .taken?, .unknown?, nil: L10n.text(K.social.editor.handleReason.taken)
        }
    }

    // MARK: Saving

    /// The fields to send: a new profile sends everything it needs; an existing one only what changed.
    func patch(forNew: Bool) -> ProfilePatch {
        var patch = ProfilePatch()
        if forNew || handleChanged { patch.handle = handle }
        if forNew || visibility != original.visibility { patch.visibility = visibility }
        if forNew || bio != original.bio { patch.bio = bio }
        if forNew || showAvatar != original.showAvatar { patch.showAvatar = showAvatar }
        if forNew || showHomeCountry != original.showHomeCountry { patch.showHomeCountry = showHomeCountry }
        if forNew || showCountries != original.showCountries { patch.showCountries = showCountries }
        if forNew || showLevel != original.showLevel { patch.showLevel = showLevel }
        if forNew || showBadges != original.showBadges { patch.showBadges = showBadges }
        if forNew || leaderboardOptIn != original.leaderboardOptIn { patch.leaderboardOptIn = leaderboardOptIn }
        if homeCountry != original.homeCountry, let homeCountry { patch.homeCountry = homeCountry }
        return patch
    }

    /// Saves, after the community rules were accepted (the first save of a user shows them and stops).
    func save() async {
        guard canSave else { return }
        guard rulesAccepted else {
            needsRules = true
            return
        }
        await performSave()
    }

    func acceptRules() async {
        env.device.acceptCommunityRules(for: username)
        needsRules = false
        await performSave()
    }

    func declineRules() {
        needsRules = false
    }

    private func performSave() async {
        guard !saving else { return }
        saving = true
        notice = nil
        defer { saving = false }
        let body = patch(forNew: isNew)
        do {
            let saved = try await env.social.call { try await $0.saveProfile(body) }
            apply(saved)
            notice = .saved
            emit(.socialProfileSave(visibility: saved.visibility.rawValue))
            if requestCount == nil { await loadRequestCount() }
        } catch is CancellationError {
            return
        } catch {
            if let api = error as? APIError, let failure = SocialFailure.from(api) {
                switch failure {
                case .handleTaken, .handleInvalid, .handleReserved:
                    handleStatus = .unavailable(SocialMessage.text(for: error))
                default: break
                }
            }
            notice = .failed(SocialMessage.text(for: error))
        }
    }

    func dismissNotice() {
        notice = nil
    }
}

extension ProfilePatch {
    /// Nothing to send.
    var isEmpty: Bool { self == ProfilePatch() }
}
