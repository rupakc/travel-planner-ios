import Testing
import VoyagerModel

@testable import SectionsUI

struct SectionItemTests {
    @Test func test_nameFallsBack() {
        #expect(SectionItem(.object(["name": .string(" Hotel X ")])).name == "Hotel X")
        #expect(SectionItem(.object(["name": .string(""), "provider": .string("Airalo")])).name == "Airalo")
        #expect(SectionItem(.object([:])).name == nil)
    }

    @Test func test_priceUSD() {
        #expect(SectionItem(.object(["price_usd": .number(120.5)])).priceUSD == 120.5)
        #expect(SectionItem(.object(["price_usd": .number(-1)])).priceUSD == nil)
        #expect(SectionItem(.object(["price_usd": .string("abc")])).priceUSD == nil)
        #expect(SectionItem(.object([:])).priceUSD == nil)
    }

    @Test func test_bookingURLIsHttpsOnly() {
        #expect(SectionItem(.object(["booking_url": .string("https://example.com/x")])).bookingURL?.host() == "example.com")
        #expect(SectionItem(.object(["booking_url": .string("http://example.com")])).bookingURL == nil)
        #expect(SectionItem(.object(["booking_url": .string("javascript:alert(1)")])).bookingURL == nil)
        #expect(SectionItem(.object(["booking_url": .string("http://x"), "url": .string("https://y.com")])).bookingURL?.host() == "y.com")
    }

    @Test func test_ratingRange() {
        #expect(SectionItem(.object(["rating": .number(4.5)])).rating == 4.5)
        #expect(SectionItem(.object(["rating": .number(9.1)])).rating == nil)
    }

    @Test func test_isEstimate() {
        #expect(SectionItem(.object(["source": .string("estimate")])).isEstimate)
        #expect(SectionItem(.object(["live_fare": .bool(false)])).isEstimate)
        #expect(!SectionItem(.object(["live_fare": .bool(true)])).isEstimate)
        #expect(!SectionItem(.object([:])).isEstimate)
    }
}
