import Foundation
import XCTest
@testable import LondonDeparturesBar

final class StopListDetailsTests: XCTestCase {
    private func legacyStop() throws -> Stop {
        let json = #"""
        {"id":"tfl-example","name":"Example stop","area":"","code":"A","stopLetter":"A",
         "tflAtcoCode":"example","latitude":51.5,"longitude":-0.1,"routes":["24"],
         "destinations":[],"modes":["bus"]}
        """#
        return try JSONDecoder().decode(Stop.self, from: Data(json.utf8))
    }

    func testExistingCachedStopsDecodeWithoutNewDirectionFields() throws {
        let stop = try legacyStop()
        XCTAssertNil(stop.towards)
        XCTAssertNil(stop.compassDirection)
        XCTAssertNil(stop.listDirectionText)
        XCTAssertEqual(stop.listRouteLabels, ["24"])
    }

    func testAllRoutesAreShownWithoutAnEightRouteLimit() throws {
        var stop = try legacyStop()
        stop.routes = ["24", "n15", "91", "9", " N15 ", "12", "29", "139", "159", "88", "453", "176"]
        XCTAssertEqual(stop.listRouteLabels.count, 11)
        XCTAssertTrue(stop.listRouteLabels.contains("N15"))
        XCTAssertTrue(stop.listRouteLabels.contains("453"))
        XCTAssertFalse(stop.listRouteLabels.contains(" N15 "))
    }

    func testTowardsMetadataTakesPrecedenceOverCompassAndRouteDestinations() throws {
        var stop = try legacyStop()
        stop.towards = "  Aldwych  "
        stop.compassDirection = "W"
        stop.destinations = ["Waterloo"]
        XCTAssertEqual(stop.listDirectionText, "Towards Aldwych")
    }

    func testDirectionFallsBackToKnownDestinationsAndThenCompass() throws {
        var stop = try legacyStop()
        stop.compassDirection = "W"
        stop.destinations = ["Waterloo", "Victoria"]
        XCTAssertEqual(stop.listDirectionText, "Towards Waterloo, Victoria")
        stop.destinations = []
        XCTAssertEqual(stop.listDirectionText, "Westbound")
    }

    func testDirectionMetadataSurvivesCaching() throws {
        var stop = try legacyStop()
        stop.towards = "Aldwych"
        stop.compassDirection = "W"
        let data = try JSONEncoder().encode(stop)
        let restored = try JSONDecoder().decode(Stop.self, from: data)
        XCTAssertEqual(restored.towards, "Aldwych")
        XCTAssertEqual(restored.compassDirection, "W")
    }
}
