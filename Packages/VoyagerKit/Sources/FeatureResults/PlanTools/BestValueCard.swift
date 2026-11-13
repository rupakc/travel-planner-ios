import DesignSystem
import Domain
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// The deterministic best-value package ("Add all" with Undo).
struct BestValueCard: View {
    let pkg: JSONValue
    let selections: JSONValue
    let canUndo: Bool
    let onApply: () -> Void
    let onUndo: () -> Void

    private var items: [JSONValue] { pkg["items"].array ?? [] }
    private var applied: Bool { BestValuePackage.isApplied(selections, pkg) }
    private var conflicts: [String] { applied ? [] : BestValuePackage.conflicts(selections, pkg) }

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, entry in row(entry) }
                }
                totalLine
                actions
                if !conflicts.isEmpty {
                    Text(verbatim: L10n.text(K.plan.best.replaces, ["items": joined(conflicts)]))
                        .font(VFont.body(.caption))
                        .foregroundStyle(SemanticColor.textMuted)
                }
            }
        }
        .accessibilityIdentifier("results.bestValue")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(verbatim: L10n.text(K.plan.best.title)).font(VFont.body(.headline, weight: .semibold))
            } icon: {
                Image(systemName: "shippingbox").foregroundStyle(SemanticColor.primary)
            }
            Text(verbatim: L10n.text(K.plan.best.subtitle))
                .font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func row(_ entry: JSONValue) -> some View {
        let described = Self.describe(entry)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(verbatim: described.name).font(VFont.body(.subheadline, weight: .semibold))
                if let city = entry["city"].string, !city.isEmpty {
                    Text(verbatim: city).font(VFont.body(.caption2)).foregroundStyle(SemanticColor.textMuted)
                }
                if let price = described.price {
                    Text(verbatim: price).font(VFont.body(.caption, weight: .semibold)).foregroundStyle(SemanticColor.primary)
                }
            }
            if let reason = entry["reason"].string, !reason.isEmpty {
                Text(verbatim: reason).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var totalLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.sm) {
                Text(verbatim: L10n.text(K.plan.best.total)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
                Text(verbatim: PlanToolsFormat.usd(pkg["total"].double ?? 0)).font(VFont.body(.headline, weight: .bold))
                if let label = pkg["budget"]["label"].string {
                    Text(verbatim: label)
                        .font(VFont.body(.caption, weight: .semibold))
                        .foregroundStyle(pkg["budget"]["status"].string == "over" ? SemanticColor.destructive : SemanticColor.primary)
                }
            }
            if items.contains(where: { ["flight", "flights"].contains($0["type"].string ?? "") }) {
                Text(verbatim: L10n.text(K.plan.best.perPerson)).font(VFont.body(.caption)).foregroundStyle(SemanticColor.textMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack(spacing: Spacing.sm) {
            VButton(
                applied ? L10n.text(K.plan.best.added) : L10n.text(K.plan.best.add), tid: "plan.best-apply",
                role: applied ? .tonal : .primary, systemImage: applied ? "checkmark" : nil, action: onApply)
                .disabled(applied)
            if applied && canUndo {
                VButton(
                    L10n.text(K.plan.best.undo), tid: "plan.best-undo", role: .secondary,
                    systemImage: "arrow.uturn.backward", action: onUndo)
            }
        }
    }

    private func joined(_ labels: [String]) -> String {
        let names = labels.map { label -> String in
            switch label {
            case "flight": L10n.text(K.plan.best.conflict.flight)
            case "hotel": L10n.text(K.plan.best.conflict.hotel)
            default: L10n.text(K.plan.best.conflict.sim)
            }
        }
        guard names.count > 1, let last = names.last else { return names.joined() }
        return L10n.text(
            K.plan.best.listAnd, ["head": names.dropLast().joined(separator: L10n.text(K.plan.best.listSep)), "last": last])
    }

    /// The row's name and price (`describe` of `BestValuePackage.jsx`).
    static func describe(_ entry: JSONValue) -> (name: String, price: String?) {
        let item = entry["item"]
        let price = PlanToolsFormat.amount(item["price_usd"])
        switch entry["type"].string ?? "" {
        case "flight", "flights":
            let airline = item["outbound"]["airline"].string ?? item["airline"].string
            let number = item["outbound"]["flight_number"].string ?? item["flight_number"].string
            let name = [airline, number].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return (name.isEmpty ? L10n.text(K.plan.best.flight) : name, price.map(PlanToolsFormat.usd))
        case "hotel":
            let nightly = PlanToolsFormat.amount(item["price_per_night_usd"])
            return (item["name"].string ?? "", nightly.map { L10n.text(K.plan.best.perNight, ["price": PlanToolsFormat.usd($0)]) })
        case "activities":
            return (item["name"].string ?? "", price.map { $0 == 0 ? L10n.text(K.plan.best.free) : PlanToolsFormat.usd($0) })
        case "sim":
            let name = [item["provider"].string, item["plan_name"].string].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return (name.isEmpty ? L10n.text(K.plan.best.simPlan) : name, price.map(PlanToolsFormat.usd))
        default:
            return (item["name"].string ?? "", nil)
        }
    }
}
