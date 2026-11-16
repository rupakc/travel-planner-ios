import AuthCore
import SnapshotTesting
import SwiftUI
import TestSupport
import UIKit
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureSocial

@MainActor
final class ProfileSnapshotTests: XCTestCase {
    private func phone(
        _ name: String, dark: Bool = false, language: AppLanguage = .en, size: UIContentSizeCategory = .large, height: CGFloat
    ) -> SnapshotConfig {
        SnapshotConfig(
            name: name, device: .iPhoneSe(.portrait), dark: dark, language: language, size: size,
            canvas: CGSize(width: 320, height: height))
    }

    private func env(_ fakes: FakeRepositories, game: Bool = false) -> AppEnvironment {
        var features: [String: JSONValue] = ["social": .number(1)]
        if game { features["game"] = .number(1) }
        let env = AppEnvironment.fake(user: User(username: "sam"), fakes: fakes, clientConfig: ClientConfig(features: features))
        env.device.acceptCommunityRules(for: "sam")
        return env
    }

    private func editor(_ fakes: FakeRepositories) async -> ProfileEditorModel {
        let environment = env(fakes)
        let model = ProfileEditorModel(
            env: environment, sleep: { _ in }, gameVisibility: { StaticGameVisibility.hidden }, track: { _ in })
        await model.load()
        return model
    }

    private let existing = OwnProfile(
        handle: "sam_t", visibility: .followers, bio: "Slow trains and street food.", showAvatar: false, showHomeCountry: true,
        homeCountry: "PT")

    func test_editorExisting() async {
        let fakes = FakeRepositories()
        fakes.social.onProfile.returns(existing)
        fakes.social.onFollowRequests.returns([FollowRequest(handle: "ana"), FollowRequest(handle: "bo")])
        let model = await editor(fakes)
        await assertSnapshots(
            of: { ProfileEditorView(model: model) }, named: "editor",
            configs: [phone("se-light", height: 1244), phone("se-dark", dark: true, height: 1244)], layout: .screen)
    }

    func test_editorNew() async {
        let model = await editor(FakeRepositories())
        await assertSnapshots(
            of: { ProfileEditorView(model: model) }, named: "editorNew", configs: [phone("se-light", height: 944)], layout: .screen)
    }

    func test_rulesCard() async {
        let fakes = FakeRepositories()
        let environment = AppEnvironment.fake(
            user: User(username: "sam"), fakes: fakes, clientConfig: ClientConfig(features: ["social": .number(1)]))
        let model = ProfileEditorModel(
            env: environment, sleep: { _ in }, gameVisibility: { StaticGameVisibility.hidden }, track: { _ in })
        await model.load()
        model.setHandle("sam_t")
        await model.pendingCheck?.value
        await model.save()
        await assertSnapshots(
            of: { ProfileEditorView(model: model) }, named: "rules", configs: [phone("se-light", height: 280)], layout: .screen)
    }

    private let full = PublicProfile(
        handle: "ana_lisbon", bio: "**bold** [x](javascript:alert(1)) https://evil.test", homeCountry: "PT", countries: ["JP", "IT", "MX"],
        level: 4, badges: [ProfileBadge(id: "first_trip"), ProfileBadge(id: "countries_3")], ideasCount: 3, followersCount: 120,
        followingCount: 45, you: ProfileRelation(followsYou: true))

    private func publicModel(
        _ profile: PublicProfile, fakes: FakeRepositories = FakeRepositories(), game: Bool = true, ideas: Bool = true)
        async -> PublicProfileModel
    {
        fakes.social.onPublicProfile.returns(profile)
        fakes.social.onIdeasOf.returns(
            IdeaPage(
                ideas: !ideas ? [] : [
                    Idea(id: "1", title: "Lisbon in three days", author: IdeaAuthor(handle: profile.handle)),
                    Idea(id: "2", title: "Porto food crawl", author: IdeaAuthor(handle: profile.handle)),
                ]))
        let model = PublicProfileModel(
            env: env(fakes, game: game), handle: profile.handle, gameVisibility: { game ? StaticGameVisibility.visible : .hidden },
            track: { _ in })
        await model.load()
        return model
    }

    func test_publicFull() async {
        let model = await publicModel(full)
        await assertSnapshots(
            of: { PublicProfileView(model: model) }, named: "full",
            configs: [phone("se-light", height: 711), phone("se-dark", dark: true, height: 711)], layout: .screen)
    }

    func test_publicMinimal() async {
        let model = await publicModel(PublicProfile(handle: "quiet_one"), game: false, ideas: false)
        await assertSnapshots(
            of: { PublicProfileView(model: model) }, named: "minimal", configs: [phone("se-light", height: 346)], layout: .screen)
    }

    func test_publicFollowing() async {
        var profile = full
        profile.you = ProfileRelation(pending: true, followsYou: false)
        let model = await publicModel(profile)
        await assertSnapshots(
            of: { PublicProfileView(model: model) }, named: "requested", configs: [phone("se-light", height: 655)], layout: .screen)
    }

    func test_followRequests() async {
        let fakes = FakeRepositories()
        fakes.social.onFollowRequests.returns([FollowRequest(handle: "ana_lisbon"), FollowRequest(handle: "bo")])
        let model = ProfileListModel(env: env(fakes), kind: .requests, track: { _ in })
        await model.load()
        await assertSnapshots(
            of: { ProfileListView(model: model) }, named: "requests",
            configs: [phone("se-light", height: 320), phone("se-dark", dark: true, height: 320)], layout: .screen)
    }

    func test_blockList() async {
        let fakes = FakeRepositories()
        fakes.social.onBlocks.returns([HandleUser(handle: "zed"), HandleUser(handle: "spam_bot_99")])
        let model = ProfileListModel(env: env(fakes), kind: .blocked, track: { _ in })
        await model.load()
        await assertSnapshots(
            of: { ProfileListView(model: model) }, named: "blocks", configs: [phone("se-light", height: 320)], layout: .screen)
    }

    func test_emptyList() async {
        let model = ProfileListModel(env: env(FakeRepositories()), kind: .followers, track: { _ in })
        await model.load()
        await assertSnapshots(
            of: { ProfileListView(model: model) }, named: "empty", configs: [phone("se-light", height: 156)], layout: .screen)
    }

    func test_reportSheet() async {
        let model = ProfileReportModel(env: env(FakeRepositories()), handle: "ana", track: { _ in })
        await assertSnapshots(
            of: { ProfileReportView(model: model) {} }, named: "report", configs: [phone("se-light", height: 681)], layout: .screen)
    }

    func test_profileHindi() async {
        let model = await publicModel(full)
        await assertSnapshots(
            of: { PublicProfileView(model: model) }, named: "hi", configs: [phone("se-hi", language: .hi, height: 711)], layout: .screen)
    }

    func test_profileGermanAX5() async {
        let model = await publicModel(full)
        await assertSnapshots(
            of: { PublicProfileView(model: model) }, named: "ax5",
            configs: [phone("se-de-ax5", language: .de, size: .accessibilityExtraExtraExtraLarge, height: 2182)], layout: .screen)
    }

    func test_editorHindi() async {
        let fakes = FakeRepositories()
        fakes.social.onProfile.returns(existing)
        let model = await editor(fakes)
        await assertSnapshots(
            of: { ProfileEditorView(model: model) }, named: "editorHi", configs: [phone("se-hi", language: .hi, height: 1226)], layout: .screen)
    }
}
