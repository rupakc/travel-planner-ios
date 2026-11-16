import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerEnv
import VoyagerModel

/// A quiz (`router.open(.quiz(sessionID:))`): one question at a time, then the result. A started session is resumed at its
/// first unanswered question. Nothing here animates: the countdown is plain text, so Reduce Motion needs no special case.
public struct QuizView: View {
    @State private var model: QuizModel
    @Environment(\.dismiss) private var dismiss

    @MainActor public init(env: AppEnvironment, sessionID: String) {
        _model = State(initialValue: QuizModel(env: env, sessionID: sessionID))
    }

    @MainActor init(model: QuizModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) { content }
                .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
        }
        .background(SemanticColor.surface)
        .navigationTitle(Text(verbatim: L10n.text(K.playYou.page.title)))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
        .onDisappear { model.stopTimer() }
        .accessibilityIdentifier("play.quiz")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView { Text(verbatim: L10n.text(K.play.loading)) }
                .frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
        case .unavailable:
            EmptyState(icon: "gamecontroller", title: L10n.text(K.play.home.unavailable))
            backButton
        case .failed(let message, let retryable):
            Text(verbatim: message).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.quiz.failed")
            if retryable {
                VButton(L10n.text(K.social.feed.retry), tid: "play.quiz.retry", role: .secondary) { Task { await model.load() } }
            }
            backButton
        case .question:
            if let question = model.question { questionCard(question) }
        case .summary:
            summaryCard
        }
    }

    private var backButton: some View {
        VButton(L10n.text(K.play.result.back), tid: "play.quiz.back", role: .secondary) { dismiss() }
    }

    // MARK: Question

    @ViewBuilder private func questionCard(_ question: PlayQuestion) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        progress
                        Spacer(minLength: Spacing.sm)
                        timer
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        progress
                        timer
                    }
                }
                if question.isSupported {
                    if let flag = QuizText.flag(question) {
                        Text(verbatim: flag).font(.system(size: 72)).frame(maxWidth: .infinity)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .accessibilityElement().accessibilityLabel(Text(verbatim: L10n.text(K.play.quiz.flagAlt)))
                            .accessibilityIdentifier("play.quiz.flag")
                    }
                    Text(verbatim: QuizText.prompt(question) ?? "")
                        .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("play.quiz.prompt")
                    VStack(spacing: Spacing.sm) {
                        ForEach(question.options) { option in
                            OptionButton(
                                label: QuizText.optionLabel(option), tid: "play.quiz.option.\(option.id)",
                                style: style(for: option), disabled: model.busy || model.result != nil
                            ) { Task { await model.pick(option) } }
                        }
                    }
                    feedback
                } else {
                    Text(verbatim: L10n.text(K.mobile.unsupported.update)).font(VFont.body(.body))
                        .foregroundStyle(SemanticColor.text).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("play.quiz.unsupported")
                    backButton
                }
            }
        }
    }

    private var progress: some View {
        Text(verbatim: model.progressText).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            .accessibilityIdentifier("play.quiz.progress")
    }

    private var timer: some View {
        Text(verbatim: model.timerText).font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            .monospacedDigit().accessibilityIdentifier("play.quiz.timer")
    }

    private func style(for option: PlayOption) -> OptionStyle {
        guard let result = model.result else { return model.selected == option.id && model.busy ? .pending : .plain }
        if option.id == result.correctChoice { return .right }
        if option.id == model.selected { return .wrong }
        return .plain
    }

    @ViewBuilder private var feedback: some View {
        if let error = model.errorText {
            Text(verbatim: error).font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.quiz.error")
        }
        if let result = model.result {
            Text(verbatim: result.correct ? L10n.text(K.play.quiz.correctPoints, count: result.points) : L10n.text(K.play.quiz.wrongNote))
                .font(VFont.body(.body, weight: .semibold)).foregroundStyle(SemanticColor.text)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("play.quiz.reveal")
            VButton(
                model.isLast ? L10n.text(K.play.quiz.finish) : L10n.text(K.play.quiz.next), tid: "play.quiz.next"
            ) { model.next() }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(verbatim: L10n.text(K.play.result.title)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: String(model.summary?.score ?? 0)).font(VFont.display(.largeTitle))
                    .foregroundStyle(SemanticColor.primary).accessibilityIdentifier("play.result.score")
                Text(
                    verbatim: L10n.text(
                        K.play.result.correct,
                        ["correct": String(model.summary?.correct ?? 0), "total": String(model.summary?.total ?? 5)])
                )
                .font(VFont.body(.body)).foregroundStyle(SemanticColor.text).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("play.result.correct")
                if model.xpEarned > 0 {
                    Text(verbatim: L10n.text(K.play.result.xp, count: model.xpEarned))
                        .font(VFont.body(.body, weight: .semibold)).foregroundStyle(SemanticColor.primary)
                        .accessibilityIdentifier("play.result.xp")
                }
                if let streak = model.summary?.streak, streak.current > 0 {
                    Text(verbatim: L10n.text(K.play.result.streak, count: streak.current))
                        .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                        .accessibilityIdentifier("play.result.streak")
                }
                backButton
            }
        }
    }
}

enum OptionStyle: Equatable {
    case plain, pending, right, wrong
}

/// One answer: a large option (56 pt minimum). The reveal shows a check or a cross as well as a colour.
private struct OptionButton: View {
    let label: String
    let tid: String
    let style: OptionStyle
    let disabled: Bool
    let action: () -> Void
    @Environment(\.telemetryRoute) private var route

    var body: some View {
        Button {
            Telemetry.shared.track(.uiTap(tid: tid, route: route))
            action()
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(verbatim: label).font(VFont.body(.body, weight: .semibold)).foregroundStyle(SemanticColor.text)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm)
                if let symbol {
                    Image(systemName: symbol).font(.body.weight(.bold)).foregroundStyle(tint).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
            .borderedSurface(RoundedRectangle(cornerRadius: Radius.itemCard), fill: fill, border: tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `.disabled`: the system would dim the revealed answers. Taps are ignored while an answer is in flight or shown.
        .allowsHitTesting(!disabled)
        .accessibilityLabel(Text(verbatim: spoken))
        .accessibilityIdentifier(tid)
    }

    private var symbol: String? {
        switch style {
        case .right: "checkmark.circle.fill"
        case .wrong: "xmark.circle.fill"
        default: nil
        }
    }

    private var tint: Color {
        switch style {
        case .right: Palette.color(.green, .s600)
        case .wrong: SemanticColor.destructive
        case .pending: SemanticColor.primary
        case .plain: SemanticColor.border
        }
    }

    private var fill: Color {
        switch style {
        case .right: Palette.color(.green, .s100)
        case .wrong: Palette.color(.red, .s100)
        default: SemanticColor.surfaceRaised
        }
    }

    /// The label plus, after the reveal, "Correct answer" or "Your answer, incorrect" for VoiceOver.
    private var spoken: String {
        switch style {
        case .right: label + ". " + L10n.text(K.play.quiz.correct)
        case .wrong: label + ". " + L10n.text(K.play.quiz.wrong)
        default: label
        }
    }
}
