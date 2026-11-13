import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// Edit one watch's alert rule: any drop or below a target, nearby dates (fares), and email.
struct WatchEditor: View {
    let row: WatchRow
    let hasEmail: Bool
    let saving: Bool
    let onSave: (WatchEdit) -> Void
    let onCancel: () -> Void

    @State private var belowTarget: Bool
    @State private var targetText: String
    @State private var flexible: Bool
    @State private var email: Bool

    init(
        row: WatchRow, hasEmail: Bool, saving: Bool = false, onSave: @escaping (WatchEdit) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.row = row
        self.hasEmail = hasEmail
        self.saving = saving
        self.onSave = onSave
        self.onCancel = onCancel
        _belowTarget = State(initialValue: row.belowTarget)
        _targetText = State(initialValue: row.target.map { String(Int($0.rounded())) } ?? "")
        _flexible = State(initialValue: row.flexible)
        _email = State(initialValue: row.emailEnabled)
    }

    /// The typed target as a positive price, or nil when it is not one.
    static func parseTarget(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value.isFinite, value > 0, value < 10_000_000 else { return nil }
        return value
    }

    private var targetError: String? {
        guard belowTarget, Self.parseTarget(targetText) == nil else { return nil }
        return L10n.text(row.currency == "USD" ? K.alerts.target.errorUsd : K.alerts.target.errorPrice)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text(K.alerts.edit.tellMe)) {
                    modeRow(title: L10n.text(K.alerts.edit.whenDrops), selected: !belowTarget, tid: "alerts.edit-any-drop") {
                        belowTarget = false
                    }
                    modeRow(
                        title: L10n.text(K.alerts.edit.belowSymbol, ["symbol": symbol]), selected: belowTarget,
                        tid: "alerts.edit-below-target"
                    ) { belowTarget = true }
                    if belowTarget {
                        TextField(
                            L10n.text(K.alerts.edit.target, ["currency": row.currency]), text: $targetText
                        )
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityIdentifier("alerts.edit-target")
                        if let targetError {
                            Text(verbatim: targetError).font(VFont.body(.caption)).foregroundStyle(SemanticColor.destructive)
                        }
                    }
                }
                if row.supportsFlexible {
                    Section { Toggle(L10n.text(K.alerts.edit.nearby), isOn: $flexible).accessibilityIdentifier("alerts.edit-flexible") }
                }
                Section {
                    Toggle(L10n.text(K.alerts.edit.alsoEmail), isOn: $email)
                        .disabled(!hasEmail)
                        .accessibilityIdentifier("alerts.edit-email")
                    if !hasEmail {
                        Text(verbatim: L10n.text(K.alerts.edit.noEmailHint))
                            .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                    }
                }
            }
            .navigationTitle(L10n.text(K.alerts.edit.aria))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(K.alerts.ui.cancel), action: onCancel).accessibilityIdentifier("alerts.edit-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(K.alerts.ui.save)) {
                        onSave(
                            WatchEdit(
                                alertMode: belowTarget ? "below_target" : "any_drop",
                                target: belowTarget ? Self.parseTarget(targetText) : nil,
                                flexible: flexible, emailEnabled: email && hasEmail))
                    }
                    .disabled(saving || targetError != nil)
                    .accessibilityIdentifier("alerts.edit-save")
                }
            }
        }
    }

    private var symbol: String {
        let formatted = Fmt.currency(0, code: row.currency)
        return String(formatted.filter { !$0.isNumber && $0 != "." && $0 != "," && !$0.isWhitespace })
    }

    private func modeRow(title: String, selected: Bool, tid: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title).foregroundStyle(SemanticColor.text)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(SemanticColor.primary).accessibilityHidden(true) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(tid)
    }
}
