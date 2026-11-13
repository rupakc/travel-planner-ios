import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Tolerant readers over LLM output used by every destination-info section.
enum Info {
    /// A trimmed, non-empty string, else nil. Numbers are shown as their plain text.
    static func text(_ value: JSONValue) -> String? {
        switch value {
        case .string(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .number(let number):
            return number.rounded() == number ? String(Int(number)) : String(number)
        default:
            return nil
        }
    }

    /// The non-empty strings of an array.
    static func texts(_ value: JSONValue) -> [String] {
        (value.array ?? []).compactMap { text($0) }
    }

    /// The object elements of the array under `key`.
    static func list(_ data: JSONValue, _ key: String) -> [JSONValue] {
        (data[key].array ?? []).filter { $0.object != nil }
    }

    /// An `https` URL with a host, else nil.
    static func httpsURL(_ value: JSONValue) -> URL? {
        guard let raw = value.string else { return nil }
        return SectionItem.httpsURL(raw)
    }

    /// `YYYY-MM-DD` as a short localized date; any other text is returned unchanged.
    static func shortDate(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(raw.prefix(10))) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = LanguageController.current.intlLocale
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }
}

/// A "Label: value" line; renders nothing when the value is missing.
struct InfoLine: View {
    let label: String?
    let value: String?

    var body: some View {
        if let value {
            if let label {
                Text(verbatim: label + " " + value)
                    .font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: value)
                    .font(VFont.body(.footnote))
                    .foregroundStyle(SemanticColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A small heading above a block of lines.
struct InfoHeading: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(VFont.body(.subheadline, weight: .semibold))
            .foregroundStyle(SemanticColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A bulleted list of plain strings.
struct InfoBullets: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text(verbatim: "•").foregroundStyle(SemanticColor.textMuted)
                    Text(verbatim: item)
                        .font(VFont.body(.footnote))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A small tinted tag.
struct InfoTag: View {
    let title: String
    var family: Family = .gray

    var body: some View {
        Text(verbatim: title)
            .font(VFont.body(.caption, weight: .medium))
            .foregroundStyle(Palette.color(family, .s700))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Palette.color(family, .s100), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Add to Plan" / "In Plan" toggle for a list item (`field` is the `selections` key).
struct PlanToggle: View {
    let field: String
    let item: JSONValue
    let ctx: SectionContext

    var body: some View {
        let selected = ctx.isSelected(field, item)
        VChip(
            title: L10n.text(selected ? K.results.plan.inPlan : K.results.plan.add),
            tid: "results.select.\(field)", selected: selected
        ) { ctx.toggle(field, item) }
    }
}

/// A link-out button: opens the provider page through the host (`https` only).
struct InfoLink: View {
    let title: String
    let url: URL?
    let section: String
    let ctx: SectionContext

    var body: some View {
        if let url {
            Button {
                ctx.openURL(url, section)
            } label: {
                Label {
                    Text(verbatim: title).font(VFont.body(.footnote, weight: .medium))
                } icon: {
                    Image(systemName: "arrow.up.right.square").accessibilityHidden(true)
                }
                .foregroundStyle(SemanticColor.primary)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("results.link.\(section)")
        }
    }
}

/// The empty-state line.
struct InfoEmpty: View {
    let key: LKey

    var body: some View {
        Text(verbatim: L10n.text(key))
            .font(VFont.body(.subheadline))
            .foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A bold lead-in line above a bullet list.
struct InfoLabel: View {
    let title: String

    var body: some View {
        Text(verbatim: title)
            .font(VFont.body(.footnote, weight: .semibold))
            .foregroundStyle(SemanticColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
