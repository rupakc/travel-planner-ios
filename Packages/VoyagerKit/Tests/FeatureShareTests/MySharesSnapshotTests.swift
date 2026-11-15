import SnapshotTesting
import SwiftUI
import TestSupport
import UIKit
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureShare

@MainActor
final class MySharesSnapshotTests: XCTestCase {
    private func phone(_ name: String, dark: Bool = false, language: AppLanguage = .en, height: CGFloat) -> SnapshotConfig {
        SnapshotConfig(
            name: name, device: .iPhoneSe(.portrait), dark: dark, language: language, canvas: CGSize(width: 320, height: height))
    }

    private func makeShare(_ token: String, kind: ShareKind, title: String, plan: Int?, created: String) -> Share {
        Share(
            token: token, kind: kind, planID: plan, title: title, url: "https://voyager.example/share/\(token)",
            options: ShareOptions(), createdAt: created)
    }

    /// A list on fakes: a plan, a recap, the savings tally and one legacy plan link.
    private func prepare(empty: Bool = false, confirming: Bool = false) async -> (MySharesModel, AppEnvironment) {
        let fakes = FakeRepositories()
        if !empty {
            fakes.shares.onList.returns(
                ShareList(
                    shares: [
                        makeShare("plan0001abc", kind: .plan, title: "Lisbon in May", plan: 3, created: "2026-11-10T10:00:00Z"),
                        makeShare("recap001abc", kind: .recap, title: "Japan trip recap", plan: 4, created: "2026-10-28T09:30:00Z"),
                        makeShare("save0001abc", kind: .savings, title: "Price alerts", plan: nil, created: "2026-10-02T18:00:00Z"),
                    ],
                    legacyPlanShares: [LegacyPlanShare(planID: 9, name: "Rome long weekend", url: "https://voyager.example/share/legacy0009")]))
        }
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["sharing": .number(1)]))
        let model = MySharesModel(env: env, pasteboard: { _ in true }, track: { _ in })
        await model.load()
        if confirming, let first = model.shares.first { model.askRevoke(first) }
        return (model, env)
    }

    func test_list() async {
        let (model, env) = await prepare()
        await assertSnapshots(
            of: { MySharesView(model: model, env: env) }, named: "list",
            configs: [phone("se-light", height: 1430), phone("se-dark", dark: true, height: 1430)], layout: .screen)
    }

    func test_empty() async {
        let (model, env) = await prepare(empty: true)
        await assertSnapshots(
            of: { MySharesView(model: model, env: env) }, named: "empty", configs: [phone("se-light", height: 407)], layout: .screen)
    }

    func test_revokeConfirmation() async {
        let (model, env) = await prepare(confirming: true)
        await assertSnapshots(
            of: { MySharesView(model: model, env: env) }, named: "revoke", configs: [phone("se-light", height: 1422)], layout: .screen)
    }

    func test_hindi() async {
        let (model, env) = await prepare()
        await assertSnapshots(
            of: { MySharesView(model: model, env: env) }, named: "hi", configs: [phone("se-hi", language: .hi, height: 1430)], layout: .screen)
    }
}
