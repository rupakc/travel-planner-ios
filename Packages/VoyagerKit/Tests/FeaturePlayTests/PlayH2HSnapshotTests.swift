import AuthCore
import Networking
import SnapshotTesting
import SwiftUI
import TestSupport
import UIKit
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeaturePlay

/// Head-to-head, boards and the challenge card (Task 5.5). Canvas heights are measured from the recorded PNGs (content
/// bottom plus the screen's own padding), never padded.
@MainActor
final class PlayH2HSnapshotTests: XCTestCase {
    private func phone(
        _ name: String, dark: Bool = false, language: AppLanguage = .en, size: UIContentSizeCategory = .large, height: CGFloat
    ) -> SnapshotConfig {
        SnapshotConfig(
            name: name, device: .iPhoneSe(.portrait), dark: dark, language: language, size: size,
            canvas: CGSize(width: 320, height: height))
    }

    private func pad(_ name: String, height: CGFloat) -> SnapshotConfig {
        SnapshotConfig(name: name, device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: height))
    }

    private let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge

    private func env(_ fakes: FakeRepositories) -> AppEnvironment {
        AppEnvironment.fake(
            user: User(username: "sam"), fakes: fakes,
            clientConfig: ClientConfig(features: ["play": .number(1), "game": .number(1), "social": .number(1)]))
    }

    // MARK: Head-to-head list

    private let matches = [
        H2HMatch(id: "1", opponent: "mia", pack: "flags", state: .waitingYou),
        H2HMatch(id: "2", opponent: "jonas_travels", pack: "capitals", state: .waitingThem),
        H2HMatch(id: "3", opponent: "priya", pack: "cuisine", state: .done, you: 4, them: 3, winner: .you),
        H2HMatch(id: "4", opponent: "lee", pack: "flags", state: .declined),
        H2HMatch(id: "5", opponent: "amelie", pack: "landmarks", state: .expired),
    ]

    private func list(_ matches: [H2HMatch], error: Bool = false) async -> H2HListModel {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns(matches)
        let model = H2HListModel(env: env(fakes), track: { _ in })
        await model.load()
        if error {
            fakes.play.onChallenge.fails(
                APIError.client(status: 422, detail: "x", code: "limit_reached", body: .object(["error_code": .string("limit_reached")])))
            model.handle = "mia"
            await model.create()
        }
        return model
    }

    func test_h2hList() async {
        let model = await list(matches)
        await assertSnapshots(
            of: { H2HSectionView(model: model) }, named: "list",
            configs: [phone("se-light", height: 1500), phone("se-dark", dark: true, height: 1500), pad("ipad-light", height: 900)],
            layout: .component)
    }

    func test_h2hListEmptyWithError() async {
        let model = await list([], error: true)
        await assertSnapshots(
            of: { H2HSectionView(model: model) }, named: "empty", configs: [phone("se-light", height: 900)], layout: .component)
    }

    func test_h2hListGermanAX5() async {
        let model = await list(Array(matches.prefix(3)))
        await assertSnapshots(
            of: { H2HSectionView(model: model) }, named: "ax5",
            configs: [phone("se-de-ax5", language: .de, size: ax5, height: 4000)], layout: .component)
    }

    // MARK: One match

    private func matchModel(_ match: H2HMatch) async -> H2HMatchModel {
        let fakes = FakeRepositories()
        fakes.play.onMatches.returns([match])
        let model = H2HMatchModel(env: env(fakes), matchID: match.id, track: { _ in })
        await model.load()
        return model
    }

    func test_h2hInvite() async {
        let model = await matchModel(matches[0])
        await assertSnapshots(
            of: { H2HMatchView(model: model) }, named: "invite",
            configs: [phone("se-light", height: 308), phone("se-dark", dark: true, height: 308)], layout: .screen)
    }

    func test_h2hResult() async {
        let model = await matchModel(matches[2])
        await assertSnapshots(
            of: { H2HMatchView(model: model) }, named: "result",
            configs: [
                phone("se-light", height: 284), phone("se-dark", dark: true, height: 284),
                phone("se-hi", language: .hi, height: 284),
            ], layout: .screen)
    }

    func test_h2hResultGermanAX5() async {
        let model = await matchModel(matches[0])
        await assertSnapshots(
            of: { H2HMatchView(model: model) }, named: "inviteAX5",
            configs: [phone("se-de-ax5", language: .de, size: ax5, height: 351)], layout: .screen)
    }

    // MARK: Boards

    private let rows = [
        BoardRow(rank: 1, handle: "mia", score: 640, level: 4),
        BoardRow(rank: 2, handle: "jonas_travels", score: 610),
        BoardRow(rank: 3, handle: "sam", score: 410, isYou: true),
        BoardRow(rank: 4, handle: "priya", score: 380),
    ]

    private func board(
        scope: BoardScope = .global, rows: [BoardRow], you: BoardYou?, week: BoardWeek = .current
    ) async -> BoardModel {
        let fakes = FakeRepositories()
        fakes.play.onLeaderboard.returns(Leaderboard(week: "2026-W46", rows: rows, you: you))
        let model = BoardModel(env: env(fakes), track: { _ in })
        await model.select(scope: scope)
        if week == .previous { await model.select(week: .previous) }
        return model
    }

    func test_boardGlobal() async {
        let model = await board(rows: rows, you: BoardYou(rank: 3, score: 410, optedIn: true))
        await assertSnapshots(
            of: { BoardSectionView(model: model) }, named: "global",
            configs: [phone("se-light", height: 370), phone("se-dark", dark: true, height: 370), pad("ipad-light", height: 374)],
            layout: .component)
    }

    func test_boardOptIn() async {
        let model = await board(rows: Array(rows.prefix(2)), you: BoardYou(rank: nil, score: 0, optedIn: false))
        await assertSnapshots(
            of: { BoardSectionView(model: model) }, named: "optin", configs: [phone("se-light", height: 432)], layout: .component)
    }

    func test_boardNeedsProfile() async {
        let model = await board(rows: Array(rows.prefix(2)), you: nil)
        await assertSnapshots(
            of: { BoardSectionView(model: model) }, named: "needsProfile",
            configs: [phone("se-dark", dark: true, height: 432)], layout: .component)
    }

    func test_boardFriendsEmpty() async {
        let model = await board(scope: .friends, rows: [], you: BoardYou(rank: nil, score: 0, optedIn: true))
        await assertSnapshots(
            of: { BoardSectionView(model: model) }, named: "friendsEmpty",
            configs: [phone("se-light", height: 300), phone("se-dark", dark: true, height: 300)], layout: .component)
    }

    func test_boardHindi() async {
        let model = await board(rows: rows, you: BoardYou(rank: 3, score: 410, optedIn: true), week: .previous)
        await assertSnapshots(
            of: { BoardSectionView(model: model) }, named: "hi",
            configs: [phone("se-hi", language: .hi, height: 370)], layout: .component)
    }

    func test_boardGermanAX5() async {
        let model = await board(rows: rows, you: BoardYou(rank: 3, score: 410, optedIn: true))
        await assertSnapshots(
            of: { BoardSectionView(model: model) }, named: "ax5",
            configs: [phone("se-de-ax5", language: .de, size: ax5, height: 3000)], layout: .component)
    }

    // MARK: Challenge

    func test_challengeCard() async {
        let open = PlayChallenge(id: "2026-W46:JP", kind: .destination, country: "JP")
        await assertSnapshots(
            of: { ChallengeCard(challenge: open, busy: false, start: {}) }, named: "open",
            configs: [phone("se-light", height: 206), phone("se-dark", dark: true, height: 206)], layout: .component)
    }

    func test_challengeCardDoneAndAX5() async {
        let done = PlayChallenge(id: "w", kind: .featured, done: true)
        let open = PlayChallenge(id: "2026-W46:JP", kind: .destination, country: "JP")
        await assertSnapshots(
            of: { ChallengeCard(challenge: done, busy: false, start: {}) }, named: "done",
            configs: [phone("se-light", height: 183)], layout: .component)
        await assertSnapshots(
            of: { ChallengeCard(challenge: open, busy: false, start: {}) }, named: "ax5",
            configs: [phone("se-de-ax5", language: .de, size: ax5, height: 476)], layout: .component)
    }
}
