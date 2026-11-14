import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
#if canImport(UIKit)
import UIKit
#endif
import VoyagerEnv
import VoyagerModel

/// Why a share could not be made: the translated code when there is one, else the generic failure kind and the
/// backend's own text.
struct ShareSheetFailure: Equatable {
    var failure: ShareFailure?
    var kind: ErrorPresentationKind
    var detail: String?

    var message: String {
        switch failure {
        case .noActiveTrip: return L10n.text(K.share.errors.noActiveTrip)
        case .sharingDisabled, .invalidKind, .playDisabled, .cardBusy: return L10n.text(K.share.errors.unavailable)
        case .planNotFound, .sessionNotFound, .shareNotFound: return L10n.text(K.share.errors.create)
        case nil: return ErrorCopy.message(kind: kind, detail: detail)
        }
    }
}

/// The share sheet (plan ruling R5): the sharer's choices, one `POST /shares`, then the link and the cards. A second
/// create for the same item replaces the options of the same link ("Update link"); defaults stay private.
@MainActor @Observable
final class ShareSheetModel {
    enum Phase: Equatable {
        case form
        case creating
        case ready
        case failed(ShareSheetFailure)
    }

    /// A downloaded card. Any failure (untrusted host, 503 `card_busy`, bad bytes) leaves `.unavailable`: the link is
    /// still shared, the image is not offered.
    enum CardState: Equatable {
        case idle
        case loading
        case ready(URL)
        case unavailable
    }

    enum Outcome: Equatable {
        case created, updated, copied, copyFailed
    }

    let target: ShareTarget
    var options = ShareOptions()
    private(set) var phase: Phase = .form
    private(set) var share: Share?
    private(set) var linkCard: CardState = .idle
    private(set) var storyCard: CardState = .idle
    /// A legacy plan link (`POST /plans/{id}/share`): no options, no card.
    private(set) var legacyLink: URL?
    /// What the last action did; translated when shown, so a language switch (or a snapshot's language) applies.
    private(set) var outcome: Outcome?
    var copyFailed: Bool { outcome == .copyFailed }
    /// The options the current link was made with; `isDirty` compares against them.
    private(set) var appliedOptions: ShareOptions?

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let loader: any ShareCardLoading
    @ObservationIgnored private let pasteboard: @MainActor (String) -> Bool
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void
    @ObservationIgnored private var cardTask: Task<Void, Never>?
    @ObservationIgnored private var didOpen = false

