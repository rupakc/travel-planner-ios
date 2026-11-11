import Foundation

extension PlanICS {
    /// The user-visible strings inside the file (the web's `plan:ics.*` and `plan:print.*`), from the localised
    /// catalogue. `english` is the web's English copy, for tests and previews only.
    public struct Labels: Sendable {
        public let dayTheme: @Sendable (_ day: String, _ theme: String) -> String
        public let fromLinkQuote: @Sendable (String) -> String
        public let fromLink: String
        public let alsoFromLink: @Sendable (String) -> String
        public let estCost: @Sendable (String) -> String
        public let arrives: @Sendable (String) -> String
        public let booking: @Sendable (String) -> String
        public let price: @Sendable (String) -> String
        public let trip: String
        public let defaultName: String
        public let inspiredBy: @Sendable (String) -> String
        /// Whole-dollar-or-cents currency text for an estimated cost (`Intl` style, up to two decimals).
        public let formatCost: @Sendable (Double) -> String

        public init(
            dayTheme: @escaping @Sendable (_ day: String, _ theme: String) -> String,
            fromLinkQuote: @escaping @Sendable (String) -> String,
            fromLink: String,
            alsoFromLink: @escaping @Sendable (String) -> String,
            estCost: @escaping @Sendable (String) -> String,
            arrives: @escaping @Sendable (String) -> String,
            booking: @escaping @Sendable (String) -> String,
            price: @escaping @Sendable (String) -> String,
            trip: String,
            defaultName: String,
            inspiredBy: @escaping @Sendable (String) -> String,
            formatCost: @escaping @Sendable (Double) -> String
        ) {
            self.dayTheme = dayTheme
            self.fromLinkQuote = fromLinkQuote
            self.fromLink = fromLink
            self.alsoFromLink = alsoFromLink
            self.estCost = estCost
            self.arrives = arrives
            self.booking = booking
            self.price = price
            self.trip = trip
            self.defaultName = defaultName
            self.inspiredBy = inspiredBy
            self.formatCost = formatCost
        }

        /// The web's English copy and en-US money, for tests and previews only.
        public static let english = Labels(
            dayTheme: { "Day \($0): \($1)" },
            fromLinkQuote: { "From your link: \u{201C}\($0)\u{201D}" },
            fromLink: "From your link",
            alsoFromLink: { "Also from your link: \($0)" },
            estCost: { "Est. cost: \($0)" },
            arrives: { "Arrives \($0) local time" },
            booking: { "Booking: \($0)" },
            price: { "Price: \($0)" },
            trip: "Trip",
            defaultName: "Trip plan",
            inspiredBy: { "Inspired by \($0)" },
            formatCost: { ExportText.usdUpTo2($0) }
        )
    }
}
