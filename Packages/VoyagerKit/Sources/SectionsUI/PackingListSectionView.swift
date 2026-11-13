import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The packing list (api-contract 3.4.15): categories with tick-off items, the user's own items, and
/// "Save to Plan". Checked items live in `selections.packing_list.checked_items` once saved, as on the web;
/// while the list is saved every change is written straight back.
public struct PackingListSectionView: View {
    let data: JSONValue
    let ctx: SectionContext
    @State private var checked: Set<String>
    @State private var custom: [String: [String]]
    @State private var drafts: [String: String] = [:]

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
        _checked = State(initialValue: PackingState.checked(in: data))
        _custom = State(initialValue: PackingState.custom(in: data))
    }

    private var payload: JSONValue { PackingState.payload(data: data, checked: checked, custom: custom) }

    private func persistIfSaved() {
        if ctx.isSelected("packing_list", data) { ctx.toggle("packing_list", payload) }
    }

    public var body: some View {
        let categories = Info.list(data, "categories")
        if categories.isEmpty {
            InfoEmpty(key: K.sections.packing.unavailable)
        } else {
            let total = (Info.clampedInt(data["total_items"].double) ?? 0) + custom.values.reduce(0) { $0 + $1.count }
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text(
                        verbatim: L10n.text(
                            K.sections.packing.itemsPacked, ["checked": String(checked.count), "total": String(total)])
                    )
                    .font(VFont.body(.footnote, weight: .medium))
                    .foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.sm)
                    saveButton
                }
                InfoLine(label: nil, value: Info.text(data["luggage_note"]))
                ForEach(Array(categories.enumerated()), id: \.offset) { _, category in categoryView(category) }
                Text(verbatim: L10n.text(K.sections.packing.essentialLegend))
                    .font(VFont.body(.caption))
                    .foregroundStyle(SemanticColor.textMuted)
            }
        }
    }

    private var saveButton: some View {
        let saved = ctx.isSelected("packing_list", data)
        return VChip(
            title: L10n.text(saved ? K.sections.packing.savedRemove : K.sections.packing.save),
            tid: "results.packing.save", selected: saved
        ) { ctx.toggle("packing_list", saved ? .null : payload) }
    }

    private func categoryView(_ category: JSONValue) -> some View {
        let name = Info.text(category["name"]) ?? ""
        let items = Info.list(category, "items")
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            InfoHeading(title: [Info.text(category["icon"]), name].compactMap { $0 }.joined(separator: " "))
            InfoLine(label: nil, value: Info.text(category["weather_note"]))
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                row(category: name, title: Info.text(item["item"]) ?? "", essential: item["essential"].bool == true,
                    note: Info.text(item["note"]))
            }
            ForEach(Array((custom[name] ?? []).enumerated()), id: \.offset) { _, own in
                row(category: name, title: own, essential: false, note: nil)
            }
            addField(category: name)
        }
    }

    private func row(category: String, title: String, essential: Bool, note: String?) -> some View {
        let key = PackingState.key(category: category, item: title)
        let on = checked.contains(key)
        return Button {
            if on { checked.remove(key) } else { checked.insert(key) }
            persistIfSaved()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? SemanticColor.primary : SemanticColor.textMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title + (essential ? " *" : ""))
                        .font(VFont.body(.subheadline))
                        .strikethrough(on)
                        .foregroundStyle(on ? SemanticColor.textMuted : SemanticColor.text)
                        .multilineTextAlignment(.leading)
                    if let note {
                        Text(verbatim: note).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("results.packing.item")
    }

    private func addField(category: String) -> some View {
        HStack(spacing: Spacing.sm) {
            TextField(
                L10n.text(K.sections.packing.addItem),
                text: Binding(get: { drafts[category] ?? "" }, set: { drafts[category] = $0 })
            )
            .font(VFont.body(.subheadline))
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .onSubmit { addItem(category: category) }
            .accessibilityIdentifier("results.packing.add")
        }
    }

    private func addItem(category: String) {
        let value = (drafts[category] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        custom[category, default: []].append(value)
        drafts[category] = ""
        persistIfSaved()
    }
}