    init(
        env: AppEnvironment, target: ShareTarget, loader: (any ShareCardLoading)? = nil,
        pasteboard: @escaping @MainActor (String) -> Bool = ShareSheetModel.systemPasteboard,
        track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.target = target
        self.loader = loader ?? env.shares.cardLoader()
        self.pasteboard = pasteboard
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    // MARK: Derived

    var kind: ShareKind { target.kind }

    /// `features.sharing >= 1` (and the route has not turned out to be missing).
    var isV2: Bool { env.shares.isAvailable }

    /// Sharing 2.0 is off but a plan still has the legacy link (the older backend's behaviour, kept).
    var isLegacyOnly: Bool { !isV2 && kind == .plan }

    /// Neither flow exists for this kind: only a message.
    var isUnavailable: Bool { !isV2 && kind != .plan }

    var title: String { L10n.text(titleKey) }

    private var titleKey: LKey {
        switch kind {
        case .plan: K.share.titleKind.plan
        case .recap: K.share.titleKind.recap
        case .savings: K.share.titleKind.savings
        case .quiz: K.share.titleKind.quiz
        case .status: K.share.titleKind.status
        case .unknown: K.share.title
        }
    }

    var status: String? {
        switch outcome {
        case .created: L10n.text(K.share.status.created)
        case .updated: L10n.text(K.share.status.updated)
        case .copied: L10n.text(K.share.status.copy)
        case .copyFailed: L10n.text(K.share.status.copyFailed)
        case nil: nil
        }
    }

    /// "My trip plan on Voyager": the message and preview title. An unknown kind is a plain link with none.
    var shareText: String? {
        let key: LKey
        switch share?.kind ?? kind {
        case .plan: key = K.share.text.plan
        case .recap: key = K.share.text.recap
        case .savings: key = K.share.text.savings
        case .quiz: key = K.share.text.quiz
        case .status: key = K.share.text.status
        case .unknown: return nil
        }
        return L10n.text(key)
    }

    /// The URL to share: the Phase 4 link, else the legacy one.
    var linkURL: URL? { share?.linkURL ?? legacyLink }

    /// An unknown kind gets no card (it is a plain link).
    var offersCard: Bool { (share?.kind.isKnown ?? false) && !isLegacyOnly }

    var isWorking: Bool { phase == .creating }

    var hasLink: Bool { linkURL != nil }

    /// Choices changed since the link was made.
    var isDirty: Bool { appliedOptions != nil && appliedOptions != options }

    var primaryTitle: String {
        if phase == .creating { return L10n.text(K.share.working) }
        return L10n.text(hasLink ? K.share.update : K.share.create)
    }

    /// "Update link" is pointless until a choice changed; "Create link" is always available.
    var canCreate: Bool { phase != .creating && (!hasLink || isDirty) }

    /// Plan, recap and savings let the sharer pick; quiz and status share a fixed card.
    var showsOptions: Bool { isV2 && kind != .quiz }

    // MARK: Actions

    /// Telemetry: the sheet was opened (once).
    func opened() {
        guard !didOpen else { return }
        didOpen = true
        if let value = kind.telemetryValue { emit(.shareOpen(kind: value)) }
    }

    func create() async {
        guard canCreate else { return }
        outcome = nil
        if isLegacyOnly {
            await createLegacy()
            return
        }
        guard isV2 else {
            phase = .failed(ShareSheetFailure(failure: .sharingDisabled, kind: .other, detail: nil))
            return
        }
        let wasUpdate = hasLink
        phase = .creating
        do {
            let made = try await env.shares.create(ShareRequest(target: target, options: options))
            guard !Task.isCancelled else { return }
            share = made
            appliedOptions = options
            phase = .ready
            outcome = wasUpdate ? .updated : .created
            if let value = made.kind.telemetryValue ?? kind.telemetryValue {
                emit(.shareCreate(kind: value, dates: options.dates.rawValue))
            }
            startCards(for: made)
        } catch is CancellationError {
            phase = share == nil ? .form : .ready
        } catch {
            await failed(error)
        }
    }

    func copyLink() {
        guard let url = linkURL else { return }
        outcome = pasteboard(url.absoluteString) ? .copied : .copyFailed
        track(target: "copy")
    }

    /// The system share sheet was opened for the link or the image (`native`); `tid` names the control.
    func didShareNatively(tid: String) {
        emit(.uiTap(tid: tid, route: TelemetryRouteName.template(for: .shareSheet(target))))
        track(target: "native")
    }

    func cancel() {
        cardTask?.cancel()
    }

    // MARK: Plumbing

    private func track(target name: String) {
        guard let value = (share?.kind ?? kind).telemetryValue else { return }
        emit(.shareAction(kind: value, target: name))
    }

    private func failed(_ error: any Error) async {
        guard let api = error as? APIError else {
            if error is SharesService.Unavailable, kind == .plan {
                await createLegacy()
            } else {
                phase = share == nil ? .failed(ShareSheetFailure(failure: nil, kind: .other, detail: nil)) : .ready
            }
            return
        }
        if case .cancelled = api {
            phase = share == nil ? .form : .ready
            return
        }
        let failure = ShareFailure.from(api, call: .create)
        // Sharing switched off since /config: a plan falls back to the legacy link.
        if failure == .sharingDisabled || ShareFailure.isRouteMissing(api), kind == .plan, share == nil {
            await createLegacy()
            return
        }
        phase = .failed(ShareSheetFailure(failure: failure, kind: api.presentationKind, detail: api.userFacingDetail))
    }

    private func createLegacy() async {
        guard case .plan(let id) = target else { return }
        phase = .creating
        do {
            let token = try await env.repos.plans.share(id: id)
            guard let base = env.server.baseURL, let url = URL(string: "share/" + token, relativeTo: base)?.absoluteURL else {
                phase = .failed(ShareSheetFailure(failure: nil, kind: .other, detail: nil))
                return
            }
            legacyLink = url
            phase = .ready
            outcome = .created
            emit(.shareCreate(kind: "plan", dates: ShareDates.exact.rawValue))
        } catch let error as APIError {
            phase = .failed(ShareSheetFailure(failure: nil, kind: error.presentationKind, detail: error.userFacingDetail))
        } catch {
            phase = .failed(ShareSheetFailure(failure: nil, kind: .other, detail: nil))
        }
    }

    /// Downloads both cards at once. A failure leaves that card `.unavailable`; the link is unaffected.
    private func startCards(for made: Share) {
        cardTask?.cancel()
        guard made.kind.isKnown else {
            linkCard = .unavailable
            storyCard = .unavailable
            return
        }
        linkCard = .loading
        storyCard = .loading
        let loader = loader
        let token = made.token
        let linkURL = made.cardLinkURL.flatMap(URL.init(string:))
        let storyURL = made.cardStoryURL.flatMap(URL.init(string:))
        cardTask = Task { [weak self] in
            async let link = Self.download(loader, linkURL, token: token, size: .link)
            async let story = Self.download(loader, storyURL, token: token, size: .story)
            let (linkState, storyState) = await (link, story)
            guard !Task.isCancelled, let self, self.share?.token == token else { return }
            self.linkCard = linkState
            self.storyCard = storyState
        }
    }

    private nonisolated static func download(
        _ loader: any ShareCardLoading, _ url: URL?, token: String, size: ShareCardSize
    ) async -> CardState {
        guard let url else { return .unavailable }
        do {
            return .ready(try await loader.load(url, token: token, size: size))
        } catch {
            return .unavailable
        }
    }

    /// Awaits the card downloads (tests).
    func settled() async {
        await cardTask?.value
    }

    static func systemPasteboard(_ text: String) -> Bool {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        return UIPasteboard.general.hasStrings
        #else
        return false
        #endif
    }
}
