import DesignSystem
import L10n
import SharedUI
import SwiftUI
import VoyagerModel

/// Currency and money (api-contract 3.4.13): local currency, rates, exchange spots, cards, cash, ATMs, tipping.
public struct ForexSectionView: View {
    let data: JSONValue
    let ctx: SectionContext

    public init(data: JSONValue, ctx: SectionContext) {
        self.data = data
        self.ctx = ctx
    }

    public var body: some View {
        if data.object == nil || data["local_currency"].object == nil && data["exchange_rates"].array == nil {
            InfoEmpty(key: K.results.forex.unavailable)
        } else {
            VStack(alignment: .leading, spacing: Spacing.md) {
                currencyBlock
                locationsBlock
                cardsBlock
                cashBlock
                atmBlock
                tippingBlock
                tipsBlock
                sourcesBlock
            }
        }
    }

    @ViewBuilder private var currencyBlock: some View {
        let currency = data["local_currency"]
        let title = [Info.text(currency["code"]), Info.text(currency["symbol"]), Info.text(currency["name"])]
            .compactMap { $0 }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !title.isEmpty { InfoHeading(title: title) }
            ForEach(Array(Info.list(data, "exchange_rates").enumerated()), id: \.offset) { _, rate in
                if let value = rate["rate"].double {
                    let from = Info.text(rate["from_currency"]) ?? ""
                    let to = Info.text(rate["to_currency"]) ?? ""
                    InfoLine(label: nil, value: "1 \(from) = \(Fmt.number(value, fractionDigits: 4)) \(to)")
                }
            }
        }
    }

    @ViewBuilder private var locationsBlock: some View {
        let places = Info.list(data, "exchange_locations")
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                InfoHeading(title: L10n.text(K.results.forex.whereToExchange))
                ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                    VCard {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(verbatim: Info.text(place["name"]) ?? Info.text(place["type"]) ?? "")
                                .font(VFont.body(.footnote, weight: .semibold))
                                .foregroundStyle(SemanticColor.text)
                            InfoLine(label: nil, value: Info.text(place["description"]))
                            InfoLine(label: L10n.text(K.results.forex.fees), value: Info.text(place["fees"]))
                            InfoLine(label: nil, value: Info.text(place["tip"]))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var cardsBlock: some View {
        let card = data["card_acceptance"]
        if card.object != nil {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(title: L10n.text(K.results.forex.cardAcceptance))
                InfoLine(label: L10n.text(K.results.forex.visaMc), value: Info.text(card["visa_mastercard"]))
                InfoLine(label: L10n.text(K.results.forex.amex), value: Info.text(card["amex"]))
                InfoLine(label: L10n.text(K.results.forex.contactless), value: Info.text(card["contactless"]))
                InfoLine(label: L10n.text(K.results.forex.digital), value: Info.text(card["digital_wallets"]))
                InfoLine(label: L10n.text(K.results.forex.surcharges), value: Info.text(card["surcharges"]))
            }
        }
    }

    @ViewBuilder private var cashBlock: some View {
        let cash = data["cash_advice"]
        if cash.object != nil {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(title: L10n.text(K.results.forex.cashAdvice))
                if let level = Info.text(cash["cash_dependency"]) {
                    InfoLine(label: nil, value: L10n.text(K.results.forex.cashDependency, ["level": level]))
                }
                InfoLine(label: nil, value: Info.text(cash["recommendation"]))
                InfoLine(label: L10n.text(K.results.forex.denominations), value: Info.text(cash["denominations"]))
                InfoLine(label: L10n.text(K.results.forex.bringUsdEur), value: Info.text(cash["bring_usd_eur"]))
            }
        }
    }

    @ViewBuilder private var atmBlock: some View {
        let atm = data["atm_info"]
        if atm.object != nil {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(title: L10n.text(K.results.forex.atmInfo))
                InfoLine(label: L10n.text(K.results.forex.availability), value: Info.text(atm["availability"]))
                InfoLine(label: L10n.text(K.results.forex.networks), value: Info.text(atm["networks"]))
                InfoLine(label: L10n.text(K.results.forex.limit), value: Info.text(atm["withdrawal_limit"]))
                InfoLine(label: L10n.text(K.results.forex.fees), value: Info.text(atm["fees"]))
                InfoLine(label: nil, value: Info.text(atm["best_option"]))
            }
        }
    }

    @ViewBuilder private var tippingBlock: some View {
        let tipping = data["tipping"]
        if let expected = tipping["expected"].bool {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(
                    title: L10n.text(expected ? K.results.forex.tippingExpected : K.results.forex.tippingNotExpected))
                InfoLine(label: nil, value: Info.text(tipping["description"]))
            }
        }
    }

    @ViewBuilder private var tipsBlock: some View {
        let tips = Info.list(data, "money_tips")
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                InfoHeading(title: L10n.text(K.results.forex.moneyTips))
                ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                    InfoLine(label: Info.text(tip["title"]), value: Info.text(tip["body"]))
                }
            }
        }
    }

    @ViewBuilder private var sourcesBlock: some View {
        let urls = (data["source_urls"].array ?? []).compactMap { Info.httpsURL($0) }
        if !urls.isEmpty {
            HStack {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    InfoLink(
                        title: L10n.text(K.results.forex.sourceN, ["n": String(index + 1)]), url: url, section: "forex",
                        ctx: ctx)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
