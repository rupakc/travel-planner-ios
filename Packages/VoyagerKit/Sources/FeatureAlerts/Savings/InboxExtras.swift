import Foundation
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// What the inbox rows need beyond the notification itself: whether game wording may show, a clock, and the
/// telemetry of the drop card and the digest. Shared by every row of one inbox, so a drop is reported once.
@MainActor
final class InboxExtras {
    private let track: @MainActor (TelemetryEvent) -> Void
    private let visibility: @MainActor () -> any GameVisibility
    private var seenDrops = Set<Int>()

    /// `gameVisibility` defaults to the server flag with an account setting that cannot be read yet (the app has no
    /// account-settings sync), which counts as hidden: game wording is never shown to someone who may have opted out.
    init(
        env: AppEnvironment, track: @escaping @MainActor (TelemetryEvent) -> Void,
        gameVisibility: (@MainActor () -> any GameVisibility)? = nil
    ) {
        self.track = track
        visibility = gameVisibility ?? { [unowned env] in
            StaticGameVisibility(gameFeature: RemoteFeatures(config: env.clientConfig).game, hideGameSetting: nil)
        }
    }

    var showsGame: Bool { visibility().showsGame }

    /// The drop card for this row, when it carries an observed drop.
    func dropContent(for item: AppNotification) -> DropMomentContent? {
        guard let drop = item.dropData else { return nil }
        return DropMomentContent(
            drop: drop, game: item.gameDelta, showsGame: showsGame, watchTitle: item.data["title"].string)
    }

    /// `alert_drop_seen`, once per notification.
    func dropSeen(_ item: AppNotification) {
        guard let drop = item.dropData, seenDrops.insert(item.id).inserted else { return }
        track(.alertDropSeen(kind: Self.watchKind(item), targetHit: drop.targetHit, via: "in_app"))
    }

    /// `alert_digest_open` for a tap on a digest row.
    func digestOpened() { track(.alertDigestOpen(via: "in_app")) }

    /// The drop's watch kind as a telemetry token: `data.watch_kind`, else flight for `fare_drop`.
    static func watchKind(_ item: AppNotification) -> String {
        let kinds = ["flight", "hotel", "activity", "trip"]
        if let kind = item.data["watch_kind"].string, kinds.contains(kind) { return kind }
        if let kind = item.data["kind"].string, kinds.contains(kind) { return kind }
        return "flight"
    }
}

private struct InboxExtrasKey: EnvironmentKey {
    static var defaultValue: InboxExtras? { nil }
}

extension EnvironmentValues {
    /// Set by the inbox; nil in previews of a bare row, where the slot shows nothing.
    var inboxExtras: InboxExtras? {
        get { self[InboxExtrasKey.self] }
        set { self[InboxExtrasKey.self] = newValue }
    }
}
