import Foundation
import L10n
import Networking
import Observation
import SharedUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// One row of My shares: a Phase 4 share or a legacy plan link, reduced to what the row shows.
struct MyShareItem: Identifiable, Equatable {
    enum Source: Equatable { case share, legacy }

    let id: String
    let source: Source
    let kind: ShareKind
    /// The plan's name (`Price alerts` for savings); user text, always shown verbatim.
    let title: String
    let url: String
    /// What "Open" shows in the app; nil when the URL carries no readable token.
    let token: String?
    let planID: Int?
    let createdAt: Date?
    /// What the link reveals; nil for a legacy link (it has none).
    var options: ShareOptions?

    var linkURL: URL? { URL(string: url) }

    /// "Share again" reopens the share sheet for the same item. Quiz and status shares need a session or an active trip
    /// the list does not know, and an unknown kind is only a link.
    var target: ShareTarget? {
        switch kind {
        case .plan:
            guard let planID else { return nil }
            return ShareTarget.plan(id: planID)
        case .recap:
            guard let planID else { return nil }
            return ShareTarget.recap(planID: planID)
        case .savings:
            return ShareTarget.savings
        case .quiz, .status, .unknown:
            return nil
        }
    }
}

/// My shares: the caller's links (`GET /shares`, newest first) and the plan links from before sharing 2.0. Revoking is
/// immediate and has no undo; the confirmation says so.
@MainActor @Observable
final class MySharesModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// `features.sharing` is off, or the route turned out to be missing.
        case unavailable
        case failed(kind: ErrorPresentationKind, detail: String?)
    }

    enum Notice: Equatable {
        case copied, copyFailed, revoked
        case revokeFailed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var shares: [MyShareItem] = []
    private(set) var legacy: [MyShareItem] = []
    /// The row whose "Stop sharing" awaits its answer.
    private(set) var confirming: String?
    private(set) var revoking: Set<String> = []
    private(set) var notice: Notice?
    /// The last pasted link was not one of ours.
    private(set) var pasteInvalid = false
    /// The row whose share sheet is open ("Share again").
    var sharingAgain: MyShareItem?

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let pasteboard: @MainActor (String) -> Bool
    @ObservationIgnored private let emit: @MainActor (TelemetryEvent) -> Void

    init(
        env: AppEnvironment, pasteboard: @escaping @MainActor (String) -> Bool = ShareSheetModel.systemPasteboard,
        track: (@MainActor (TelemetryEvent) -> Void)? = nil
    ) {
        self.env = env
        self.pasteboard = pasteboard
        let telemetry = env.telemetry
        self.emit = track ?? { telemetry.track($0) }
    }

    var isEmpty: Bool { shares.isEmpty && legacy.isEmpty }

    var noticeText: String? {
        switch notice {
        case .copied: L10n.text(K.share.mine.copied)
        case .copyFailed: L10n.text(K.share.mine.copyFailed)
        case .revoked: L10n.text(K.share.mine.revoked)
        case .revokeFailed(let message): message
        case nil: nil
        }
    }

    // MARK: Loading

    func load() async {
        guard env.shares.isAvailable else {
            phase = .unavailable
            return
        }
        // A refresh keeps the rows on screen.
        if phase != .loaded { phase = .loading }
        do {
            let list = try await env.shares.list()
            guard !Task.isCancelled else { return }
            shares = Self.newestFirst(list.shares.map(Self.item(from:)))
            legacy = list.legacyPlanShares.map(Self.item(from:))
            phase = .loaded
        } catch is CancellationError {
            return
        } catch is SharesService.Unavailable {
            phase = .unavailable
        } catch let error as APIError {
            if case .cancelled = error { return }
            if ShareFailure.isRouteMissing(error) || ShareFailure.from(error, call: .list) == .sharingDisabled {
                phase = .unavailable
            } else {
                phase = .failed(kind: error.presentationKind, detail: error.userFacingDetail)
            }
        } catch {
            phase = .failed(kind: .other, detail: nil)
        }
    }

    // MARK: Row actions

    func copy(_ item: MyShareItem) {
        notice = pasteboard(item.url) ? .copied : .copyFailed
        if let value = item.kind.telemetryValue { emit(.shareAction(kind: value, target: "copy")) }
    }

    /// Shows the link in the app's viewer (the same screen a received link opens).
    func open(_ item: MyShareItem) {
        guard let token = item.token else { return }
        env.router.open(.openShare(token: token))
    }

    func shareAgain(_ item: MyShareItem) {
        guard item.target != nil else { return }
        sharingAgain = item
    }

    func askRevoke(_ item: MyShareItem) {
        notice = nil
        confirming = item.id
    }

    func cancelRevoke() {
        confirming = nil
    }

    /// Revokes at once. A 404 (already gone) counts as done; any other failure keeps the row and says so.
    func confirmRevoke(_ item: MyShareItem) async {
        guard !revoking.contains(item.id) else { return }
        revoking.insert(item.id)
        defer { revoking.remove(item.id) }
        do {
            switch item.source {
            case .share:
                guard let token = item.token else { return }
                try await env.shares.revoke(token: token)
            case .legacy:
                guard let planID = item.planID else { return }
                try await env.shares.revokeLegacy(planID: planID)
            }
            removed(item)
        } catch is CancellationError {
            return
        } catch {
            if Self.isGone(error) {
                removed(item)
            } else {
                confirming = nil
                notice = .revokeFailed(Self.revokeMessage(error))
            }
        }
    }

    private func removed(_ item: MyShareItem) {
        shares.removeAll { $0.id == item.id }
        legacy.removeAll { $0.id == item.id }
        confirming = nil
        notice = .revoked
        if let value = item.kind.telemetryValue { emit(.shareRevoke(kind: value)) }
    }

    // MARK: Paste

    /// A link from the paste control: ours opens in the viewer, anything else is refused with a message.
    func paste(_ urls: [URL]) {
        let trusted = env.build.trustedHosts
        let token = urls.lazy.compactMap { ShareLinkParser.token(from: $0, trustedHosts: trusted) }.first
        guard let token else {
            pasteInvalid = true
            return
        }
        pasteInvalid = false
        env.router.open(.openShare(token: token))
    }

    // MARK: Mapping

    private static func isGone(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch ShareFailure.from(api, call: .revoke) {
        case .shareNotFound, .planNotFound: return true
        default: return false
        }
    }

    private static func revokeMessage(_ error: any Error) -> String {
        guard let api = error as? APIError else { return L10n.text(K.share.mine.error) }
        // A 429's own text is the useful one; everything else is the translated failure.
        if case .rateLimited = api { return ErrorCopy.message(kind: .rateLimited, detail: api.userFacingDetail) }
        return L10n.text(K.share.mine.error)
    }

    private static func newestFirst(_ items: [MyShareItem]) -> [MyShareItem] {
        items.enumerated().sorted { lhs, rhs in
            switch (lhs.element.createdAt, rhs.element.createdAt) {
            case (let left?, let right?) where left != right: return left > right
            // A row without a date goes after the dated ones, in the server's order.
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static func item(from share: Share) -> MyShareItem {
        MyShareItem(
            id: "share:" + share.token, source: .share, kind: share.kind, title: share.title ?? "", url: share.url,
            token: share.token, planID: share.planID, createdAt: parse(share.createdAt), options: share.options)
    }

    private static func item(from legacy: LegacyPlanShare) -> MyShareItem {
        MyShareItem(
            id: "legacy:\(legacy.planID)", source: .legacy, kind: .plan, title: legacy.name, url: legacy.url,
            token: ShareLinkParser.token(fromServerURL: legacy.url), planID: legacy.planID, createdAt: nil, options: nil)
    }

    private static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
