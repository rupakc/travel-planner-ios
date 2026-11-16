import DesignSystem
import L10n
import SharedUI
import SwiftUI
import Telemetry
import VoyagerModel

/// Report an idea or comment: the seven contract reasons, an optional note, thanks when sent. The owner's support
/// contact is offered here too.
struct ReportSheetView: View {
    @Bindable var model: ReportModel
    var supportURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if model.phase == .sent {
                        Text(verbatim: L10n.text(K.social.report.sent))
                            .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("report.sent")
                    } else {
                        form
                    }
                    SupportRow(url: supportURL)
                }
                .frame(maxWidth: AdaptiveLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg)
            }
            .background(SemanticColor.surface)
            .navigationTitle(L10n.text(K.social.report.title))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(K.social.actions.close)) { dismiss() }.accessibilityIdentifier("report.close")
                }
            }
        }
        .telemetryRoute("/feed/report")
        .accessibilityIdentifier("report.sheet")
    }

    @ViewBuilder private var form: some View {
        Text(verbatim: L10n.text(K.social.report.intro))
            .font(VFont.body(.subheadline)).foregroundStyle(SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
        Text(verbatim: L10n.text(K.social.report.reasonLabel))
            .font(VFont.body(.subheadline, weight: .semibold)).foregroundStyle(SemanticColor.text)
            .accessibilityAddTraits(.isHeader)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ReportReason.allCases, id: \.self) { reason in reasonRow(reason) }
        }
        Text(verbatim: L10n.text(K.social.report.noteLabel))
            .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.textMuted)
        TextField("", text: $model.note, axis: .vertical)
            .lineLimit(2...4)
            .font(VFont.body(.subheadline))
            .padding(Spacing.sm)
            .borderedSurface(
                    RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
            .accessibilityLabel(Text(verbatim: L10n.text(K.social.report.noteLabel)))
            .accessibilityIdentifier("report.note")
        if case .failed(let failure) = model.phase {
            Text(verbatim: failure.message)
                .font(VFont.body(.footnote)).foregroundStyle(SemanticColor.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("report.error")
        }
        VButton(L10n.text(K.social.report.submit), tid: "report.submit") { Task { await model.submit() } }
            .disabled(!model.canSubmit)
    }

    private func reasonRow(_ reason: ReportReason) -> some View {
        let selected = model.reason == reason
        return Button {
            model.reason = reason
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? SemanticColor.primary : SemanticColor.textMuted)
                    .accessibilityHidden(true)
                Text(verbatim: Self.title(reason))
                    .font(VFont.body(.body)).foregroundStyle(SemanticColor.text)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("report.reason.\(reason.rawValue)")
    }

    static func title(_ reason: ReportReason) -> String {
        switch reason {
        case .spam: L10n.text(K.social.report.reason.spam)
        case .abuse: L10n.text(K.social.report.reason.abuse)
        case .sexual: L10n.text(K.social.report.reason.sexual)
        case .violence: L10n.text(K.social.report.reason.violence)
        case .misinformation: L10n.text(K.social.report.reason.misinformation)
        case .other: L10n.text(K.social.report.reason.other)
        }
    }
}
