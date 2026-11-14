import CoreGraphics
import Foundation
import SwiftUI
import TestSupport
import UIKit
import VoyagerEnv
import VoyagerModel
import XCTest

@testable import FeaturePlan

@MainActor
final class PrintTests: XCTestCase {
    private func document(rows: Int = 4) -> PlanPrintDocument {
        let big = (0..<rows).map { PlanPrintDocument.Row(id: $0, title: "Item \($0)", detail: "detail", price: Double($0) * 10) }
        return PlanPrintDocument(
            name: "Tokyo food trip", tripLine: "NYC to Tokyo", inspiredBy: nil, total: 2573,
            costParts: [CostPart(key: "hotel", label: "Hotel", amount: 1470), CostPart(key: "flights", label: "Flights", amount: 980)],
            blocks: [PlanPrintDocument.Block(id: "activities", title: "Activities", rows: big)],
            days: [PlanPrintDocument.Block(id: "day-0", title: "Day 1", rows: Array(big.prefix(2)))])
    }

    private func pageCount(_ pdf: Data) throws -> Int {
        let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
        return try XCTUnwrap(CGPDFDocument(provider)).numberOfPages
    }

    /// The top-left pixel of an image as 0...255 RGB.
    private func firstPixel(_ image: UIImage) throws -> (UInt8, UInt8, UInt8) {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        try pixel.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return (pixel[0], pixel[1], pixel[2])
    }

    func test_printAlwaysLight() throws {
        XCTAssertEqual(PrintRenderer.colorScheme, .light)
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            image = PrintRenderer.headerImage(document())
        }
        let (red, green, blue) = try firstPixel(try XCTUnwrap(image))
        XCTAssertGreaterThan(Int(red) + Int(green) + Int(blue), 3 * 240, "paper is white even when the app is dark")
    }

    func test_pdfIsPaginatedAndKeepsRowsWhole() throws {
        let short = try XCTUnwrap(PrintRenderer.makePDF(document(rows: 3)))
        XCTAssertEqual(try pageCount(short), 1)
        XCTAssertTrue(String(decoding: short.prefix(5), as: UTF8.self).hasPrefix("%PDF"))
        let long = try XCTUnwrap(PrintRenderer.makePDF(document(rows: 120)))
        XCTAssertGreaterThan(try pageCount(long), 1)
    }

    func test_documentCarriesEditedActivity() {
        var selections = PlanFixtures.selections
        selections = .object(selections.object?.merging(["itinerary_edits": ["1-morning": ["activity": "Edited visit"]]]) { _, new in new } ?? [:])
        let blocks = PlanPrintDocument.itineraryBlocks(selections: selections, itinerary: PlanFixtures.itinerary)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks[0].title.contains("Old Tokyo"))
        XCTAssertEqual(blocks[0].rows.count, 2)
        XCTAssertTrue(blocks[0].rows.contains { $0.title == "Edited visit" })
    }
}
