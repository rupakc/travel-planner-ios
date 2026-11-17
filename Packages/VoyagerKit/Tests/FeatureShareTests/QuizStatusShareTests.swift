import Foundation
import Networking
import Testing
import TestSupport
import VoyagerEnv
import VoyagerModel

@testable import FeatureShare

/// Quiz and status shares reuse the Phase 4 flow (R15): the request carries `session_id` or `plan_id`, and the sharer's
/// name stays hidden unless they turn `show_name` on.
@MainActor
struct QuizStatusShareTests {
    private func made(_ kind: ShareKind) -> Share {
        Share(
            token: "tok1", kind: kind, planID: 3, url: "https://fake.voyager.test/share/tok1",
            cardLinkURL: nil, cardStoryURL: nil, options: ShareOptions())
    }

    private func rig(_ target: ShareTarget, kind: ShareKind) -> (ShareSheetModel, FakeRepositories) {
        let fakes = FakeRepositories()
        fakes.shares.onCreate.returns(made(kind))
        let env = AppEnvironment.fake(fakes: fakes, clientConfig: ClientConfig(features: ["sharing": .number(1)]))
        let model = ShareSheetModel(env: env, target: target, loader: FakeShareCardLoader(), track: { _ in })
        return (model, fakes)
    }

    private func body(_ request: ShareRequest?) throws -> JSONValue {
        let request = try #require(request)
        return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(request))
    }

    @Test func test_quizShareSendsSessionID() async throws {
        let (model, fakes) = rig(.quiz(sessionID: "sess-42"), kind: .quiz)
        await model.create()
        let json = try body(fakes.shares.onCreate.lastCall)
        #expect(json["kind"].string == "quiz" && json["session_id"].string == "sess-42")
        #expect(json["plan_id"].isNull)
        #expect(!model.showsOptions)
    }

    @Test func test_statusShareSendsPlanID() async throws {
        let (model, fakes) = rig(.status(planID: 7), kind: .status)
        await model.create()
        let json = try body(fakes.shares.onCreate.lastCall)
        #expect(json["kind"].string == "status" && json["plan_id"].int == 7)
        #expect(json["session_id"].isNull)
    }

    @Test func test_nameHiddenUnlessShowName() async throws {
        for target in [ShareTarget.quiz(sessionID: "s"), .status(planID: 7)] {
            let kind = target.kind
            let (model, fakes) = rig(target, kind: kind)
            await model.create()
            let hidden = try body(fakes.shares.onCreate.lastCall)
            #expect(hidden["options"]["show_name"].bool == false)
        }
        // A status share can turn it on in the sheet; the request then says so.
        let (model, fakes) = rig(.status(planID: 7), kind: .status)
        model.options.showName = true
        await model.create()
        #expect(try body(fakes.shares.onCreate.lastCall)["options"]["show_name"].bool == true)
    }
}
