import DesignSystem
import L10n
import SharedUI
import SwiftUI

/// Names the plan and saves it (creates it, or updates the saved one).
struct SaveSheet: View {
    let model: MyPlanModel
    @State private var name: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    init(model: MyPlanModel) {
        self.model = model
        _name = State(initialValue: model.defaultName)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                TextField(L10n.text(K.plan.modal.namePlaceholder), text: $name)
                    .font(VFont.body(.body))
                    .textFieldStyle(.plain)
                    .foregroundStyle(SemanticColor.text)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 44)
                    .borderedSurface(
                        RoundedRectangle(cornerRadius: Radius.input), fill: SemanticColor.surfaceRaised, border: SemanticColor.border)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { Task { await save() } }
                    .accessibilityIdentifier("plan.save.name")
                PlanActionButton(title: L10n.text(K.plan.modal.save), systemImage: "square.and.arrow.down", tid: "plan.save.confirm") {
                    Task { await save() }
                }
                .disabled(model.isSaving)
                Spacer(minLength: 0)
            }
            .padding(Spacing.lg)
            .background(SemanticColor.surface)
            .navigationTitle(L10n.text(K.plan.modal.save))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(K.plan.modal.close)) { dismiss() }
                        .tint(SemanticColor.primary)
                        .accessibilityIdentifier("plan.save.close")
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }

    private func save() async {
        if await model.save(name: name) { dismiss() }
    }
}
