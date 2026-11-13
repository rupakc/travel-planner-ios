import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Visa and entry (api-contract 3.4.8). The static Phase 0 payload has only `requirement`; the vaccination
/// and customs blocks appear when the AI version brings them, so static data renders as a subset, not a gap.
public struct VisaSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    private static func family(for type: String?) -> Family {
        switch type {
        case "visa-free": .green
        case "visa-on-arrival", "e-visa": .amber
        default: .red
        }
    }

    /// Which blocks the payload fills: a static Phase 0 payload yields only `requirement`.
    static func blocks(_ data: JSONValue) -> [String] {
        var result: [String] = []
        if data["requirement"].object != nil { result.append("requirement") }
        let vaccinations = data["vaccinations"]
        if vaccinations.object != nil,
            !(Info.texts(vaccinations["required"]).isEmpty && Info.texts(vaccinations["recommended"]).isEmpty
                && Info.text(vaccinations["covid_status"]) == nil && Info.text(vaccinations["notes"]) == nil)
        {
            result.append("vaccinations")
        }
        let customs = data["customs"]
        let allowances = (customs["duty_free_allowances"].object ?? [:]).values.compactMap { Info.text($0) }
        if customs.object != nil,
            !(allowances.isEmpty && Info.texts(customs["prohibited_items"]).isEmpty
                && Info.texts(customs["declaration_required"]).isEmpty)
        {
            result.append("customs")
        }
        return result
    }

    public var body: some View {
        let requirement = data["requirement"]
        if requirement.object == nil {
            InfoEmpty(key: K.results.visa.unavailable)
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                requirementBlock(requirement)
                vaccinationBlock(data["vaccinations"])
                customsBlock(data["customs"])
            }
        }
    }

    private func requirementBlock(_ requirement: JSONValue) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                if let type = Info.text(requirement["visa_type"]) {
                    InfoTag(title: type.replacingOccurrences(of: "-", with: " "), family: Self.family(for: type))
                }
                if let level = Info.text(requirement["confidence"]) {
                    Text(verbatim: L10n.text(K.results.visa.confidence, ["level": level]))
                        .font(VFont.body(.caption))
                        .foregroundStyle(SemanticColor.textMuted)
                }
            }
            if let days = requirement["max_stay_days"].double {
                InfoLine(label: L10n.text(K.results.visa.maxStay), value: L10n.text(K.results.visa.days, count: Int(days)))
            }
            InfoLine(label: L10n.text(K.results.visa.processing), value: Info.text(requirement["processing_time"]))
            if let fee = requirement["fee_usd"].double {
                InfoLine(
                    label: L10n.text(K.results.visa.fee),
                    value: fee == 0 ? L10n.text(K.results.visa.free) : Fmt.currency(fee, code: "USD"))
            }
            let needs = Info.texts(requirement["requirements"])
            if !needs.isEmpty { InfoBullets(items: needs) }
            InfoLine(label: nil, value: Info.text(requirement["notes"]))
            InfoLink(
                title: L10n.text(K.results.visa.officialSource), url: Info.httpsURL(requirement["official_url"]),
                section: "visa", ctx: ctx)
        }
    }

    @ViewBuilder private func vaccinationBlock(_ block: JSONValue) -> some View {
        let required = Info.texts(block["required"])
        let recommended = Info.texts(block["recommended"])
        let status = Info.text(block["covid_status"])
        let notes = Info.text(block["notes"])
        if block.object != nil, !(required.isEmpty && recommended.isEmpty && status == nil && notes == nil) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                InfoHeading(title: L10n.text(K.results.visa.vaccination))
                if !required.isEmpty {
                    InfoLabel(title: L10n.text(K.results.visa.required))
                    InfoBullets(items: required)
                }
                if !recommended.isEmpty {
                    InfoLabel(title: L10n.text(K.results.visa.recommended))
                    InfoBullets(items: recommended)
                }
                InfoLine(label: nil, value: status)
                InfoLine(label: nil, value: notes)
                InfoLink(
                    title: L10n.text(K.results.visa.healthSource), url: Info.httpsURL(block["source_url"]), section: "visa",
                    ctx: ctx)
            }
        }
    }

    @ViewBuilder private func customsBlock(_ block: JSONValue) -> some View {
        let allowances = block["duty_free_allowances"].object ?? [:]
        let lines = allowances.keys.sorted().compactMap { key in Info.text(allowances[key] ?? .null).map { (key, $0) } }
        let prohibited = Info.texts(block["prohibited_items"])
        let declare = Info.texts(block["declaration_required"])
        if block.object != nil, !(lines.isEmpty && prohibited.isEmpty && declare.isEmpty) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                InfoHeading(title: L10n.text(K.results.visa.customs))
                if !lines.isEmpty {
                    InfoLabel(title: L10n.text(K.results.visa.dutyFree))
                    ForEach(lines, id: \.0) { line in InfoLine(label: line.0.capitalized + ":", value: line.1) }
                }
                if !prohibited.isEmpty {
                    InfoLabel(title: L10n.text(K.results.visa.prohibited))
                    InfoBullets(items: prohibited)
                }
                if !declare.isEmpty {
                    InfoLabel(title: L10n.text(K.results.visa.mustDeclare))
                    InfoBullets(items: declare)
                }
                InfoLine(label: nil, value: Info.text(block["notes"]))
                InfoLink(
                    title: L10n.text(K.results.visa.customsSource), url: Info.httpsURL(block["source_url"]), section: "visa",
                    ctx: ctx)
            }
        }
    }
}
