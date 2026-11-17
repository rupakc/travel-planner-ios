import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Report a profile: a reason, an optional note, send.
struct ProfileReportView: View {
    @State private var model: ProfileReportModel
    let dismiss: () -> Void

    @MainActor init(model: ProfileReportModel, dismiss: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.dismiss = dismiss
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if model.phase == .sent {
                    EmptyState(icon: "checkmark.circle", title: L10n.text(K.social.report.sent))
                    VButton(L10n.text(K.social.actions.close), tid: "report.close", action: dismiss)
                } else {
                    form
                }
            }
            .padding(Spacing.lg)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(SemanticColor.surface)
        .accessibilityIdentifier("report.sheet")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(verbatim: L10n.text(K.social.report.title)).font(VFont.display(.title3)).foregroundStyle(SemanticColor.text)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: L10n.text(K.social.report.intro)).font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: L10n.text(K.social.report.reasonLabel)).font(VFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(SemanticColor.text)
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button { model.reason = reason } label: {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: model.reason == reason ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(SemanticColor.primary).accessibilityHidden(true)
                        Text(verbatim: ProfileReportModel.title(for: reason)).font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.reason == reason ? .isSelected : [])
                .accessibilityIdentifier("report.reason.\(reason.rawValue)")
            }
            Text(verbatim: L10n.text(K.social.report.noteLabel)).font(VFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(SemanticColor.text)
            TextField(
                L10n.text(K.social.report.noteLabel), text: Binding(get: { model.note }, set: { model.setNote($0) }), axis: .vertical
            )
            .lineLimit(3...6)
            .themedTextField()
            .accessibilityIdentifier("report.note")
            if case .failed(let message) = model.phase {
                Text(verbatim: message).font(VFont.body(.footnote, weight: .semibold)).foregroundStyle(SemanticColor.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ActionPair {
                VButton(L10n.text(K.social.actions.cancel), tid: "report.cancel", role: .secondary, action: dismiss)
            } second: {
                VButton(L10n.text(K.social.report.submit), tid: "report.send") { Task { await model.send() } }
                    .disabled(model.phase == .sending)
            }
        }
    }
}
