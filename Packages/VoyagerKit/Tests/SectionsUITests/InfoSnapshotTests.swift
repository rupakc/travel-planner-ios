import SnapshotTesting
import SwiftUI
import VoyagerModel
import XCTest

@testable import SectionsUI

@MainActor
final class InfoSnapshotTests: XCTestCase {
    private var lean: [SnapshotConfig] { [.phoneLight, .phoneDark, .padLight, .padDark] }

    private static let weather: JSONValue = [
        "source": "llm-estimate", "poor_weather_day_count": 1,
        "days": [
            ["date": "2026-04-01", "description": "Sunny", "weather_code": 0, "temp_high_c": 21, "temp_low_c": 12, "precipitation_mm": 0, "is_poor": false],
            ["date": "2026-04-02", "description": "Heavy rain", "weather_code": 65, "temp_high_c": 16, "temp_low_c": 11, "precipitation_mm": 14.5, "is_poor": true],
        ],
    ]

    func test_weather() {
        assertSnapshots(of: { WeatherSectionView(data: Self.weather, ctx: .inert) }, named: "weather", configs: lean)
    }

    func test_places() {
        let data: JSONValue = [
            "results": [
                ["name": "Senso-ji", "category": "Temple/Mosque/Church", "neighbourhood": "Asakusa", "description": "Tokyo's oldest temple.",
                    "rating": 4.6, "visit_duration_hours": 1.5, "admission_fee_usd": 0, "highlights": ["Kaminarimon gate", "Nakamise street"],
                    "hidden_gem": false, "family_friendly": true]
            ]
        ]
        assertSnapshots(of: { PlacesSectionView(data: data, ctx: .inert) }, named: "places", configs: lean)
    }

    func test_walkingTours() {
        let data: JSONValue = [
            "results": [
                ["name": "Old Town Free Tour", "provider": "GuruWalk", "url": "https://www.guruwalk.com/x", "rating": 4.8,
                    "duration": "2.5 hours", "price_note": "Tip-based", "reason": "Matches your history interest.", "top_pick": true]
            ]
        ]
        assertSnapshots(of: { WalkingToursSectionView(data: data, ctx: .inert) }, named: "tours", configs: lean)
    }

    func test_events() {
        let data: JSONValue = [
            "results": [
                ["name": "Cherry Blossom Festival", "category": "festival", "start_date": "2026-04-01", "end_date": "2026-04-05",
                    "date_certainty": "typical_season", "location": "Ueno Park", "price": "Free", "impact": "highlight"]
            ]
        ]
        assertSnapshots(of: { EventsSectionView(data: data, ctx: .inert) }, named: "events", configs: lean)
    }

    func test_visaStatic() {
        let data: JSONValue = [
            "requirement": ["visa_type": "visa-free", "max_stay_days": 90, "requirements": ["Passport valid for 6 months"], "confidence": "high"]
        ]
        assertSnapshots(of: { VisaSectionView(data: data, ctx: .inert) }, named: "visa-static", configs: lean)
    }

    func test_visaFull() {
        let data: JSONValue = [
            "requirement": ["visa_type": "e-visa", "max_stay_days": 30, "processing_time": "3 days", "fee_usd": 50, "notes": "Apply online."],
            "vaccinations": ["required": [], "recommended": ["Hepatitis A"], "notes": "Check before travel."],
            "customs": ["duty_free_allowances": ["alcohol": "1 litre"], "prohibited_items": ["Drones"]],
        ]
        assertSnapshots(of: { VisaSectionView(data: data, ctx: .inert) }, named: "visa-full", configs: lean)
    }

    func test_tips() {
        let data: JSONValue = [
            "tips": [
                ["title": "Beware of taxi touts", "body": "Use the official rank.", "category": "tourist_trap", "severity": "warning"],
                ["title": "Tipping is not expected", "body": "Round up the bill.", "category": "etiquette", "severity": "info"],
            ]
        ]
        assertSnapshots(of: { TipsSectionView(data: data, ctx: .inert) }, named: "tips", configs: lean)
    }

    func test_gettingAround() {
        let data: JSONValue = [
            "options": [
                ["name": "Metro", "type": "metro", "scope": "intra_city", "description": "Fast and frequent.", "price_info": "$2 per ride", "operating_hours": "5:00-24:00"],
                ["name": "Shinkansen", "type": "train", "scope": "inter_city", "coverage": "Nationwide", "tourist_pass": "JR Pass"],
            ]
        ]
        assertSnapshots(of: { GettingAroundSectionView(data: data, ctx: .inert) }, named: "transport", configs: lean)
    }

    func test_forex() {
        let data: JSONValue = [
            "local_currency": ["name": "Japanese Yen", "code": "JPY", "symbol": "¥"],
            "exchange_rates": [["from_currency": "USD", "to_currency": "JPY", "rate": 150.25]],
            "exchange_locations": [["name": "Airport counter", "description": "Convenient", "fees": "High"]],
            "card_acceptance": ["visa_mastercard": "Widely accepted", "amex": "Limited"],
            "cash_advice": ["cash_dependency": "medium", "recommendation": "Carry some cash."],
            "tipping": ["expected": false, "description": "Not customary."],
            "money_tips": [["title": "ATMs", "body": "Use 7-Eleven ATMs."]],
        ]
        assertSnapshots(of: { ForexSectionView(data: data, ctx: .inert) }, named: "forex", configs: lean)
    }

    func test_emergencyMultiCity() {
        let city: (String, String) -> JSONValue = { name, police in
            [
                "city": .string(name), "emergency_numbers": ["police": .string(police), "ambulance": "112"],
                "embassy": ["name": "US Embassy", "phone": "+49 30 8305 0"],
                "local_phrases": [["english": "Help", "local": "Hilfe", "phonetic": "hilfuh"]],
                "local_laws": [["law": "ID required", "detail": "Carry ID.", "severity": "warning"]],
            ]
        }
        let data: JSONValue = ["cities": [city("Berlin, Germany", "110"), city("Prague, Czechia", "158")]]
        assertSnapshots(of: { EmergencyCardSectionView(data: data, ctx: .inert) }, named: "emergency", configs: lean)
    }

    func test_packing() {
        let data: JSONValue = [
            "categories": [
                ["name": "Clothes", "icon": "👕", "weather_note": "Mild evenings", "items": [["item": "Jacket", "essential": true, "note": "Light"], ["item": "Socks", "essential": false]]]
            ],
            "luggage_note": "Carry-on is enough", "total_items": 2,
            "checked_items": ["Clothes::Jacket": true],
        ]
        assertSnapshots(of: { PackingListSectionView(data: data, ctx: .inert) }, named: "packing", configs: lean)
    }

    func test_confidence() {
        func data(_ total: Int, _ grade: String) -> JSONValue {
            [
                "total": .number(Double(total)), "grade": .string(grade), "destination": "Tokyo",
                "sub_scores": [
                    "visa_ease": ["score": 18, "max": 20, "label": "Visa ease", "note": "Visa-free"],
                    "safety": ["score": 15, "max": 20, "label": "Safety"],
                ],
            ]
        }
        assertSnapshots(of: { ConfidenceHeaderView(data: data(82, "green"), ctx: .inert) }, named: "confidence-green", configs: lean)
        assertSnapshots(of: { ConfidenceHeaderView(data: data(55, "amber"), ctx: .inert) }, named: "confidence-amber", configs: [.phoneLight])
        assertSnapshots(of: { ConfidenceHeaderView(data: data(30, "red"), ctx: .inert) }, named: "confidence-red", configs: [.phoneLight])
    }
}
