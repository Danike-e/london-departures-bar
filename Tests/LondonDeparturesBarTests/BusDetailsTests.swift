import CoreLocation
import Foundation
import XCTest
@testable import LondonDeparturesBar

@MainActor
final class BusDetailsTests: XCTestCase {
    private let stops = [
        RouteStop(id: "start", name: "Lewisham Centre", coordinate: .init(latitude: 51.46, longitude: -0.01)),
        RouteStop(id: "middle", name: "New Cross Gate", coordinate: .init(latitude: 51.475, longitude: -0.04)),
        RouteStop(id: "end", name: "Waterloo Station", coordinate: .init(latitude: 51.5, longitude: -0.11))
    ]

    private var preview: RoutePreview {
        RoutePreview(lineID: "bl1", lineName: "BL1", mode: .bus, lineStrings: [], stopSequences: [
            RouteStopSequence(id: "outbound-1", direction: "outbound", lineStrings: [], stops: stops),
            RouteStopSequence(id: "inbound-0", direction: "inbound", lineStrings: [], stops: stops.reversed())
        ])
    }

    private func request(vehicle: String, stopID: String = "start") -> RoutePreviewRequest {
        RoutePreviewRequest(route: vehicle == "error" ? "error" : "BL1", mode: .bus, colorRoute: nil,
                            originStopName: "Lewisham Centre", destination: "Waterloo Station",
                            vehicleID: vehicle, originStopID: stopID, direction: "outbound")
    }

    private func vehicles(for request: RoutePreviewRequest) async throws -> [LiveRouteVehicle] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BusDetailsProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await LondonDeparturesBarStore.fetchLiveRouteVehicles(for: request, preview: preview, session: session)
    }

    func testDepartureIdentityIncludesTheSpecificBus() {
        XCTAssertNotEqual(request(vehicle: "BUS1").id, request(vehicle: "BUS2").id)
    }

    func testDirectionUsesTheClickedDepartureRatherThanTheLongestRoute() {
        var request = request(vehicle: "BUS1")
        request.direction = "inbound"
        XCTAssertEqual(preview.stopSequence(for: request)?.id, "inbound-0")
    }

    func testPositionBeforeTheFirstStopIsExplicitlyEstimated() async throws {
        let vehicles = try await vehicles(for: request(vehicle: "BUS1"))
        let bus = try XCTUnwrap(vehicles.first { $0.vehicleID == "BUS1" })
        XCTAssertTrue(bus.isEstimatedPosition)
        XCTAssertEqual(bus.locationName, "Approaching Lewisham Centre")
        XCTAssertEqual(bus.nextStopID, "start")
        XCTAssertEqual(bus.routeSequenceID, "outbound-1")
    }

    func testReportedStopDoesNotClaimBusIsBetweenStops() async throws {
        let vehicles = try await vehicles(for: request(vehicle: "BUS2"))
        let bus = try XCTUnwrap(vehicles.first { $0.vehicleID == "BUS2" })
        XCTAssertFalse(bus.isEstimatedPosition)
        XCTAssertEqual(bus.locationName, "New Cross Gate")
        XCTAssertEqual(bus.coordinate(at: .now).latitude, stops[1].coordinate.latitude, accuracy: 0.00001)
    }

    func testSelectedTripDoesNotUseTheReturnTripPosition() async throws {
        let request = request(vehicle: "BUS3", stopID: "middle")
        let vehicles = try await vehicles(for: request)
        let bus = try XCTUnwrap(vehicles.first { $0.vehicleID == "BUS3" })
        XCTAssertEqual(bus.direction, "outbound")
        XCTAssertEqual(bus.nextStopID, "middle")
        XCTAssertEqual(preview.stopSequence(for: request, vehicle: bus)?.id, "outbound-1")
        // A long wait must not animate the bus to its stop in only 90 seconds.
        XCTAssertGreaterThan(bus.segmentDuration, 500)
        XCTAssertLessThan(bus.coordinate(at: .now.addingTimeInterval(90)).latitude, stops[1].coordinate.latitude)
    }

    func testServerFailureThrowsInsteadOfRemovingTheSelectedBus() async {
        do {
            _ = try await vehicles(for: request(vehicle: "error"))
            XCTFail("An unsuccessful response must throw")
        } catch {
            guard case RoutePreviewError.liveVehiclesUnavailable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

private final class BusDetailsProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(#"""
        [
          {"vehicleId":"BUS1","naptanId":"start","destinationName":"Waterloo Station","direction":"outbound","currentLocation":"","tripId":"one","timeToStation":540},
          {"vehicleId":"BUS1","naptanId":"middle","destinationName":"Waterloo Station","direction":"outbound","tripId":"one","timeToStation":700},
          {"vehicleId":"BUS2","naptanId":"middle","destinationName":"Waterloo Station","direction":"outbound","currentLocation":"New Cross Gate","tripId":"two","timeToStation":10},
          {"vehicleId":"BUS3","naptanId":"middle","destinationName":"Waterloo Station","direction":"outbound","tripId":"three","timeToStation":600},
          {"vehicleId":"BUS3","naptanId":"end","destinationName":"Waterloo Station","direction":"outbound","tripId":"three","timeToStation":690},
          {"vehicleId":"BUS3","naptanId":"end","destinationName":"Lewisham Centre","direction":"inbound","tripId":"return","timeToStation":5}
        ]
        """#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: request.url!.path.contains("/error/") ? 503 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
