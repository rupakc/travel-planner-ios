import DesignSystem
import L10n
import SectionsUI
import SharedUI
import SwiftUI
import VoyagerModel

/// One message: the user's bubble, or the assistant's text with its specialist cards and planning card.
struct MessageBubble: View {
    let message: ChatMessageState
    let isLast: Bool
    let isStreaming: Bool
    let ctx: SectionContext
    let onSuggestion: (String) -> Void
    let onImport: (String) -> Void
    let onRetry: () -> Void
    @State private var collapsed: Set<String> = []

    var body: some View {
        if message.role == .user { userBubble } else { assistantBubble }
    }

    private var userBubble: some View {
        HStack(spacing: 0) {
            Spacer(minLength: Spacing.xxl)
            Text(verbatim: message.content)
                .font(VFont.body(.body))
                .foregroundStyle(SemanticColor.onPrimary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(SemanticColor.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.largeCard))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.message.user")
    }

    private var streamingThis: Bool { isLast && isStreaming }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if message.content.isEmpty, message.planning == nil, message.sections.isEmpty {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text(verbatim: L10n.text(K.chat.bubble.planning))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                }
            }
            if !message.content.isEmpty {
                MarkdownText(text: message.content, finished: !streamingThis)
            }
            if let planning = message.planning { PlanningCard(planning: planning, ctx: ctx) }
            ForEach(message.sections.compactMap(sectionEntry), id: \.0.rawValue) { id, section in
                SectionCard(
                    id: id, status: section.failed ? .error("") : SectionStatus(source: section.source.map(\.rawValue)),
                    expanded: expandedBinding(id)
                ) {
                    SectionRegistry.view(for: id, data: section.data, ctx: ctx)
                }
            }
            ForEach(message.loadingAgents, id: \.self) { agent in
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                    Text(verbatim: L10n.text(K.chat.section.searching, ["what": Self.agentLabel(agent)]))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                }
            }
            if let url = message.importURL {
                VButton(L10n.text(K.chat.page.planFromLink), tid: "chat.importLink", role: .secondary, systemImage: "link") {
                    onImport(url)
                }
            }
            if message.failed, isLast, !isStreaming {
                VButton(
                    L10n.text(K.chat.action.retry), tid: "chat.retry", role: .secondary, systemImage: "arrow.clockwise",
                    action: onRetry)
            }
            if isLast, !isStreaming { SuggestionChips(chips: message.suggestions, onTap: onSuggestion) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("chat.message.assistant")
    }

    private func sectionEntry(_ section: ChatSection) -> (SectionID, ChatSection)? {
        SectionID(rawValue: section.id).map { ($0, section) }
    }

    private func expandedBinding(_ id: SectionID) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(id.rawValue) },
            set: { if $0 { collapsed.remove(id.rawValue) } else { collapsed.insert(id.rawValue) } })
    }

    static func agentLabel(_ agent: String) -> String {
        switch agent {
        case "activities": L10n.text(K.chat.agent.activities)
        case "flights": L10n.text(K.chat.agent.flights)
        case "forex": L10n.text(K.chat.agent.forex)
        case "getting_around", "getting-around": L10n.text(K.chat.agent.getting_around)
        case "hotels": L10n.text(K.chat.agent.hotels)
        case "itinerary": L10n.text(K.chat.agent.itinerary)
        case "sim": L10n.text(K.chat.agent.sim)
        case "tips": L10n.text(K.chat.agent.tips)
        case "visa": L10n.text(K.chat.agent.visa)
        default: agent
        }
    }
}
