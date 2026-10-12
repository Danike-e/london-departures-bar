import CoreLocation
import Foundation
import XCTest
@testable import LondonDeparturesBar

@MainActor
final class NearbyStopsTests: XCTestCase {
    private let coordinate = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NearbyStopsProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testNearbyStopsAreUniqueAndSortedByCoordinateDistance() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let stops = try await LondonDeparturesBarStore.fetchNearbyStops(
            around: coordinate, radius: 1_000, limit: 2, session: session
        )
        XCTAssertEqual(stops.map(\.id), ["tfl-nearest", "tfl-middle"])
        XCTAssertEqual(stops.first?.displayCode, "A")
        XCTAssertEqual(stops.first?.routes, ["24"])
        XCTAssertEqual(stops.first?.listDirectionText, "Towards Central London")
        XCTAssertEqual(stops.last?.listDirectionText, "Westbound")
    }

    func testSearchExcludesInvalidAndOutOfRadiusStops() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let stops = try await LondonDeparturesBarStore.fetchNearbyStops(
            around: coordinate, radius: 1_000, limit: 20, session: session
        )
        XCTAssertEqual(stops.map(\.id), ["tfl-nearest", "tfl-middle", "tfl-farther"])

        let mapStops = try await LondonDeparturesBarStore.fetchNearbyStops(
            around: coordinate, session: session
        )
        XCTAssertEqual(mapStops.map(\.id), ["tfl-nearest", "tfl-middle"])
    }

    func testEmptyResponseIsASuccessfulSearch() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let stops = try await LondonDeparturesBarStore.fetchNearbyStops(
            around: coordinate, radius: 200, session: session
        )
        XCTAssertTrue(stops.isEmpty)
    }

    func testServerErrorIsNotReportedAsNoStops() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await LondonDeparturesBarStore.fetchNearbyStops(
                around: coordinate, radius: 500, session: session
            )
            XCTFail("An unsuccessful server response must throw.")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
    }

    func testInvalidResponseIsNotReportedAsNoStops() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await LondonDeparturesBarStore.fetchNearbyStops(
                around: coordinate, radius: 250, session: session
            )
            XCTFail("An invalid response must throw.")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }
}

private final class NearbyStopsProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let radius = query.first { $0.name == "radius" }?.value
        let data: Data
        switch radius {
        case "200":
            data = Data(#"{"stopPoints":[]}"#.utf8)
        case "250":
            data = Data("not JSON".utf8)
        default:
            // Distances supplied by the server are deliberately misleading.
            // The app must calculate the order from the stop coordinates.
            data = Data(#"""
            {"stopPoints":[
              {"id":"farther","commonName":"Farther stop","lat":51.503,"lon":-0.1,"distance":1},
              {"id":"nearest","commonName":"Nearest stop","stopLetter":"A","lat":51.5005,"lon":-0.1,"distance":900,"modes":["bus"],"lines":[{"id":"24","name":"24"}],"additionalProperties":[{"key":"Towards","value":"Central London"},{"key":"CompassPoint","value":"E"}]},
              {"id":"middle","commonName":"Middle stop","lat":51.502,"lon":-0.1,"distance":2,"additionalProperties":[{"key":"CompassPoint","value":"W"}]},
              {"id":"nearest","commonName":"Duplicate stop","lat":51.5005,"lon":-0.1},
              {"id":"outside","commonName":"Outside radius","lat":51.52,"lon":-0.1},
              {"id":"invalid","commonName":"Invalid location","lat":91,"lon":-0.1},
              {"id":"missing","commonName":"Missing location"}
            ]}
            """#.utf8)
        }
        let response = HTTPURLResponse(url: url, statusCode: radius == "500" ? 503 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
