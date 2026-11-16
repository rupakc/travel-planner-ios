import AuthCore
import SnapshotTesting
import SwiftUI
import TestSupport
import UIKit
import VoyagerEnv
import VoyagerModel
import Networking
import XCTest

@testable import FeatureSocial

@MainActor
final class FeedSnapshotTests: XCTestCase {
    private func phone(
        _ name: String, dark: Bool = false, language: AppLanguage = .en, size: UIContentSizeCategory = .large, height: CGFloat
    ) -> SnapshotConfig {
        SnapshotConfig(
            name: name, device: .iPhoneSe(.portrait), dark: dark, language: language, size: size,
            canvas: CGSize(width: 320, height: height))
    }

    private static let snapshot: JSONValue = .object([
        "destinations": .array([.string("Lisbon"), .string("Porto")]), "days": .number(7),
        "stats": .array([
            .object(["key": .string("activities"), "count": .number(6)]), .object(["key": .string("hotels"), "count": .number(2)]),
        ]),
        "items": .object([
            "activities": .array(
                [
                    "Tram 28 ride", "Belem pastry tour", "Alfama walking tour", "Sunset at Miradouro", "Fado night",
                    "Day trip to Sintra", "Time Out Market",
                ]
                    .map { .object(["name": .string($0)]) }),
            "hotels": .array([.object(["name": .string("Hotel Avenida Palace")])]),
        ]),
    ])

    private static var ideas: [Idea] {
        [
            Idea(
                id: "1", title: "A slow week in Lisbon and Porto", caption: "Trams, pastries and one very good fado night.",
                author: IdeaAuthor(handle: "ana_travels"), snapshot: snapshot, likes: 12, saves: 3, comments: 2, liked: true),
            Idea(
                id: "2", kind: .recap, title: "Japan recap", caption: "", author: IdeaAuthor(handle: "kenji"),
                snapshot: .object(["destinations": .array([.string("Tokyo")]), "days": .number(10)]), likes: 0, saved: true),
            Idea(
                id: "3", title: "My weekend plan", caption: "Waiting for the quick review.", author: IdeaAuthor(handle: "me_myself"),
                snapshot: .null, mine: true, status: .held),
        ]
    }

