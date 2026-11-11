import Foundation
import L10n
import Testing
import VoyagerModel

@testable import SharedUI

struct SharedUILogicTests {
    @Test func test_bookingLinkAcceptsOnlyHttps() throws {
        #expect(BookingLink.isAllowed(try #require(URL(string: "https://www.example.com/book?a=1"))))
        #expect(!BookingLink.isAllowed(try #require(URL(string: "http://example.com"))))
        #expect(!BookingLink.isAllowed(try #require(URL(string: "javascript:alert(1)"))))
        #expect(!BookingLink.isAllowed(try #require(URL(string: "voyager://share/abc"))))
        #expect(URL(string: "https:///nohost").map(BookingLink.isAllowed) != true)
    }

    @Test func test_bookingLinkTelemetryDomainIsHostOnly() throws {
        let url = try #require(URL(string: "https://Book.Example.com/secret/path?token=abc"))
        #expect(BookingLink.domain(of: url) == "book.example.com")
    }

    @Test func test_errorCopyShowsBackendTextAsIs() {
        LanguageController.withLanguage(.en) {
            let text = "Too many searches. Try again in 42 seconds."
            #expect(ErrorCopy.message(kind: .rateLimited, detail: text) == text)
        }
    }

    @Test func test_errorCopyFallsBackToWebCopy() {
        LanguageController.withLanguage(.en) {
            #expect(ErrorCopy.message(kind: .rateLimited, detail: nil).contains("Too many"))
            #expect(ErrorCopy.message(kind: .other, detail: "  ") == "Something went wrong. Please try again.")
            #expect(ErrorCopy.message(kind: .unauthorized, detail: nil).contains("session expired"))
            #expect(ErrorCopy.message(kind: .network, detail: nil).contains("connection"))
        }
    }

    @Test func test_priceTextFormatting() {
        LanguageController.withLanguage(.en) {
            #expect(PriceText.formatted(nil, currency: "USD") == "—")
            #expect(PriceText.formatted(120, currency: "USD").contains("120"))
        }
    }

    @Test func test_attributionFooterLinksGeoNamesAndOurAirports() {
        #expect(AttributionFooter.links["geonames"]?.host() == "www.geonames.org")
        #expect(AttributionFooter.links["ourairports"]?.host() == "ourairports.com")
        let text = LanguageController.withLanguage(.en) {
            String(L10n.attributed(K.common.footer.attribution, links: AttributionFooter.links).characters)
        }
        #expect(text.contains("GeoNames"))
        #expect(text.contains("CC BY 4.0"))
    }

    @Test func test_readableWidthOnlyCapsRegular() {
        #expect(AdaptiveLayout.readableMaxWidth == 720)
        #expect(AdaptiveLayout.isRegular(.regular))
        #expect(!AdaptiveLayout.isRegular(.compact))
        #expect(!AdaptiveLayout.isRegular(nil))
    }
}
