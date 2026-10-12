import Foundation
import XCTest
@testable import LondonDeparturesBar

final class StopSearchTests: XCTestCase {
    private func stop() throws -> Stop {
        let json = #"""
        {"id":"tfl-example","name":"Trafalgar Square","area":"Westminster","code":"53521","stopLetter":"S",
         "tflAtcoCode":"example","latitude":51.5,"longitude":-0.1,"routes":["24","n15"],
         "destinations":["Pimlico"],"modes":["bus"]}
        """#
        var stop = try JSONDecoder().decode(Stop.self, from: Data(json.utf8))
        stop.towards = "Aldwych"
        return stop
    }

    func testEmptyQueryMatchesEverything() throws {
        XCTAssertTrue(try stop().matches(searchQuery: ""))
        XCTAssertTrue(try stop().matches(searchQuery: "   "))
    }

    func testMatchesNameAreaRouteCodeAndDirectionCaseInsensitively() throws {
        let stop = try stop()
        XCTAssertTrue(stop.matches(searchQuery: "trafal"))
        XCTAssertTrue(stop.matches(searchQuery: "WESTMIN"))
        XCTAssertTrue(stop.matches(searchQuery: "N15"))
        XCTAssertTrue(stop.matches(searchQuery: "53521"))
        XCTAssertTrue(stop.matches(searchQuery: "aldwych"))
        XCTAssertTrue(stop.matches(searchQuery: "pimlico"))
    }

    func testRouteNumbersMatchExactlyNotAsPartOfOtherRoutes() throws {
        var stop = try stop()
        stop.routes = ["136", "N36", "436"]
        XCTAssertFalse(stop.matches(searchQuery: "36"))
        XCTAssertTrue(stop.matches(searchQuery: "n36"))

        stop.routes = ["36", "185"]
        XCTAssertTrue(stop.matches(searchQuery: "36"))
    }

    func testStopCodeMatchesFromTheStartOnly() throws {
        let stop = try stop()
        XCTAssertTrue(stop.matches(searchQuery: "535"))
        XCTAssertFalse(stop.matches(searchQuery: "521"))
    }

    func testEveryWordMustMatch() throws {
        let stop = try stop()
        XCTAssertTrue(stop.matches(searchQuery: "square 24"))
        XCTAssertFalse(stop.matches(searchQuery: "square 73"))
        XCTAssertFalse(stop.matches(searchQuery: "victoria"))
    }
}