    private func make(_ ideas: [Idea], profile: Bool = true, next: String? = nil) async -> (FeedModel, AppEnvironment) {
        let fakes = FakeRepositories()
        fakes.social.onFeed.returns(IdeaPage(ideas: ideas, next: next))
        if profile { fakes.social.onProfile.returns(OwnProfile(handle: "me_myself", visibility: .public)) }
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["social": .number(1)]))
        let model = FeedModel(env: env, track: { _ in })
        await model.start()
        return (model, env)
    }

    func test_feedCards() async {
        let (model, env) = await make(Self.ideas, next: "more")
        await assertSnapshots(
            of: { IdeasFeedView(model: model, env: env, supportURL: URL(string: "https://example.test/help")) }, named: "cards",
            configs: [phone("se-light", height: 1352), phone("se-dark", dark: true, height: 1352)], layout: .screen)
    }

    func test_feedHindi() async {
        let (model, env) = await make(Self.ideas)
        await assertSnapshots(
            of: { IdeasFeedView(model: model, env: env) }, named: "hi", configs: [phone("se-hi", language: .hi, height: 1246)],
            layout: .screen)
    }

    func test_feedGermanAX5() async {
        let (model, env) = await make(Array(Self.ideas.prefix(1)))
        await assertSnapshots(
            of: { IdeasFeedView(model: model, env: env) }, named: "ax5",
            configs: [phone("se-de-ax5", language: .de, size: .accessibilityExtraExtraExtraLarge, height: 2126)], layout: .screen)
    }

    func test_feedTwoColumn() async {
        let (model, env) = await make(Self.ideas + [Self.ideas[0]].map {
            var copy = $0
            copy.id = "4"
            return copy
        })
        let pad = SnapshotConfig(name: "ipad-light", device: .iPadPro11(.portrait), dark: false, canvas: CGSize(width: 834, height: 948))
        await assertSnapshots(of: { IdeasFeedView(model: model, env: env) }, named: "two-column", configs: [pad], layout: .screen)
    }

    func test_feedEmptyAndPrompt() async {
        let (model, env) = await make([], profile: false)
        await assertSnapshots(
            of: { IdeasFeedView(model: model, env: env) }, named: "empty", configs: [phone("se-light", height: 410)], layout: .screen)
    }

    func test_feedError() async {
        let fakes = FakeRepositories()
        fakes.social.onFeed.fails(APIError.network)
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["social": .number(1)]))
        let model = FeedModel(env: env, track: { _ in })
        await model.start()
        await assertSnapshots(
            of: { IdeasFeedView(model: model, env: env) }, named: "error", configs: [phone("se-light", height: 340)], layout: .screen)
    }

    /// Hostile text (markdown, a javascript link, a bare URL) shows exactly as typed.
    func test_userTextRendersVerbatim() async {
        let hostile = "**bold** [x](javascript:alert(1)) https://evil.test"
        let idea = Idea(
            id: "h", title: hostile, caption: hostile, author: IdeaAuthor(handle: "evil_handle"),
            snapshot: .object(["items": .object(["activities": .array([.object(["name": .string(hostile)])])])]))
        let (model, env) = await make([idea])
        await assertSnapshots(
            of: { IdeasFeedView(model: model, env: env) }, named: "hostile", configs: [phone("se-light", height: 518)],
            layout: .screen)
    }

    func test_ideaDetailWithComments() async {
        let fakes = FakeRepositories()
        fakes.social.onIdea.returns(Self.ideas[0])
        fakes.social.onComments.returns(
            CommentPage(comments: [
                IdeaComment(id: "c1", authorHandle: "bo", text: "Which hotel did you like most?", helpful: true),
                IdeaComment(id: "c2", authorHandle: "me_myself", text: "Love this.", mine: true, status: .held),
            ]))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["social": .number(1)]))
        let detail = IdeaDetailModel(env: env, ideaID: "1", track: { _ in })
        await detail.start()
        let comments = CommentsModel(env: env, ideaID: "1", ideaMine: false, track: { _ in })
        await comments.start()
        await assertSnapshots(
            of: { IdeaDetailView(model: detail, comments: comments, env: env) }, named: "detail",
            configs: [phone("se-light", height: 1102), phone("se-dark", dark: true, height: 1102)], layout: .screen)
    }

    func test_ideaGone() async {
        let fakes = FakeRepositories()
        fakes.social.onIdea.fails(APIError.notFound("Idea not found."))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["social": .number(1)]))
        let detail = IdeaDetailModel(env: env, ideaID: "1", track: { _ in })
        await detail.start()
        let comments = CommentsModel(env: env, ideaID: "1", ideaMine: false, track: { _ in })
        await assertSnapshots(
            of: { IdeaDetailView(model: detail, comments: comments, env: env) }, named: "gone",
            configs: [phone("se-light", height: 200)], layout: .screen)
    }

    // MARK: Publish and report

    private func publishModel(profile: OwnProfile, submit: Bool = false, status: IdeaStatus = .published, rules: Bool = true) async -> PublishIdeaModel {
        let fakes = FakeRepositories()
        fakes.social.onProfile.returns(profile)
        fakes.social.onPublish.returns(Self.ideas[0].withStatus(status))
        let env = AppEnvironment.fake(
            user: User(username: "sam"), fakes: fakes, clientConfig: ClientConfig(features: ["social": .number(1)]))
        if rules { env.device.acceptCommunityRules(for: "sam") }
        let model = PublishIdeaModel(env: env, planID: 3, kind: .plan, suggestedTitle: "A slow week in Lisbon", track: { _ in })
        await model.checkProfile()
        if submit { await model.submit() }
        return model
    }

    func test_publishSheet() async {
        let model = await publishModel(profile: OwnProfile(handle: "me_myself", visibility: .public))
        await assertSnapshots(
            of: { PublishIdeaView(model: model) }, named: "publish",
            configs: [phone("se-light", height: 510), phone("se-dark", dark: true, height: 510)], layout: .screen)
    }

    func test_publishNeedsProfile() async {
        let model = await publishModel(profile: OwnProfile())
        await assertSnapshots(
            of: { PublishIdeaView(model: model) }, named: "needs-profile", configs: [phone("se-light", height: 622)], layout: .screen)
    }

    func test_publishRulesCard() async {
        let model = await publishModel(profile: OwnProfile(handle: "me_myself", visibility: .public), submit: true, rules: false)
        await assertSnapshots(
            of: { PublishIdeaView(model: model) }, named: "rules",
            configs: [phone("se-light", height: 324), phone("se-dark", dark: true, height: 324)], layout: .screen)
    }

    func test_heldNotice() async {
        let model = await publishModel(profile: OwnProfile(handle: "me_myself", visibility: .public), submit: true, status: .held)
        await assertSnapshots(
            of: { PublishIdeaView(model: model) }, named: "held", configs: [phone("se-light", height: 192)], layout: .screen)
    }

    func test_reportSheet() async {
        let env = AppEnvironment.fake()
        let model = ReportModel(target: .idea, id: "1", env: env)
        await assertSnapshots(
            of: { ReportSheetView(model: model, supportURL: URL(string: "https://example.test/help")) }, named: "report",
            configs: [phone("se-light", height: 671), phone("se-dark", dark: true, height: 671)], layout: .screen)
    }
}

extension Idea {
    fileprivate func withStatus(_ status: IdeaStatus) -> Idea {
        var copy = self
        copy.status = status
        return copy
    }
}
