import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The emergency card (api-contract 3.4.11): numbers, embassy, hospitals, phrases, laws. Multi-city data
/// (`cities[]`) shows one card per city. "Save for offline" renders each card to a PDF in
/// `Application Support/offline/`.
public struct EmergencyCardSectionView: View {
    let data: JSONValue
    let ctx: SectionContext
    @State private var saved = false

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        let entries = EmergencyCards.entries(from: data)
        if entries.isEmpty {
            InfoEmpty(key: K.sections.emergency.unavailable)
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    EmergencyCardBody(entry: entry)
                }
                Text(verbatim: L10n.text(K.results.emergency.disclaimer))
                    .font(VFont.body(.caption))
                    .foregroundStyle(SemanticColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    saved = EmergencyOffline.save(entries: entries) != nil
                } label: {
                    Label {
                        Text(verbatim: L10n.text(K.sections.emergency.printableOffline))
                            .font(VFont.body(.footnote, weight: .medium))
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: saved ? "checkmark.circle.fill" : "arrow.down.doc").accessibilityHidden(true)
                    }
                    .foregroundStyle(SemanticColor.primary)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("results.emergency.saveOffline")
            }
        }
    }
}

/// One card's content, also the page rendered into the offline PDF.
struct EmergencyCardBody: View {
    let entry: EmergencyCardEntry

    var body: some View {
        let data = entry.data
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let city = entry.city {
                    Text(verbatim: L10n.text(K.results.emergency.cardTitle, ["title": city]))
                        .font(VFont.body(.headline, weight: .semibold))
                        .foregroundStyle(SemanticColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                numbers(data["emergency_numbers"])
                embassy(data["embassy"])
                hospitals(Info.list(data, "hospitals"))
                phrases(Info.list(data, "local_phrases"))
                laws(Info.list(data, "local_laws"))
                InfoLine(label: nil, value: Info.text(data["home_country_note"]))
            }
        }
    }

    @ViewBuilder private func numbers(_ block: JSONValue) -> some View {
        let rows: [(LKey, String?)] = [
            (K.results.emergency.police, Info.text(block["police"])),
            (K.results.emergency.ambulance, Info.text(block["ambulance"])),
            (K.results.emergency.fire, Info.text(block["fire"])),
            (K.results.emergency.touristPolice, Info.text(block["tourist_police"])),
        ]
        let present = rows.filter { $0.1 != nil }
        if !present.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(title: L10n.text(K.results.emergency.numbers))
                ForEach(Array(present.enumerated()), id: \.offset) { _, row in
                    InfoLine(label: L10n.text(row.0) + ":", value: row.1)
                }
            }
        }
    }

    @ViewBuilder private func embassy(_ block: JSONValue) -> some View {
        if block.object != nil, Info.text(block["name"]) != nil {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(title: L10n.text(K.results.emergency.embassy))
                InfoLine(label: nil, value: Info.text(block["name"]))
                InfoLine(label: nil, value: Info.text(block["address"]))
                InfoLine(label: nil, value: Info.text(block["phone"]))
                if let after = Info.text(block["emergency_after_hours"]) {
                    InfoLine(label: nil, value: L10n.text(K.results.emergency.afterHours, ["value": after]))
                }
                InfoLine(label: nil, value: Info.text(block["hours"]))
                InfoLine(label: nil, value: Info.text(block["note"]))
            }
        }
    }

    @ViewBuilder private func hospitals(_ list: [JSONValue]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(title: L10n.text(K.results.emergency.hospitals))
                ForEach(Array(list.enumerated()), id: \.offset) { _, hospital in
                    InfoLine(
                        label: nil,
                        value: [Info.text(hospital["name"]), Info.text(hospital["phone"]), Info.text(hospital["address"])]
                            .compactMap { $0 }.joined(separator: " · "))
                }
            }
        }
    }

    @ViewBuilder private func phrases(_ list: [JSONValue]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(title: L10n.text(K.results.emergency.phrases))
                ForEach(Array(list.enumerated()), id: \.offset) { _, phrase in
                    VStack(alignment: .leading, spacing: 2) {
                        InfoLine(label: nil, value: Info.text(phrase["english"]))
                        Text(verbatim: Info.text(phrase["local"]) ?? "")
                            .font(VFont.body(.footnote, weight: .semibold))
                            .foregroundStyle(SemanticColor.text)
                        InfoLine(label: nil, value: Info.text(phrase["phonetic"]))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder private func laws(_ list: [JSONValue]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(title: L10n.text(K.results.emergency.laws))
                ForEach(Array(list.enumerated()), id: \.offset) { _, law in
                    let critical = law["severity"].string == "critical"
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                        Image(systemName: critical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(critical ? SemanticColor.destructive : Palette.color(.amber, .s600))
                            .accessibilityHidden(true)
                        InfoLine(
                            label: nil,
                            value: [Info.text(law["law"]), Info.text(law["detail"])].compactMap { $0 }.joined(separator: ": "))
                    }
                }
            }
        }
    }
}

/// Writes the card as a PDF under `Application Support/offline/`. Always rendered light, like a printout.
@MainActor
enum EmergencyOffline {
    static let pageWidth: CGFloat = 540

    /// The directory for offline files (created on demand).
    static func directory() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        let dir = base.appendingPathComponent("offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The file name for one card: `emergency-card[-<city>].pdf`, with only letters and digits from the city.
    static func fileName(city: String?) -> String {
        let slug = (city ?? "").lowercased().unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? "emergency-card.pdf" : "emergency-card-\(slug).pdf"
    }

    /// Renders each entry to its own PDF; returns the files written, nil when none could be.
    @discardableResult
    static func save(entries: [EmergencyCardEntry], into directory: URL? = nil) -> [URL]? {
        guard let dir = directory ?? Self.directory() else { return nil }
        var written: [URL] = []
        for entry in entries {
            let page = EmergencyCardBody(entry: entry)
                .padding(Spacing.lg)
                .frame(width: pageWidth)
                .background(Color.white)
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: page)
            let url = dir.appendingPathComponent(fileName(city: entry.city))
            var succeeded = false
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
                context.closePDF()
                succeeded = true
            }
            if succeeded { written.append(url) }
        }
        return written.isEmpty ? nil : written
    }
}
