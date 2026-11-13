import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerEnv

/// Rating, category and message, sent to `POST /api/feedback`.
struct FeedbackSheet: View {
    @State private var model: FeedbackModel
    let dismiss: () -> Void

    @MainActor init(env: AppEnvironment, dismiss: @escaping () -> Void) {
        _model = State(initialValue: FeedbackModel(env: env))
        self.dismiss = dismiss
    }

    @MainActor init(model: FeedbackModel, dismiss: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.dismiss = dismiss
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if model.sent {
                    EmptyState(
                        icon: "heart", title: L10n.text(K.misc.feedback.thanks), message: L10n.text(K.misc.feedback.thanksBody))
                    VButton(L10n.text(K.misc.feedback.close), tid: "feedback.close", action: dismiss)
                } else {
                    form
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        .accessibilityIdentifier("feedback.sheet")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: L10n.text(K.misc.feedback.triggerTitle))
                .font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
            Text(verbatim: L10n.text(K.misc.feedback.rate))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            HStack(spacing: Spacing.sm) {
                ForEach(1...5, id: \.self) { star in
                    Button { model.rating = star } label: {
                        Image(systemName: star <= model.rating ? "star.fill" : "star")
                            .font(.title2).foregroundStyle(SemanticColor.accent)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text(K.misc.feedback.star, count: star))
                    .accessibilityIdentifier("feedback.star.\(star)")
                }
            }
            Text(verbatim: L10n.text(K.misc.feedback.category))
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            WrapLayout(spacing: Spacing.sm) {
                ForEach(FeedbackModel.categories, id: \.self) { id in
                    VChip(title: Self.categoryTitle(id), tid: "feedback.cat.\(id)", selected: model.category == id) {
                        model.category = id
                    }
                }
            }
            Text(verbatim: "\(L10n.text(K.misc.feedback.message)) (\(L10n.text(K.misc.feedback.optional)))")
                .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
            TextField(
                L10n.text(K.misc.feedback.placeholder),
                text: Binding(get: { model.message }, set: { model.updateMessage($0) }), axis: .vertical
            )
            .lineLimit(4...8)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("feedback.message")
            Text(verbatim: "\(model.message.count)/\(FeedbackModel.maxMessage)")
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if let error = model.error {
                Text(verbatim: ErrorCopy.message(kind: error.presentationKind, detail: error.userFacingDetail))
                    .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
            }
            HStack(spacing: Spacing.md) {
                VButton(L10n.text(K.misc.feedback.close), tid: "feedback.cancel", role: .secondary, action: dismiss)
                VButton(
                    model.sending ? L10n.text(K.misc.feedback.sending) : L10n.text(K.misc.feedback.send), tid: "feedback.send"
                ) { Task { await model.send() } }
                .disabled(!model.canSend)
            }
        }
    }

    static func categoryTitle(_ id: String) -> String {
        switch id {
        case "bug": L10n.text(K.misc.feedback.cat.bug)
        case "feature_request": L10n.text(K.misc.feedback.cat.feature_request)
        case "praise": L10n.text(K.misc.feedback.cat.praise)
        default: L10n.text(K.misc.feedback.cat.general)
        }
    }
}
