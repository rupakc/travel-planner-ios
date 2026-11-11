import SwiftUI
import VoyagerModel

/// Maps a section id to its view. Every case is present, so adding a `SectionID` is a compile error here.
public enum SectionRegistry {
    @MainActor
    public static func view(for id: SectionID, data: JSONValue, ctx: SectionContext) -> AnyView {
        switch id {
        case .flights: AnyView(FlightsSectionView(data: data, ctx: ctx))
        case .weather: AnyView(WeatherSectionView(data: data, ctx: ctx))
        case .hotels: AnyView(HotelsSectionView(data: data, ctx: ctx))
        case .activities: AnyView(ActivitiesSectionView(data: data, ctx: ctx))
        case .places_to_see: AnyView(PlacesSectionView(data: data, ctx: ctx))
        case .walking_tours: AnyView(WalkingToursSectionView(data: data, ctx: ctx))
        case .events: AnyView(EventsSectionView(data: data, ctx: ctx))
        case .visa: AnyView(VisaSectionView(data: data, ctx: ctx))
        case .sim: AnyView(SimSectionView(data: data, ctx: ctx))
        case .tips: AnyView(TipsSectionView(data: data, ctx: ctx))
        case .emergency_card: AnyView(EmergencyCardSectionView(data: data, ctx: ctx))
        case .getting_around: AnyView(GettingAroundSectionView(data: data, ctx: ctx))
        case .forex: AnyView(ForexSectionView(data: data, ctx: ctx))
        case .itinerary: AnyView(ItinerarySectionView(data: data, ctx: ctx))
        case .stress_test: AnyView(StressTestSectionView(data: data, ctx: ctx))
        case .packing_list: AnyView(PackingListSectionView(data: data, ctx: ctx))
        }
    }
}
