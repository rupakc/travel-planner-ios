import SnapshotTesting
import SwiftUI
import TestSupport
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeatureChat

@MainActor
final class ChatSnapshotTests: XCTestCase {
    private let configs: [SnapshotConfig] = [.phoneLight, .phoneDark, .padLight]

    private func turn(_ name: String) -> ChatMessageState {
        var turn = ChatTurn()
        for json in Fixtures.sse(name) { _ = ChatReducer.reduce(&turn, ChatStreamEvent(json: json)) }
        return turn.message
    }

    private func screen(_ messages: [ChatMessageState], threads: Bool = false) -> some View {
        let env = AppEnvironment.fake()
        if threads {
            env.chatThreads.update(UUID()) { $0.title = "Visa for Thailand" }
            env.chatThreads.update(UUID()) { $0.title = "Plan a week in Tokyo" }
        }
        let model = ChatModel(env: env, track: { _ in })
        model.load(messages)
        return NavigationStack { ChatRootView(env: env, model: model) }
            .environment(\.chatShowsMap, false)
    }

    func test_empty() async {
        await assertSnapshots(of: { screen([]) }, named: "empty", configs: configs, layout: .screen)
    }

    func test_qa() async {
        var answer = turn("chat_qa")
        answer.failed = false
        let messages = [ChatMessageState(id: "u1", role: .user, content: "Do I need a visa for Thailand?"), answer]
        await assertSnapshots(of: { screen(messages, threads: true) }, named: "qa", configs: configs, layout: .screen)
    }

    func test_planning() async {
        var plan = turn("chat_planning")
        plan.id = "a1"
        let messages = [ChatMessageState(id: "u1", role: .user, content: "Plan 5 days in Tokyo"), plan]
        await assertSnapshots(of: { screen(messages) }, named: "planning", configs: configs, layout: .screen)
    }

    func test_planningInProgress() async {
        let plan = ChatMessageState(id: "a1", role: .assistant, planning: PlanningState(destination: "Tokyo", generating: true))
        let messages = [ChatMessageState(id: "u1", role: .user, content: "Plan 5 days in Tokyo"), plan]
        await assertSnapshots(of: { screen(messages) }, named: "planning-progress", configs: [.phoneLight], layout: .screen)
    }

    func test_sectionCard() async {
        var answer = turn("chat_fallback")
        answer.id = "a1"
        answer.content = "Here are hotels in Tokyo."
        answer.failed = false
        answer.importURL = nil
        answer.planning = nil
        answer.suggestions = []
        let messages = [ChatMessageState(id: "u1", role: .user, content: "Show me hotels in Tokyo"), answer]
        await assertSnapshots(of: { screen(messages) }, named: "section", configs: configs, layout: .screen)
    }
}
