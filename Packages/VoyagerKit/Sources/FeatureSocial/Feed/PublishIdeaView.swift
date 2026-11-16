import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv
import VoyagerModel

/// "Share to Ideas" (`Route.publishIdea`): title and caption, then publish. Plain text only; the sheet says what is
/// never included.
public struct PublishIdeaView: View {
    @State private var model: PublishIdeaModel
    @Environment(\.dismiss) private var dismiss

    @MainActor public init(env: AppEnvironment, planID: Int, kind: IdeaKind, suggestedTitle: String = "") {
        _model = State(initialValue: PublishIdeaModel(env: env, planID: planID, kind: kind, suggestedTitle: suggestedTitle))
    }

    @MainActor init(model: PublishIdeaModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if model.isDone { done } else { form }
                }
                .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
            }
            .background(SemanticColor.surface)
            .navigationTitle(L10n.text(model.kind == .recap ? K.socialShare.titleRecap : K.socialShare.title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(model.isDone ? K.socialShare.close : K.socialShare.cancel)) { dismiss() }
                        .accessibilityIdentifier("publish.close")
                }
            }
        }
        .telemetryRoute("/feed/new")
        .task { await model.checkProfile() }
        .accessibilityIdentifier("publish.sheet")
    }

    @ViewBuilder private var done: some View {
        Text(verbatim: L10n.text(model.phase == .held ? K.socialShare.held : K.socialShare.done))
            .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(model.phase == .held ? "publish.held" : "publish.done")
        VButton(L10n.text(K.socialShare.viewFeed), tid: "publish.view-feed", role: .secondary) {
            model.openFeed()
            dismiss()
        }
    }

    @ViewBuilder private var form: some View {
        Text(verbatim: L10n.text(K.socialShare.intro))
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
        profileNotice
        field(
            L10n.text(K.socialShare.titleLabel), text: $model.title, lines: 1...3, count: model.title.count,
            max: IdeaDraft.maxTitle, tid: "publish.title")
        field(
            L10n.text(K.socialShare.captionLabel), text: $model.caption, lines: 3...8, count: model.caption.count,
            max: IdeaDraft.maxCaption, tid: "publish.caption")
        Text(verbatim: L10n.text(K.socialShare.plainNote))
            .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        if case .failed(let failure) = model.phase {
            Text(verbatim: failure.message)
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("publish.error")
        }
        if model.needsProfileEditor {
            VButton(L10n.text(model.profile == .private ? K.socialShare.editProfile : K.socialShare.createProfile),
                tid: "publish.profile", role: .secondary) {
                model.openEditor()
                dismiss()
            }
        }
        VButton(L10n.text(model.phase == .sending ? K.socialShare.publishing : K.socialShare.submit), tid: "publish.submit") {
            Task { await model.submit() }
        }
        .disabled(!model.canSubmit)
    }

    @ViewBuilder private var profileNotice: some View {
        switch model.profile {
        case .missing:
            note(L10n.text(K.socialShare.needProfile), tid: "publish.need-profile")
        case .private:
            note(L10n.text(K.socialShare.profilePrivate), tid: "publish.profile-private")
        case .unknown, .ready:
            EmptyView()
        }
    }

    private func note(_ text: String, tid: String) -> some View {
        Text(verbatim: text)
            .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(tid)
    }

    private func field(_ label: String, text: Binding<String>, lines: ClosedRange<Int>, count: Int, max: Int, tid: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(verbatim: label).font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
            TextField("", text: text, axis: .vertical)
                .lineLimit(lines)
                .font(VFont.body(.subheadline))
                .padding(Spacing.sm)
                .borderedSurface(RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityIdentifier(tid)
            Text(verbatim: L10n.text(K.socialShare.counter, ["n": String(count), "max": String(max)]))
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
        }
    }
}
