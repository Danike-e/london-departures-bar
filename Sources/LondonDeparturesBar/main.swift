import AppKit
import Combine
import CoreLocation
import MapKit
import SwiftUI

private func displayRouteLabel(_ route: String, mode: TransitMode) -> String {
    guard mode == .bus else {
        return route
    }

    let trimmed = route.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasLetter = trimmed.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    let hasNumber = trimmed.range(of: #"[0-9]"#, options: .regularExpression) != nil

    return hasLetter && hasNumber ? trimmed.uppercased() : route
}

struct Stop: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let area: String
    let code: String
    let stopLetter: String?
    let tflAtcoCode: String?
    let latitude: Double
    let longitude: Double
    let routes: [String]
    let destinations: [String]
    let modes: [String]?
    let nationalRailCRS: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var displayCode: String {
        let trimmedLetter = stopLetter?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedLetter.isEmpty {
            return trimmedLetter.uppercased()
        }

        return code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var primaryMode: TransitMode {
        TransitMode.primary(from: modes ?? [])
    }

    var colorRoute: String? {
        primaryMode == .tube ? routes.first : nil
    }
}

struct Departure: Identifiable {
    let id = UUID()
    let route: String
    let destination: String
    let vehicleID: String?
    let mode: TransitMode
    let platform: String?
    let minutes: Int
    let dueAt: Date

    var filterKey: String {
        if mode == .nationalRail {
            return platform.map { "Platform \($0)" } ?? "No platform"
        }

        return mode == .bus ? route : destination
    }

    var filterLabel: String {
        filterKey
    }

    var departureBadgeLabel: String {
        mode == .nationalRail ? destination : filterLabel
    }

    var detailText: String {
        mode == .bus ? destination : route
    }

    var showsVehiclePlate: Bool {
        mode == .bus && vehicleID != nil
    }
}

struct RouteDisruption: Identifiable, Equatable {
    let lineID: String
    let lineName: String
    let mode: TransitMode
    let status: String
    let reason: String?

    var id: String {
        lineID
    }

    var message: String {
        if let reason, !reason.isEmpty {
            return "\(lineName): \(reason)"
        }

        return "\(lineName): \(status)"
    }
}

struct RoutePreviewRequest: Identifiable, Equatable {
    let route: String
    let mode: TransitMode
    let colorRoute: String?
    let originStopName: String
    let destination: String

    var id: String {
        "\(mode.rawValue)-\(lineID)-\(originStopName)-\(destination)"
    }

    var displayRoute: String {
        displayRouteLabel(route, mode: mode)
    }

    var lineID: String {
        TransitMode.lineID(for: colorRoute ?? route, mode: mode)
    }
}

struct RoutePreview {
    let lineID: String
    let lineName: String
    let mode: TransitMode
    let lineStrings: [[CLLocationCoordinate2D]]
    let stopSequences: [RouteStopSequence]

    var allCoordinates: [CLLocationCoordinate2D] {
        let sequenceCoordinates = stopSequences.flatMap { $0.routeCoordinates }
        return sequenceCoordinates.isEmpty ? lineStrings.flatMap { $0 } : sequenceCoordinates
    }

    var primaryStopSequence: RouteStopSequence? {
        stopSequences.max { lhs, rhs in
            lhs.stops.count < rhs.stops.count
        }
    }

    var directionGroups: [RouteDirectionGroup] {
        var grouped: [String: [RouteStopSequence]] = [:]
        var order: [String] = []

        for sequence in stopSequences {
            let key = sequence.direction.lowercased()
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(sequence)
        }

        return order.compactMap { key in
            guard let sequences = grouped[key], let first = sequences.first else { return nil }
            return RouteDirectionGroup(direction: first.direction, sequences: sequences)
        }
    }
}

struct RouteDirectionGroup: Identifiable {
    let direction: String
    let sequences: [RouteStopSequence]

    var id: String {
        direction.lowercased()
    }

    var displayDirection: String {
        direction.capitalized
    }

    var primarySequence: RouteStopSequence? {
        sequences.max { lhs, rhs in
            lhs.stops.count < rhs.stops.count
        }
    }

    var lineStrings: [[CLLocationCoordinate2D]] {
        sequences.flatMap(\.lineStrings)
    }

    var stops: [RouteStop] {
        var seen = Set<String>()
        return sequences
            .flatMap(\.stops)
            .filter { seen.insert($0.id).inserted }
    }

    var summary: String {
        primarySequence?.summary ?? displayDirection
    }

    var routeCoordinates: [CLLocationCoordinate2D] {
        let coordinates = lineStrings.flatMap { $0 }
        return coordinates.isEmpty ? stops.map(\.coordinate) : coordinates
    }
}

struct RouteStopSequence: Identifiable {
    let id: String
    let direction: String
    let lineStrings: [[CLLocationCoordinate2D]]
    let stops: [RouteStop]

    var displayDirection: String {
        direction.capitalized
    }

    var summary: String {
        guard let first = stops.first, let last = stops.last else {
            return displayDirection
        }

        return "\(displayDirection): \(first.name) to \(last.name)"
    }

    var routeCoordinates: [CLLocationCoordinate2D] {
        let coordinates = lineStrings.flatMap { $0 }
        return coordinates.isEmpty ? stops.map(\.coordinate) : coordinates
    }
}

struct RouteStop: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
}

enum TransitMode: String, Codable {
    case bus
    case tram
    case tube
    case dlr
    case overground
    case elizabethLine = "elizabeth-line"
    case nationalRail = "national-rail"

    static let supportedQueryModes = [
        bus,
        tram,
        tube,
        dlr,
        overground,
        elizabethLine,
        nationalRail
    ]

    static func primary(from modes: [String]) -> TransitMode {
        let parsedModes = modes.compactMap { TransitMode(rawValue: $0.lowercased()) }
        let priority: [TransitMode] = [.tram, .tube, .dlr, .overground, .elizabethLine, .nationalRail, .bus]
        return priority.first { parsedModes.contains($0) } ?? .bus
    }

    var color: Color {
        color(for: nil)
    }

    func color(for route: String?) -> Color {
        if self == .tube, let route {
            return Self.tubeLineRGB(for: route).color
        }

        switch self {
        case .bus:
            let normalizedRoute = Self.normalizedRoute(route)
            if normalizedRoute == "BL1" {
                return Self.bakerlooBrown.color
            }
            if let superloopColor = Self.superloopRGB(for: normalizedRoute) {
                return superloopColor.color
            }
            if normalizedRoute.hasPrefix("N") {
                return Self.nightBusBlue.color
            }
            return RGB(220, 36, 31).color
        case .tram:
            return RGB(95, 181, 38).color
        case .tube:
            return RGB(0, 25, 168).color
        case .dlr:
            return RGB(0, 175, 173).color
        case .overground:
            return RGB(250, 123, 5).color
        case .elizabethLine:
            return RGB(96, 57, 158).color
        case .nationalRail:
            return Color(red: 0.0, green: 0.19, blue: 0.51)
        }
    }

    var nsColor: NSColor {
        nsColor(for: nil)
    }

    func nsColor(for route: String?) -> NSColor {
        if self == .tube, let route {
            return Self.tubeLineRGB(for: route).nsColor
        }

        switch self {
        case .bus:
            let normalizedRoute = Self.normalizedRoute(route)
            if normalizedRoute == "BL1" {
                return Self.bakerlooBrown.nsColor
            }
            if let superloopColor = Self.superloopRGB(for: normalizedRoute) {
                return superloopColor.nsColor
            }
            if normalizedRoute.hasPrefix("N") {
                return Self.nightBusBlue.nsColor
            }
            return RGB(220, 36, 31).nsColor
        case .tram:
            return RGB(95, 181, 38).nsColor
        case .tube:
            return RGB(0, 25, 168).nsColor
        case .dlr:
            return RGB(0, 175, 173).nsColor
        case .overground:
            return RGB(250, 123, 5).nsColor
        case .elizabethLine:
            return RGB(96, 57, 158).nsColor
        case .nationalRail:
            return NSColor(calibratedRed: 0.0, green: 0.19, blue: 0.51, alpha: 1)
        }
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        var color: Color {
            Color(red: red / 255, green: green / 255, blue: blue / 255)
        }

        var nsColor: NSColor {
            NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
        }
    }

    private static let bakerlooBrown = RGB(178, 99, 0)
    private static let nightBusBlue = RGB(195, 216, 237)
    private static let superloopRouteRGB: [String: RGB] = [
        "SL1": RGB(228, 59, 23),
        "SL2": RGB(187, 204, 0),
        "SL3": RGB(129, 27, 109),
        "SL4": RGB(91, 91, 90),
        "SL5": RGB(55, 171, 221),
        "SL6": RGB(225, 0, 122),
        "SL7": RGB(190, 0, 94),
        "SL8": RGB(17, 52, 131),
        "SL9": RGB(5, 142, 156),
        "SL10": RGB(242, 149, 0),
        "SL11": RGB(61, 128, 205)
    ]

    private static func superloopRGB(for route: String) -> RGB? {
        superloopRouteRGB[route]
    }

    static func usesNightBusColor(mode: TransitMode, route: String?) -> Bool {
        let normalizedRoute = normalizedRoute(route)
        return mode == .bus
            && normalizedRoute.hasPrefix("N")
            && normalizedRoute != "BL1"
            && !normalizedRoute.hasPrefix("SL")
    }

    static func lineID(for route: String, mode: TransitMode) -> String {
        switch mode {
        case .bus:
            return normalizedRoute(route).lowercased()
        case .dlr:
            return "dlr"
        case .elizabethLine:
            return "elizabeth"
        default:
            return route
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "&", with: "and")
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }
    }

    private static func normalizedRoute(_ route: String?) -> String {
        route?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
    }

    private static func tubeLineRGB(for route: String) -> RGB {
        let key = route
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "-", with: " ")
        if key.contains("bakerloo") {
            return RGB(178, 99, 0)
        }
        if key.contains("central") {
            return RGB(220, 36, 31)
        }
        if key.contains("circle") {
            return RGB(255, 200, 10)
        }
        if key.contains("district") {
            return RGB(0, 125, 50)
        }
        if key.contains("hammersmith") || key.contains("city") {
            return RGB(245, 137, 166)
        }
        if key.contains("jubilee") {
            return RGB(131, 141, 147)
        }
        if key.contains("metropolitan") {
            return RGB(155, 0, 88)
        }
        if key.contains("northern") {
            return RGB(0, 0, 0)
        }
        if key.contains("piccadilly") {
            return RGB(0, 25, 168)
        }
        if key.contains("victoria") {
            return RGB(3, 155, 229)
        }
        if key.contains("waterloo") {
            return RGB(118, 208, 189)
        }

        return RGB(0, 25, 168)
    }
}

private func formatCountdown(until dueAt: Date, now: Date) -> String {
    let seconds = dueAt.timeIntervalSince(now)
    guard seconds >= 60 else {
        return "Due"
    }

    let minutes = max(1, Int(floor(seconds / 60.0)))
    return "\(minutes) mins"
}

private func formatDepartureBoardCountdown(until dueAt: Date, now: Date) -> String {
    let seconds = dueAt.timeIntervalSince(now)
    guard seconds >= 60 else {
        return "Due"
    }

    let minutes = max(1, Int(floor(seconds / 60.0)))
    return "\(minutes)min"
}

extension MKCoordinateRegion {
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latitudeRange = (center.latitude - span.latitudeDelta / 2)...(center.latitude + span.latitudeDelta / 2)
        let longitudeRange = (center.longitude - span.longitudeDelta / 2)...(center.longitude + span.longitudeDelta / 2)
        return latitudeRange.contains(coordinate.latitude) && longitudeRange.contains(coordinate.longitude)
    }

    var searchMargin: MKCoordinateSpan {
        MKCoordinateSpan(
            latitudeDelta: max(span.latitudeDelta, 0.02),
            longitudeDelta: max(span.longitudeDelta, 0.02)
        )
    }
}

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var locationError: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestLocation() {
        locationError = nil
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        DispatchQueue.main.async {
            self.coordinate = coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        DispatchQueue.main.async {
            self.locationError = message
        }
    }
}

@MainActor
final class AppActions: ObservableObject {
    var open: (() -> Void)?
    var openRoutePreview: ((RoutePreviewRequest) -> Void)?
    var quit: (() -> Void)?
}

@MainActor
final class LondonDeparturesBarStore: ObservableObject {
    private static let recentLimit = 5
    private static let nationalRailBaseURL = "https://hux.azurewebsites.net"

    @Published var selectedStopID: String
    @Published var selectedArea: String
    @Published var favouriteIDs: [String]
    @Published var recentIDs: [String]
    @Published var nearbyStops: [Stop] = []
    @Published var nearbyLoading: Bool = false
    @Published var nearbySearchError: String?
    @Published var liveArrivals: [Departure] = []
    @Published var liveArrivalsStopID: String?
    @Published var liveRouteSections: [TfLRouteSection] = []
    @Published var liveRouteSectionsStopID: String?
    @Published var liveLineDisruptions: [RouteDisruption] = []
    @Published var liveLineDisruptionsStopID: String?
    @Published var lastRefreshedAt: Date?
    @Published var now: Date = .now
    @Published var routeFiltersByStopID: [String: [String]]

    private enum DefaultsKey {
        static let selectedStop = "londonDeparturesBar.selectedStop"
        static let selectedArea = "londonDeparturesBar.selectedArea"
        static let favourites = "londonDeparturesBar.favourites"
        static let recents = "londonDeparturesBar.recents"
        static let cachedStops = "londonDeparturesBar.cachedStops"
        static let routeFilters = "londonDeparturesBar.routeFilters"
    }

    private let defaultStops: [Stop] = [
        Stop(
            id: "tfl-490013767X",
            name: "Northumberland Avenue / Trafalgar Square",
            area: "Central London",
            code: "X",
            stopLetter: "X",
            tflAtcoCode: "490013767X",
            latitude: 51.50716,
            longitude: -0.12673,
            routes: ["91", "N91", "N97"],
            destinations: [],
            modes: [TransitMode.bus.rawValue],
            nationalRailCRS: nil
        ),
        Stop(
            id: "tfl-940GZZLUCHX",
            name: "Charing Cross Underground Station",
            area: "Central London",
            code: "CHX",
            stopLetter: nil,
            tflAtcoCode: "940GZZLUCHX",
            latitude: 51.50741,
            longitude: -0.127277,
            routes: ["Bakerloo", "Northern"],
            destinations: [],
            modes: [TransitMode.tube.rawValue],
            nationalRailCRS: nil
        ),
        Stop(
            id: "tfl-490014585N",
            name: "Whitehall / Trafalgar Square",
            area: "Central London",
            code: "N",
            stopLetter: "N",
            tflAtcoCode: "490014585N",
            latitude: 51.50631,
            longitude: -0.12705,
            routes: ["24", "26", "87", "88", "91"],
            destinations: [],
            modes: [TransitMode.bus.rawValue],
            nationalRailCRS: nil
        )
    ]

    private let defaults = UserDefaults.standard
    private var refreshTimer: Timer?
    private var clockTimer: Timer?
    private var nearbySearchTask: Task<Void, Never>?
    private var arrivalsSearchTask: Task<Void, Never>?
    private var stopIndex: [String: Stop]
    private let defaultStopIDs: Set<String>

    init() {
        let defaultStop = defaultStops[0].id
        defaultStopIDs = Set(defaultStops.map(\.id))
        let cachedStops = Self.loadCachedStops(from: defaults)
        let loadedStops = Self.uniqueStops(defaultStops + cachedStops)
        let loadedStopIndex = Dictionary(uniqueKeysWithValues: loadedStops.map { ($0.id, $0) })
        selectedStopID = defaults.string(forKey: DefaultsKey.selectedStop) ?? defaultStop
        selectedArea = defaults.string(forKey: DefaultsKey.selectedArea) ?? defaultStops[0].area
        favouriteIDs = Self.uniqueIDs(defaults.stringArray(forKey: DefaultsKey.favourites) ?? [], limit: 20)
        recentIDs = Self.uniqueIDs(defaults.stringArray(forKey: DefaultsKey.recents) ?? [], limit: Self.recentLimit)
        routeFiltersByStopID = Self.loadRouteFilters(from: defaults)
        stopIndex = loadedStopIndex
        if !areas.contains(selectedArea) {
            selectedArea = defaultStops[0].area
        }
        if stop(for: selectedStopID) == nil {
            selectedStopID = defaultStop
        }
        recentIDs = uniquePrefix([selectedStopID] + recentIDs, limit: Self.recentLimit)
        persist()
        loadLiveTransitData(for: selectedStop)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.now = .now
            }
        }
    }

    var stops: [Stop] {
        Self.uniqueStops(Array(stopIndex.values) + nearbyStops)
    }

    var areas: [String] {
        let values = stops.map(\.area)
        return ["All"] + unique(values).sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    var selectedStop: Stop {
        stop(for: selectedStopID) ?? defaultStops[0]
    }

    var selectedDepartureSummary: String {
        guard let next = nextDepartures(for: selectedStop).first else {
            if selectedStop.tflAtcoCode == nil {
                return "No live TfL data"
            }

            return routeFilterIsActive(for: selectedStop.id) ? "No selected departures" : "No live TfL departures"
        }

        return "\(selectedStop.name) · \(formatCountdown(until: next.dueAt, now: now))"
    }

    var menuLabel: String {
        guard let next = departures.first else {
            return "Bus"
        }

        return "\(next.route) \(formatCountdown(until: next.dueAt, now: now))"
    }

    var statusTooltip: String {
        let favourites = favouriteStops.map(\.name).joined(separator: ", ")
        let favouriteText = favourites.isEmpty ? "No favourites yet" : "Favourites: \(favourites)"
        return "\(selectedDepartureSummary)\n\(selectedRouteFilterSummary)\n\(favouriteText)"
    }

    var departures: [Departure] {
        nextDepartures(for: selectedStop)
    }

    var selectedRouteFilterSummary: String {
        let filters = selectedFilters(for: selectedStopID).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return filters.isEmpty ? "Filter: All" : "Filter: \(filters.joined(separator: ", "))"
    }

    var visibleStops: [Stop] {
        guard selectedArea != "All" else {
            return stops
        }

        let filtered = stops.filter { $0.area == selectedArea }
        return filtered.isEmpty ? stops : filtered
    }

    var favouriteStops: [Stop] {
        favouriteIDs.compactMap { stop(for: $0) }
    }

    var recentStops: [Stop] {
        recentIDs.compactMap { stop(for: $0) }
    }

    func selectStop(_ id: String) {
        guard let stop = stop(for: id) else { return }
        selectedStopID = stop.id
        selectedArea = stop.area
        recentIDs = uniquePrefix([id] + recentIDs.filter { $0 != id }, limit: Self.recentLimit)
        persist()
        loadLiveTransitData(for: stop)
    }

    func selectArea(_ area: String) {
        selectedArea = area
        if area != "All", let first = stops.first(where: { $0.area == area }) {
            selectedStopID = first.id
            recentIDs = uniquePrefix([first.id] + recentIDs.filter { $0 != first.id }, limit: Self.recentLimit)
        }

        persist()
    }

    func toggleFavourite(_ id: String) {
        if favouriteIDs.contains(id) {
            favouriteIDs.removeAll { $0 == id }
        } else {
            favouriteIDs = uniquePrefix([id] + favouriteIDs, limit: 20)
        }

        persist()
    }

    func filterOptions(for stop: Stop) -> [String] {
        let values: [String]
        if stop.primaryMode == .bus {
            let liveRouteLabels = liveArrivalsStopID == stop.id ? liveArrivals.map(\.filterLabel) : []
            let liveRouteSectionLabels = stop.id == liveRouteSectionsStopID ? liveRouteSections.map(\.lineId) : []
            values = stop.routes + liveRouteSectionLabels + liveRouteLabels
        } else {
            values = liveArrivalsStopID == stop.id && !liveArrivals.isEmpty
                ? liveArrivals.map(\.filterLabel)
                : stop.destinations
        }

        return (stop.primaryMode == .bus ? uniqueBusRoutes(values) : unique(values))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func uniqueBusRoutes(_ routes: [String]) -> [String] {
        var seen = Set<String>()
        var values: [String] = []

        for route in routes {
            let trimmed = route.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let display = displayRouteLabel(trimmed, mode: .bus)
            let key = display.uppercased()
            guard seen.insert(key).inserted else { continue }
            values.append(display)
        }

        return values
    }

    func mode(for filter: String, at stop: Stop) -> TransitMode {
        if liveArrivalsStopID == stop.id,
           let departure = liveArrivals.first(where: { $0.filterKey == filter }) {
            return departure.mode
        }

        return stop.primaryMode
    }

    func colorRoute(for filter: String, at stop: Stop) -> String? {
        if liveArrivalsStopID == stop.id,
           let departure = liveArrivals.first(where: { $0.filterKey == filter }) {
            return departure.route
        }

        guard stop.primaryMode == .tube, stop.routes.count == 1 else {
            return nil
        }

        return stop.routes.first
    }

    func colorRoute(for departure: Departure) -> String? {
        departure.mode == .tube ? departure.route : nil
    }

    func colorRoute(for departure: Departure, at stop: Stop) -> String? {
        if let route = colorRoute(for: departure) {
            return route
        }

        return colorRoute(for: departure.filterKey, at: stop)
    }

    func routePreviewRequest(for departure: Departure, at stop: Stop) -> RoutePreviewRequest {
        let route = departure.mode == .bus
            ? departure.route
            : colorRoute(for: departure, at: stop) ?? departure.route
        return RoutePreviewRequest(
            route: route,
            mode: departure.mode,
            colorRoute: colorRoute(for: departure, at: stop),
            originStopName: stop.name,
            destination: departure.destination
        )
    }

    func selectedFilters(for stopID: String) -> Set<String> {
        guard let filters = routeFiltersByStopID[stopID] else {
            return []
        }

        guard let stop = stop(for: stopID) else {
            return Set(filters)
        }

        let availableFilters = Set(filterOptions(for: stop))
        guard !availableFilters.isEmpty else {
            return Set(filters)
        }

        return Set(filters).intersection(availableFilters)
    }

    func routeFilterIsActive(for stopID: String) -> Bool {
        !selectedFilters(for: stopID).isEmpty
    }

    func toggleFilter(_ filter: String, for stopID: String) {
        var filters = selectedFilters(for: stopID)
        if filters.contains(filter) {
            filters.remove(filter)
        } else {
            filters.insert(filter)
        }

        setRouteFilter(filters, for: stopID)
    }

    func showAllRoutes(for stopID: String) {
        var filters = routeFiltersByStopID
        filters.removeValue(forKey: stopID)
        routeFiltersByStopID = filters
        persist()
    }

    func stops(in region: MKCoordinateRegion) -> [Stop] {
        stops.filter { region.contains($0.coordinate) }
    }

    func loadNearbyStops(around coordinate: CLLocationCoordinate2D) {
        nearbySearchTask?.cancel()
        nearbyLoading = true
        nearbySearchError = nil
        nearbySearchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.nearbyLoading = false
                }
            }
            let loaded = await Self.fetchNearbyStops(around: coordinate)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.nearbyStops = Array(loaded.prefix(10))
                self.nearbySearchError = loaded.isEmpty ? "No nearby TfL stops found." : nil
                for stop in loaded {
                    self.stopIndex[stop.id] = stop
                }
                self.persist()
                if let first = loaded.first {
                    self.selectStop(first.id)
                }
            }
        }
    }

    func loadLiveTransitData(for stop: Stop) {
        arrivalsSearchTask?.cancel()
        guard let stopCode = stop.tflAtcoCode, !stopCode.isEmpty else {
            liveArrivals = []
            liveArrivalsStopID = nil
            liveRouteSections = []
            liveRouteSectionsStopID = nil
            liveLineDisruptions = []
            liveLineDisruptionsStopID = nil
            lastRefreshedAt = nil
            return
        }

        arrivalsSearchTask = Task { [weak self] in
            guard let self else { return }
            async let arrivalsTask = Self.fetchLiveArrivals(for: stop)
            async let routeSectionsTask = Self.fetchLiveRouteSections(for: stopCode)
            let arrivals = await arrivalsTask
            let routeSections = await routeSectionsTask
            let disruptions = await Self.fetchLineDisruptions(for: stop, arrivals: arrivals, routeSections: routeSections)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.liveArrivals = arrivals
                self.liveArrivalsStopID = stop.id
                self.liveRouteSections = routeSections
                self.liveRouteSectionsStopID = stop.id
                self.liveLineDisruptions = disruptions
                self.liveLineDisruptionsStopID = stop.id
                self.lastRefreshedAt = .now
            }
        }
    }

    func selectedDisruptions(for stop: Stop) -> [RouteDisruption] {
        guard liveLineDisruptionsStopID == stop.id else {
            return []
        }

        let selectedLineIDs = selectedStatusLineIDs(for: stop)
        guard !selectedLineIDs.isEmpty else {
            return []
        }

        return liveLineDisruptions.filter { selectedLineIDs.contains($0.lineID) }
    }

    func nextDepartures(for stop: Stop) -> [Departure] {
        if liveArrivalsStopID == stop.id, !liveArrivals.isEmpty {
            let selectedFilters = selectedFilters(for: stop.id)
            guard !selectedFilters.isEmpty else {
                return liveArrivals
            }

            return liveArrivals.filter { selectedFilters.contains($0.filterKey) }
        }

        return []
    }

    func refresh() {
        now = .now
        loadLiveTransitData(for: selectedStop)
    }

    func subtitle(for stop: Stop) -> String {
        let parts = [stop.area, stop.displayCode]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { value in
                let lower = value.lowercased()
                return lower != "nearby stops" && lower != "map"
            }

        return parts.joined(separator: " · ")
    }

    func routeSummary(for stop: Stop) -> String {
        let routes = stop.id == liveRouteSectionsStopID && !liveRouteSections.isEmpty
            ? liveRouteSections.map(\.lineId)
            : stop.routes

        let values = unique(routes)
            .filter { !$0.isEmpty }
            .map { $0.uppercased() }
        return values.isEmpty ? "No routes" : values.prefix(8).joined(separator: ", ")
    }

    func destinationSummary(for stop: Stop) -> String {
        let destinations = stop.id == liveArrivalsStopID && !liveArrivals.isEmpty
            ? liveArrivals.map(\.destination)
            : stop.id == liveRouteSectionsStopID && !liveRouteSections.isEmpty
            ? liveRouteSections.map { $0.vehicleDestinationText ?? $0.destinationName ?? "" }
            : stop.destinations

        let values = unique(destinations).filter { !$0.isEmpty }
        return values.isEmpty ? "No destinations" : values.prefix(6).joined(separator: ", ")
    }

    private func persist() {
        defaults.set(selectedStopID, forKey: DefaultsKey.selectedStop)
        defaults.set(selectedArea, forKey: DefaultsKey.selectedArea)
        defaults.set(favouriteIDs, forKey: DefaultsKey.favourites)
        defaults.set(recentIDs, forKey: DefaultsKey.recents)
        defaults.set(routeFiltersByStopID, forKey: DefaultsKey.routeFilters)
        persistCachedStops()
    }

    private func setRouteFilter(_ routes: Set<String>, for stopID: String) {
        let sortedRoutes = routes.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var filters = routeFiltersByStopID
        if sortedRoutes.isEmpty {
            filters.removeValue(forKey: stopID)
        } else {
            filters[stopID] = sortedRoutes
        }

        routeFiltersByStopID = filters
        persist()
    }

    private func persistCachedStops() {
        let pinnedIDs = Set([selectedStopID] + favouriteIDs + recentIDs)
        let cachedStops = Self.uniqueStops(Array(stopIndex.values) + nearbyStops)
            .filter { stop in
                !defaultStopIDs.contains(stop.id) || pinnedIDs.contains(stop.id)
            }
            .sorted { lhs, rhs in
                let lhsPinned = pinnedIDs.contains(lhs.id)
                let rhsPinned = pinnedIDs.contains(rhs.id)
                if lhsPinned != rhsPinned {
                    return lhsPinned
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(100)

        do {
            let data = try JSONEncoder().encode(Array(cachedStops))
            defaults.set(data, forKey: DefaultsKey.cachedStops)
        } catch {
            defaults.removeObject(forKey: DefaultsKey.cachedStops)
        }
    }

    private func uniquePrefix(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return Array(values.filter { seen.insert($0).inserted }.prefix(limit))
    }

    func cameraRegion(for area: String) -> MKCoordinateRegion {
        let candidates = area == "All" ? stops : stops.filter { $0.area == area }
        return region(for: candidates.isEmpty ? stops : candidates)
    }

    func defaultCoordinate(for area: String) -> CLLocationCoordinate2D {
        let region = cameraRegion(for: area)
        return region.center
    }

    private func region(for stops: [Stop]) -> MKCoordinateRegion {
        let latitudeValues = stops.map(\.latitude)
        let longitudeValues = stops.map(\.longitude)
        let latitude = latitudeValues.reduce(0, +) / Double(max(stops.count, 1))
        let longitude = longitudeValues.reduce(0, +) / Double(max(stops.count, 1))
        let latitudeDelta = max(0.03, 0.012 * Double(max(stops.count, 1)))
        let longitudeDelta = max(0.03, 0.015 * Double(max(stops.count, 1)))
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func uniqueStops(_ stops: [Stop]) -> [Stop] {
        var seen = Set<String>()
        return stops.filter { seen.insert($0.id).inserted }
    }

    private func stop(for id: String) -> Stop? {
        stopIndex[id] ?? nearbyStops.first(where: { $0.id == id })
    }

    private static func fetchLiveArrivals(for stop: Stop) async -> [Departure] {
        let stopCode = stop.tflAtcoCode ?? ""
        guard let url = URL(string: "https://api.tfl.gov.uk/StopPoint/\(stopCode)/Arrivals") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("LondonDeparturesBar/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            let decoded = try JSONDecoder().decode([TfLArrivalRecord].self, from: data)
            let sorted = decoded.sorted { lhs, rhs in lhs.timeToStation < rhs.timeToStation }

            let departures = sorted.prefix(8).map { record in
                let dueAt = record.expectedArrivalDate ?? Date().addingTimeInterval(TimeInterval(record.timeToStation))
                let minutes = record.timeToStation <= 0 ? 0 : max(1, record.timeToStation / 60)
                return Departure(
                    route: record.lineName,
                    destination: record.destinationName,
                    vehicleID: Self.firstNonEmpty(record.vehicleId),
                    mode: Self.mode(from: record.modeName),
                    platform: nil,
                    minutes: minutes,
                    dueAt: dueAt
                )
            }

            if departures.isEmpty, stop.primaryMode == .nationalRail {
                return await fetchNationalRailDepartures(for: stop)
            }

            return departures
        } catch {
            if stop.primaryMode == .nationalRail {
                return await fetchNationalRailDepartures(for: stop)
            }
            return []
        }
    }

    private static func fetchLiveRouteSections(for stopCode: String) async -> [TfLRouteSection] {
        guard let url = URL(string: "https://api.tfl.gov.uk/StopPoint/\(stopCode)/Route") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("LondonDeparturesBar/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            let decoded = try JSONDecoder().decode([TfLRouteSection].self, from: data)
            return decoded
                .filter { $0.isActive ?? true }
                .sorted { lhs, rhs in
                    lhs.lineId.localizedCaseInsensitiveCompare(rhs.lineId) == .orderedAscending
                }
        } catch {
            return []
        }
    }

    private static func fetchLineDisruptions(
        for stop: Stop,
        arrivals: [Departure],
        routeSections: [TfLRouteSection]
    ) async -> [RouteDisruption] {
        let lineIDs = statusLineIDs(for: stop, arrivals: arrivals, routeSections: routeSections)
        guard !lineIDs.isEmpty else {
            return []
        }

        let chunkedIDs = stride(from: 0, to: lineIDs.count, by: 20).map { start in
            Array(lineIDs[start..<min(start + 20, lineIDs.count)])
        }
        var disruptions: [RouteDisruption] = []

        for ids in chunkedIDs {
            guard let encodedIDs = ids
                .joined(separator: ",")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://api.tfl.gov.uk/Line/\(encodedIDs)/Status") else {
                continue
            }

            var request = URLRequest(url: url)
            request.setValue("LondonDeparturesBar/1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    continue
                }

                let decoded = try JSONDecoder().decode([TfLLineStatusResponse].self, from: data)
                disruptions.append(contentsOf: decoded.compactMap(routeDisruption(from:)))
            } catch {
                continue
            }
        }

        return disruptions.sorted { lhs, rhs in
            lhs.lineName.localizedStandardCompare(rhs.lineName) == .orderedAscending
        }
    }

    nonisolated private static func routeDisruption(from response: TfLLineStatusResponse) -> RouteDisruption? {
        let disruptedStatus = response.lineStatuses
            .filter { $0.statusSeverity != 10 }
            .sorted { lhs, rhs in lhs.statusSeverity < rhs.statusSeverity }
            .first

        guard let disruptedStatus else {
            return nil
        }

        let reason = firstNonEmpty(
            disruptedStatus.reason,
            response.disruptions?.compactMap(\.description).first
        )

        return RouteDisruption(
            lineID: response.id.lowercased(),
            lineName: firstNonEmpty(response.name, response.id) ?? response.id,
            mode: mode(from: response.modeName),
            status: disruptedStatus.statusSeverityDescription,
            reason: reason
        )
    }

    private static func statusLineIDs(
        for stop: Stop,
        arrivals: [Departure],
        routeSections: [TfLRouteSection]
    ) -> [String] {
        let stopRoutes = stop.routes.map { TransitMode.lineID(for: $0, mode: stop.primaryMode) }
        let arrivalRoutes = arrivals.map { TransitMode.lineID(for: $0.route, mode: $0.mode) }
        let sectionRoutes = routeSections.map(\.lineId)
        return uniqueStatusLineIDs(stopRoutes + arrivalRoutes + sectionRoutes)
    }

    private func selectedStatusLineIDs(for stop: Stop) -> Set<String> {
        let selectedFilters = selectedFilters(for: stop.id)
        if !selectedFilters.isEmpty {
            let ids = selectedFilters.map { filter in
                TransitMode.lineID(for: colorRoute(for: filter, at: stop) ?? filter, mode: mode(for: filter, at: stop))
            }
            return Set(Self.uniqueStatusLineIDs(ids))
        }

        return Set(Self.uniqueStatusLineIDs(stop.routes.map { TransitMode.lineID(for: $0, mode: stop.primaryMode) }))
    }

    static func fetchRoutePreview(for request: RoutePreviewRequest) async throws -> RoutePreview {
        guard request.mode != .nationalRail else {
            throw RoutePreviewError.unsupportedMode
        }

        guard let encodedLineID = request.lineID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.tfl.gov.uk/Line/\(encodedLineID)/Route/Sequence/all?serviceTypes=Regular") else {
            throw RoutePreviewError.invalidRoute
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("LondonDeparturesBar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw RoutePreviewError.routeUnavailable
        }

        let decoded = try JSONDecoder().decode(TfLRouteSequenceResponse.self, from: data)
        let lineStrings = decoded.lineStrings.flatMap(Self.coordinates(fromLineString:)).filter { !$0.isEmpty }
        let sequences = decoded.stopPointSequences.enumerated().map { index, sequence in
            let sequenceLineStrings = index < lineStrings.count ? [lineStrings[index]] : []
            return RouteStopSequence(
                id: "\(sequence.direction)-\(sequence.branchId)",
                direction: sequence.direction,
                lineStrings: sequenceLineStrings,
                stops: sequence.stopPoint.compactMap { stop in
                    guard let latitude = stop.lat, let longitude = stop.lon else { return nil }
                    return RouteStop(
                        id: stop.id,
                        name: stop.name,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    )
                }
            )
        }

        guard !lineStrings.isEmpty || sequences.contains(where: { !$0.stops.isEmpty }) else {
            throw RoutePreviewError.routeUnavailable
        }

        return RoutePreview(
            lineID: decoded.lineId,
            lineName: decoded.lineName,
            mode: Self.mode(from: decoded.mode),
            lineStrings: lineStrings,
            stopSequences: sequences
        )
    }

    nonisolated private static func coordinates(fromLineString value: String) -> [[CLLocationCoordinate2D]] {
        guard let data = value.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }

        return coordinateGroups(from: parsed)
    }

    nonisolated private static func coordinateGroups(from value: Any) -> [[CLLocationCoordinate2D]] {
        if let pair = value as? [Double], pair.count >= 2 {
            return [[CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])]]
        }

        guard let values = value as? [Any] else {
            return []
        }

        let nested = values.flatMap(coordinateGroups)
        if nested.count > 1, nested.allSatisfy({ $0.count == 1 }) {
            return [nested.flatMap { $0 }]
        }

        return nested
    }

    private static func fetchNationalRailDepartures(for stop: Stop) async -> [Departure] {
        guard let crs = await nationalRailCRS(for: stop) else {
            return []
        }

        guard let url = URL(string: "\(nationalRailBaseURL)/departures/\(crs)/10") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("LondonDeparturesBar/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            let decoded = try JSONDecoder().decode(NationalRailDeparturesResponse.self, from: data)
            let services = (decoded.trainServices ?? []) + (decoded.busServices ?? [])
            return services.compactMap { service in
                guard service.isCancelled != true else { return nil }
                guard let dueAt = service.departureDate else { return nil }
                let destination = service.destinationSummary
                guard !destination.isEmpty else { return nil }

                let platform = Self.firstNonEmpty(service.platform).map { "Platform \($0)" }
                let timing = Self.firstNonEmpty(service.etd, service.std)
                let detail = [platform, service.operatorName, timing]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                let minutes = max(0, Int(dueAt.timeIntervalSinceNow / 60))

                return Departure(
                    route: detail.isEmpty ? "National Rail" : detail,
                    destination: destination,
                    vehicleID: nil,
                    mode: .nationalRail,
                    platform: Self.firstNonEmpty(service.platform),
                    minutes: minutes,
                    dueAt: dueAt
                )
            }
            .sorted { $0.dueAt < $1.dueAt }
            .prefix(8)
            .map { $0 }
        } catch {
            return []
        }
    }

    private static func nationalRailCRS(for stop: Stop) async -> String? {
        if let crs = firstNonEmpty(stop.nationalRailCRS) {
            return crs.uppercased()
        }

        let stationName = stop.name
            .replacingOccurrences(of: " Rail Station", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: " Station", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stationName.isEmpty else { return nil }
        guard let encodedName = stationName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(nationalRailBaseURL)/crs/\(encodedName)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("LondonDeparturesBar/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let matches = try JSONDecoder().decode([NationalRailStationMatch].self, from: data)
            return bestCRSMatch(for: stationName, in: matches)?.uppercased()
        } catch {
            return nil
        }
    }

    private static func bestCRSMatch(for stationName: String, in matches: [NationalRailStationMatch]) -> String? {
        let query = normalizedStationName(stationName)
        let londonQuery = normalizedStationName("London \(stationName)")
        let exactMatch = matches.first { match in
            let candidate = normalizedStationName(match.stationName)
            return candidate == query || candidate == londonQuery
        }

        return (exactMatch ?? matches.first)?.crsCode
    }

    private static func normalizedStationName(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func fetchNearbyStops(around coordinate: CLLocationCoordinate2D) async -> [Stop] {
        var components = URLComponents(string: "https://api.tfl.gov.uk/StopPoint")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude)),
            URLQueryItem(name: "stopTypes", value: "NaptanPublicBusCoachTram,NaptanMetroStation,NaptanRailStation"),
            URLQueryItem(name: "radius", value: "300"),
            URLQueryItem(name: "modes", value: TransitMode.supportedQueryModes.map(\.rawValue).joined(separator: ","))
        ]

        guard let url = components.url else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("LondonDeparturesBar/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            let decoded = try JSONDecoder().decode(TfLNearbyStopsResponse.self, from: data)
            let stops = decoded.stopPoints.compactMap { record -> Stop? in
                guard let latitude = record.lat, let longitude = record.lon else {
                    return nil
                }

                let atcoCode = record.naptanId ?? record.id
                guard let atcoCode, !atcoCode.isEmpty else {
                    return nil
                }

                let stopLetter = Self.stopLetter(from: record)
                let name = Self.firstNonEmpty(record.commonName, record.indicator)
                guard let name else { return nil }

                let code = Self.firstNonEmpty(stopLetter, record.indicator, atcoCode) ?? atcoCode
                let routeDetails = record.lines?.compactMap { line -> RouteDetail? in
                    let route = Self.firstNonEmpty(line.name, line.id) ?? ""
                    guard !route.isEmpty else { return nil }
                    return RouteDetail(route: route, destination: "")
                } ?? []
                let modes = Self.stopModes(from: record)

                let uniqueRoutes = Self.uniqueRouteDetails(routeDetails)
                return Stop(
                    id: "tfl-\(atcoCode)",
                    name: name,
                    area: "",
                    code: code,
                    stopLetter: stopLetter,
                    tflAtcoCode: atcoCode,
                    latitude: latitude,
                    longitude: longitude,
                    routes: uniqueRoutes.map(\.route),
                    destinations: uniqueRoutes.map(\.destination),
                    modes: modes,
                    nationalRailCRS: nil
                )
            }

            return Self.closestStops(stops, to: coordinate, limit: 10)
        } catch {
            return []
        }
    }

    private static func loadCachedStops(from defaults: UserDefaults) -> [Stop] {
        guard let data = defaults.data(forKey: DefaultsKey.cachedStops) else {
            return []
        }

        do {
            return try JSONDecoder().decode([Stop].self, from: data)
        } catch {
            defaults.removeObject(forKey: DefaultsKey.cachedStops)
            return []
        }
    }

    private static func loadRouteFilters(from defaults: UserDefaults) -> [String: [String]] {
        guard let values = defaults.dictionary(forKey: DefaultsKey.routeFilters) as? [String: [String]] else {
            return [:]
        }

        return values.mapValues { uniqueIDs($0, limit: 30) }.filter { !$0.value.isEmpty }
    }

    private static func uniqueIDs(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return Array(values
            .filter { seen.insert($0).inserted }
            .prefix(limit)
        )
    }

    private static func uniqueStatusLineIDs(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func closestStops(_ stops: [Stop], to coordinate: CLLocationCoordinate2D, limit: Int) -> [Stop] {
        stops
            .sorted { lhs, rhs in
                lhs.coordinate.distance(to: coordinate) < rhs.coordinate.distance(to: coordinate)
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func uniqueRouteDetails(_ values: [RouteDetail]) -> [RouteDetail] {
        var seen = Set<String>()
        return values.filter { seen.insert("\($0.route)|\($0.destination)").inserted }
    }

    private static func stopLetter(from record: TfLStopPointRecord) -> String? {
        if let stopLetter = record.stopLetter?.trimmingCharacters(in: .whitespacesAndNewlines), !stopLetter.isEmpty {
            return stopLetter.uppercased()
        }

        if let indicator = record.indicator?.trimmingCharacters(in: .whitespacesAndNewlines), !indicator.isEmpty {
            let pieces = indicator.split(whereSeparator: { $0.isWhitespace })
            if let last = pieces.last, last.count == 1 {
                return last.uppercased()
            }

            return indicator.uppercased()
        }

        return nil
    }

    nonisolated private static func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func stopModes(from record: TfLStopPointRecord) -> [String] {
        let rawModes = (record.modes ?? []) + (record.lines?.compactMap(\.modeName) ?? [])
        let modes = uniqueModeNames(rawModes)
        return modes.isEmpty ? [TransitMode.bus.rawValue] : modes
    }

    nonisolated private static func mode(from rawValue: String?) -> TransitMode {
        guard let rawValue else { return .bus }
        return TransitMode(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .bus
    }

    private static func uniqueModeNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .compactMap { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard TransitMode(rawValue: trimmed) != nil else {
                    return nil
                }

                return trimmed
            }
            .filter { seen.insert($0).inserted }
    }

    private struct RouteDetail {
        let route: String
        let destination: String
    }

}

private struct TfLArrivalRecord: Decodable {
    let lineName: String
    let destinationName: String
    let vehicleId: String?
    let modeName: String?
    let expectedArrival: String?
    let timeToStation: Int

    var expectedArrivalDate: Date? {
        guard let expectedArrival else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expectedArrival) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expectedArrival)
    }
}

private struct NationalRailDeparturesResponse: Decodable {
    let trainServices: [NationalRailService]?
    let busServices: [NationalRailService]?
}

private struct NationalRailService: Decodable {
    let destination: [NationalRailLocation]?
    let std: String?
    let etd: String?
    let platform: String?
    let operatorName: String?
    let isCancelled: Bool?

    enum CodingKeys: String, CodingKey {
        case destination
        case std
        case etd
        case platform
        case operatorName = "operator"
        case isCancelled
    }

    var destinationSummary: String {
        (destination ?? [])
            .map(\.locationName)
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    var departureDate: Date? {
        let value = etd == "On time" || etd == "No report" || etd == "Delayed" ? std : etd
        guard let value, !value.isEmpty, value != "Cancelled" else { return nil }
        guard let departureTime = Self.timeFormatter.date(from: value) else { return nil }

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: departureTime)
        guard let hour = timeComponents.hour, let minute = timeComponents.minute else { return nil }

        var dateComponents = calendar.dateComponents([.year, .month, .day], from: .now)
        dateComponents.hour = hour
        dateComponents.minute = minute
        let candidate = calendar.date(from: dateComponents)
        guard let candidate else { return nil }

        if candidate.timeIntervalSinceNow < -600 {
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }

        return candidate
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct NationalRailLocation: Decodable {
    let locationName: String
}

private struct NationalRailStationMatch: Decodable {
    let stationName: String
    let crsCode: String
}

struct TfLRouteSection: Decodable {
    let lineId: String
    let vehicleDestinationText: String?
    let destinationName: String?
    let isActive: Bool?
}

private struct TfLLineStatusResponse: Decodable {
    let id: String
    let name: String?
    let modeName: String?
    let lineStatuses: [TfLLineStatus]
    let disruptions: [TfLLineDisruption]?
}

private struct TfLLineStatus: Decodable {
    let statusSeverity: Int
    let statusSeverityDescription: String
    let reason: String?
}

private struct TfLLineDisruption: Decodable {
    let description: String?
}

enum RoutePreviewError: LocalizedError {
    case invalidRoute
    case routeUnavailable
    case unsupportedMode

    var errorDescription: String? {
        switch self {
        case .invalidRoute:
            return "This route could not be opened."
        case .routeUnavailable:
            return "TfL did not return a route map for this service."
        case .unsupportedMode:
            return "Route maps are available for TfL services only."
        }
    }
}

private struct TfLRouteSequenceResponse: Decodable {
    let lineId: String
    let lineName: String
    let mode: String?
    let lineStrings: [String]
    let stopPointSequences: [TfLStopPointSequence]
}

private struct TfLStopPointSequence: Decodable {
    let direction: String
    let branchId: Int
    let stopPoint: [TfLMatchedStop]
}

private struct TfLMatchedStop: Decodable {
    let id: String
    let name: String
    let lat: Double?
    let lon: Double?
}

private struct TfLNearbyStopsResponse: Decodable {
    let stopPoints: [TfLStopPointRecord]
}

private struct TfLStopPointRecord: Decodable {
    let id: String?
    let naptanId: String?
    let indicator: String?
    let stopLetter: String?
    let commonName: String?
    let lat: Double?
    let lon: Double?
    let distance: Double?
    let modes: [String]?
    let lines: [TfLLineRecord]?
}

private struct TfLLineRecord: Decodable {
    let id: String
    let name: String?
    let modeName: String?
}

@main
enum LondonDeparturesBarMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = LondonDeparturesBarStore()
    let actions = AppActions()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var standaloneWindow: NSWindow?
    private var routePreviewWindow: NSWindow?
    private var cancellable: AnyCancellable?
    private let logURL = URL(fileURLWithPath: "/tmp/londonDeparturesBar.log")

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("launch")
        NSApplication.shared.setActivationPolicy(.accessory)
        actions.open = { [weak self] in self?.showStandaloneWindow() }
        actions.openRoutePreview = { [weak self] request in self?.showRoutePreviewWindow(for: request) }
        actions.quit = { [weak self] in self?.quitApp() }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageOnly
            button.image = statusImage()
            button.title = ""
        }

        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.delegate = self
        popover.contentSize = NSSize(width: 400, height: 440)
        popover.contentViewController = NSHostingController(
            rootView: LondonDeparturesBarMenuView()
                .environmentObject(store)
                .environmentObject(actions)
        )

        self.statusItem = statusItem
        self.popover = popover

        cancellable = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }

        updateStatusItem()
        log("status item configured")
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(sender)
            clearStatusButtonHighlight()
            return
        }

        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        updateStatusItem()
        popover.show(relativeTo: statusCountdownAnchorRect(in: button), of: button, preferredEdge: .minY)
        clearStatusButtonHighlight()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func statusCountdownAnchorRect(in button: NSStatusBarButton) -> NSRect {
        let countdown = statusCountdownText()
        guard !countdown.isEmpty else {
            return button.bounds
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        ]
        let textSize = countdown.size(withAttributes: attributes)
        let countdownHorizontalPadding: CGFloat = 5
        let countdownWidth = ceil(textSize.width + countdownHorizontalPadding * 2)
        let anchorWidth = min(button.bounds.width, countdownWidth)

        return NSRect(
            x: button.bounds.maxX - anchorWidth,
            y: button.bounds.minY,
            width: anchorWidth,
            height: button.bounds.height
        )
    }

    func popoverDidClose(_ notification: Notification) {
        clearStatusButtonHighlight()
    }

    private func showStandaloneWindow() {
        if popover?.isShown == true {
            popover?.performClose(nil)
        }

        if standaloneWindow == nil {
            let rootView = LondonDeparturesBarBoardView()
                .environmentObject(store)
                .environmentObject(actions)

            let controller = NSHostingController(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 920),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "London Departures Bar"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            standaloneWindow = window
        }

        positionStandaloneWindow()
        standaloneWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showRoutePreviewWindow(for request: RoutePreviewRequest) {
        let rootView = RoutePreviewWindowView(request: request)
            .environmentObject(store)
            .environmentObject(actions)
        let controller = NSHostingController(rootView: rootView)

        if routePreviewWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            routePreviewWindow = window
        }

        routePreviewWindow?.title = "\(request.displayRoute) Route"
        routePreviewWindow?.contentViewController = controller
        positionRoutePreviewWindow()
        routePreviewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func positionRoutePreviewWindow() {
        guard let window = routePreviewWindow,
              let screen = window.screen ?? NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let targetWidth = min(680, max(540, visibleFrame.width - 80))
        let targetHeight = min(700, max(620, visibleFrame.height - 80))
        window.setContentSize(NSSize(width: targetWidth, height: targetHeight))
        let frame = window.frame
        let originX = routePreviewOriginX(for: frame, in: visibleFrame)
        let originY = max(visibleFrame.minY + 24, visibleFrame.maxY - frame.height - 56)
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func routePreviewOriginX(for frame: NSRect, in visibleFrame: NSRect) -> CGFloat {
        let minimumX = visibleFrame.minX + 24
        let maximumX = visibleFrame.maxX - frame.width - 24
        let fallbackX = visibleFrame.midX - frame.width / 2 - 180

        guard let button = statusItem?.button,
              let buttonWindow = button.window else {
            return min(max(fallbackX, minimumX), maximumX)
        }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let popoverWidth = popover?.contentSize.width ?? 400
        let popoverLeftEdge = buttonFrame.midX - popoverWidth / 2
        let preferredX = popoverLeftEdge - frame.width - 18
        return min(max(preferredX, minimumX), maximumX)
    }

    private func positionStandaloneWindow() {
        guard let window = standaloneWindow,
              let screen = window.screen ?? NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let targetWidth = min(720, max(520, visibleFrame.width - 80))
        let targetHeight = min(820, max(560, visibleFrame.height - 80))
        window.setContentSize(NSSize(width: targetWidth, height: targetHeight))
        let frame = window.frame
        let originX = visibleFrame.midX - frame.width / 2
        let originY = max(visibleFrame.minY + 24, visibleFrame.maxY - frame.height - 36)
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func updateStatusItem() {
        guard let statusItem, let button = statusItem.button else {
            log("status item update skipped: missing button")
            return
        }
        let image = statusImage()
        button.image = image
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        button.imageScaling = .scaleProportionallyDown
        clearStatusButtonHighlight()
        statusItem.length = NSStatusItem.variableLength
        button.toolTip = store.statusTooltip
        log("status item updated width=\(image?.size.width ?? 0) departures=\(store.departures.count) label=\(statusServiceLabel())")
        if popover?.isShown == true {
            popover?.positioningRect = statusCountdownAnchorRect(in: button)
        }
    }

    private func clearStatusButtonHighlight() {
        statusItem?.button?.highlight(false)
    }

    private func statusText() -> String {
        guard let next = store.departures.first else {
            return "London Departures Bar"
        }

        let label = next.mode == .bus
            ? next.route.trimmingCharacters(in: .whitespacesAndNewlines)
            : next.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortLabel = label.count > 14 ? "\(label.prefix(12))..." : label
        return " \(shortLabel) \(formatCountdown(until: next.dueAt, now: store.now)) "
    }

    private func statusImage() -> NSImage? {
        let next = store.departures.first
        let label = statusServiceLabel()
        let countdown = statusCountdownText()
        let font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        let textColor = statusForegroundColor(for: next?.mode ?? .bus, route: next?.route)
        let backgroundColor = next?.mode.nsColor(for: next?.route) ?? NSColor.controlAccentColor
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let countdownAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.12, alpha: 1)
        ]
        let badgeTextSize = label.size(withAttributes: badgeAttributes)
        let countdownSize = countdown.size(withAttributes: countdownAttributes)
        let badgeHorizontalPadding: CGFloat = 6
        let badgeVerticalPadding: CGFloat = 2
        let interItemSpacing: CGFloat = 5
        let countdownHorizontalPadding: CGFloat = 5
        let countdownVerticalPadding: CGFloat = 2
        let badgeSize = NSSize(
            width: ceil(badgeTextSize.width + badgeHorizontalPadding * 2),
            height: ceil(badgeTextSize.height + badgeVerticalPadding * 2)
        )
        let countdownBadgeSize = NSSize(
            width: ceil(countdownSize.width + countdownHorizontalPadding * 2),
            height: ceil(countdownSize.height + countdownVerticalPadding * 2)
        )
        let imageSize = NSSize(
            width: ceil(badgeSize.width + interItemSpacing + countdownBadgeSize.width),
            height: ceil(max(badgeSize.height, countdownBadgeSize.height))
        )
        let image = NSImage(size: imageSize)
        image.lockFocus()
        let badgeRect = NSRect(
            x: 0,
            y: (imageSize.height - badgeSize.height) / 2,
            width: badgeSize.width,
            height: badgeSize.height
        )
        let badgePath = NSBezierPath(
            roundedRect: badgeRect,
            xRadius: 4,
            yRadius: 4
        )
        backgroundColor.setFill()
        badgePath.fill()
        label.draw(
            at: NSPoint(
                x: badgeHorizontalPadding,
                y: (imageSize.height - badgeTextSize.height) / 2
            ),
            withAttributes: badgeAttributes
        )
        NSColor(calibratedRed: 0.02, green: 0.025, blue: 0.018, alpha: 1).setFill()
        let countdownRect = NSRect(
            x: badgeSize.width + interItemSpacing,
            y: (imageSize.height - countdownBadgeSize.height) / 2,
            width: countdownBadgeSize.width,
            height: countdownBadgeSize.height
        )
        NSBezierPath(
            roundedRect: countdownRect,
            xRadius: 3,
            yRadius: 3
        ).fill()
        countdown.draw(
            at: NSPoint(
                x: countdownRect.minX + countdownHorizontalPadding,
                y: countdownRect.minY + countdownVerticalPadding
            ),
            withAttributes: countdownAttributes
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func statusServiceLabel() -> String {
        guard let next = store.departures.first else {
            return "LDB"
        }

        let label = next.mode == .bus
            ? next.route.trimmingCharacters(in: .whitespacesAndNewlines)
            : next.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.count > 14 ? "\(label.prefix(12))..." : label
    }

    private func statusCountdownText() -> String {
        guard let next = store.departures.first else {
            return ""
        }

        return formatDepartureBoardCountdown(until: next.dueAt, now: store.now)
    }

    private func statusForegroundColor(for mode: TransitMode, route: String?) -> NSColor {
        if TransitMode.usesNightBusColor(mode: mode, route: route) {
            return NSColor(calibratedWhite: 0.12, alpha: 1)
        }

        guard mode == .tube else {
            return .white
        }

        let route = route?.lowercased() ?? ""
        if route.contains("circle") || route.contains("hammersmith") || route.contains("waterloo") {
            return .black
        }

        return .white
    }

    private func log(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                FileManager.default.createFile(atPath: logURL.path, contents: data)
            }
        }
    }
}

struct LondonDeparturesBarMenuView: View {
    @EnvironmentObject private var store: LondonDeparturesBarStore
    @EnvironmentObject private var actions: AppActions
    private let contentWidth: CGFloat = 352
    private static let topScrollID = "menu-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                        .id(Self.topScrollID)
                    actionRow
                    DisruptionStrip(disruptions: store.selectedDisruptions(for: store.selectedStop))
                    Divider()

                    section(title: filterSectionTitle(for: store.selectedStop)) {
                        RouteFilterPicker(stop: store.selectedStop)
                    }

                    section(title: "Next departures") {
                        VStack(spacing: 8) {
                            if store.departures.isEmpty {
                                Text(departuresEmptyText(for: store.selectedStop))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            ForEach(store.departures) { departure in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .center, spacing: 6) {
                                            Button {
                                                actions.openRoutePreview?(
                                                    store.routePreviewRequest(for: departure, at: store.selectedStop)
                                                )
                                            } label: {
                                                RouteBadge(
                                                    route: departure.departureBadgeLabel,
                                                    mode: departure.mode,
                                                    selected: store.selectedFilters(for: store.selectedStop.id).contains(departure.filterKey),
                                                    colorRoute: store.colorRoute(for: departure, at: store.selectedStop)
                                                )
                                            }
                                            .buttonStyle(.plain)

                                            if departure.showsVehiclePlate, let vehicleID = departure.vehicleID {
                                                VehiclePlateView(vehicleID: vehicleID)
                                            }
                                        }

                                        Text(departure.detailText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 12)

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(formatCountdown(until: departure.dueAt, now: store.now))
                                            .font(.headline)
                                        Text(formatClock(departure.dueAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 5)
                                .padding(.horizontal, 2)
                            }
                        }
                    }

                    section(title: "Favourites") {
                        stopList(store.favouriteStops, emptyText: "Add a stop to pin it here.", scrollProxy: proxy)
                    }

                    section(title: "Recent") {
                        stopList(store.recentStops, emptyText: "Picked stops show up here.", scrollProxy: proxy)
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .frame(width: 400, height: 440)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.selectedStop.name)
                        .font(.headline)
                    StopMetaView(stop: store.selectedStop)
                }

                Spacer(minLength: 12)

                LastRefreshView(date: store.lastRefreshedAt)
            }

            HStack(spacing: 8) {
                Button(store.favouriteIDs.contains(store.selectedStop.id) ? "Remove from favourites" : "Add to favourites") {
                    store.toggleFavourite(store.selectedStop.id)
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh") {
                    store.refresh()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Open") {
                actions.open?()
            }
            .buttonStyle(.bordered)

            Button("Quit") {
                actions.quit?()
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func stopList(_ stops: [Stop], emptyText: String, scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            if stops.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(stops) { stop in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button {
                            store.selectStop(stop.id)
                            scrollToTop(using: scrollProxy)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.name)
                                    .foregroundStyle(.primary)
                                StopMetaView(stop: stop)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.toggleFavourite(stop.id)
                        } label: {
                            Image(systemName: store.favouriteIDs.contains(stop.id) ? "star.fill" : "star")
                                .foregroundStyle(store.favouriteIDs.contains(stop.id) ? .yellow : .secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func scrollToTop(using proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(Self.topScrollID, anchor: .top)
        }
    }

    private func formatClock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func departuresEmptyText(for stop: Stop) -> String {
        store.routeFilterIsActive(for: stop.id) ? "No departures for selected filters" : "No live TfL departures"
    }

    private func filterSectionTitle(for stop: Stop) -> String {
        switch stop.primaryMode {
        case .bus:
            return "Routes"
        case .nationalRail:
            return "Platforms"
        default:
            return "Destinations"
        }
    }

}

struct LastRefreshView: View {
    let date: Date?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Last refreshed")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(date.map(formatClock) ?? "Waiting")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.trailing)
    }

    private func formatClock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

struct DisruptionStrip: View {
    let disruptions: [RouteDisruption]
    @State private var expanded = false

    var body: some View {
        if let disruption = disruptions.first {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: expanded ? 8 : 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Color(red: 0.65, green: 0.34, blue: 0.0))

                        Text(disruption.message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(expanded ? nil : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if disruptions.count > 1 {
                            Text("+\(disruptions.count - 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }

                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }

                    if expanded && disruptions.count > 1 {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(disruptions.dropFirst()) { item in
                                Text(item.message)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.leading, 22)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.88, blue: 0.42).opacity(0.32))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(red: 0.73, green: 0.45, blue: 0.0).opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Service disruption")
            .accessibilityHint(expanded ? "Collapse status" : "Expand status")
        }
    }
}

struct RouteFilterPicker: View {
    @EnvironmentObject private var store: LondonDeparturesBarStore
    let stop: Stop

    private let columns = [
        GridItem(.adaptive(minimum: 48), spacing: 6)
    ]

    var body: some View {
        let options = store.filterOptions(for: stop)
        let selectedFilters = store.selectedFilters(for: stop.id)

        if options.isEmpty {
            Text(filterEmptyText(for: stop))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                Button {
                    store.showAllRoutes(for: stop.id)
                } label: {
                    RouteFilterChip(title: "All", selected: selectedFilters.isEmpty, mode: stop.primaryMode, colorRoute: stop.colorRoute)
                }
                .buttonStyle(.plain)

                ForEach(options, id: \.self) { option in
                    Button {
                        store.toggleFilter(option, for: stop.id)
                    } label: {
                        RouteFilterChip(
                            title: option,
                            selected: selectedFilters.contains(option),
                            mode: store.mode(for: option, at: stop),
                            colorRoute: store.colorRoute(for: option, at: stop)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filterEmptyText(for stop: Stop) -> String {
        switch stop.primaryMode {
        case .bus:
            return "Routes appear once TfL data loads."
        case .nationalRail:
            return "Platforms appear once National Rail data loads."
        default:
            return "Destinations appear once TfL data loads."
        }
    }
}

struct RouteFilterChip: View {
    let title: String
    let selected: Bool
    let mode: TransitMode
    var colorRoute: String?

    var body: some View {
        let route = colorRoute ?? title
        Text(displayRouteLabel(title, mode: mode))
            .font(.caption.bold())
            .foregroundStyle(selected && !TransitMode.usesNightBusColor(mode: mode, route: route) ? Color.white : Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 7)
            .background {
                if selected {
                    RouteColorBackground(route: route, mode: mode, cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(selected ? Color.clear : Color.secondary.opacity(0.22), lineWidth: 1)
            )
    }
}

struct RouteColorBackground: View {
    let route: String?
    let mode: TransitMode
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(mode.color(for: route))
    }
}

struct VehiclePlateView: View {
    let vehicleID: String

    var body: some View {
        Text(vehicleID.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.black.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.82, blue: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.black.opacity(0.5), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 4)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 3,
                            bottomLeadingRadius: 3
                        )
                    )
            }
            .accessibilityLabel("Vehicle \(vehicleID)")
    }
}

struct RoutePreviewWindowView: View {
    let request: RoutePreviewRequest
    @State private var preview: RoutePreview?
    @State private var selectedDirectionID: String?
    @State private var errorMessage: String?
    @State private var loading = false
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if loading {
                ProgressView("Loading route")
                    .controlSize(.small)
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            }

            directionPicker
            mapPane

            if let group = selectedDirectionGroup {
                stopSequence(group)
            }
        }
        .padding(18)
        .frame(minWidth: 540, minHeight: 620)
        .task(id: request.id) {
            await loadRoutePreview()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            RouteBadge(
                route: request.displayRoute,
                mode: request.mode,
                colorRoute: request.colorRoute ?? request.route
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(preview?.lineName ?? request.displayRoute)
                    .font(.title2.bold())
                Text(summaryText)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }

    private var summaryText: String {
        if let group = selectedDirectionGroup {
            return group.summary
        }

        let destination = request.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        return destination.isEmpty
            ? "From \(request.originStopName)"
            : "From \(request.originStopName) towards \(destination)"
    }

    @ViewBuilder
    private var directionPicker: some View {
        if let preview, preview.directionGroups.count > 1 {
            Picker("Direction", selection: Binding(
                get: { selectedDirectionID ?? preview.directionGroups[0].id },
                set: { id in
                    selectedDirectionID = id
                    if let group = preview.directionGroups.first(where: { $0.id == id }) {
                        mapPosition = routeMapPosition(for: group)
                    }
                }
            )) {
                ForEach(preview.directionGroups) { group in
                    Text(group.displayDirection)
                        .tag(group.id)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var selectedDirectionGroup: RouteDirectionGroup? {
        guard let preview else { return nil }
        if let selectedDirectionID,
           let group = preview.directionGroups.first(where: { $0.id == selectedDirectionID }) {
            return group
        }

        return preview.directionGroups.first
    }

    private var mapPane: some View {
        Map(position: $mapPosition) {
            if let preview, let group = selectedDirectionGroup {
                let lineStrings = group.lineStrings.isEmpty ? [group.stops.map(\.coordinate)] : group.lineStrings
                ForEach(Array(lineStrings.enumerated()), id: \.offset) { _, coordinates in
                    MapPolyline(coordinates: coordinates)
                        .stroke(routeColor(for: preview), lineWidth: 4)
                }

                ForEach(Array(group.stops.enumerated()), id: \.offset) { _, stop in
                    Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                        Circle()
                            .fill(routeColor(for: preview))
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    }
                }
            }
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func stopSequence(_ group: RouteDirectionGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stops")
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(group.stops.enumerated()), id: \.offset) { index, stop in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 22, alignment: .trailing)
                            Text(stop.name)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 150)
        }
    }

    private func loadRoutePreview() async {
        loading = true
        errorMessage = nil
        preview = nil

        do {
            let loaded = try await LondonDeparturesBarStore.fetchRoutePreview(for: request)
            preview = loaded
            selectedDirectionID = preferredDirectionGroup(in: loaded)?.id
            mapPosition = selectedDirectionID
                .flatMap { id in loaded.directionGroups.first(where: { $0.id == id }) }
                .map(routeMapPosition(for:)) ?? routeMapPosition(for: loaded)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            selectedDirectionID = nil
            mapPosition = .automatic
        }

        loading = false
    }

    private func routeColor(for preview: RoutePreview) -> Color {
        preview.mode.color(for: request.colorRoute ?? preview.lineName)
    }

    private func routeMapPosition(for preview: RoutePreview) -> MapCameraPosition {
        let coordinates = preview.allCoordinates.isEmpty
            ? preview.stopSequences.flatMap { $0.stops.map(\.coordinate) }
            : preview.allCoordinates
        guard let region = region(containing: coordinates) else {
            return .automatic
        }

        return .region(region)
    }

    private func routeMapPosition(for group: RouteDirectionGroup) -> MapCameraPosition {
        guard let region = region(containing: group.routeCoordinates) else {
            return .automatic
        }

        return .region(region)
    }

    private func preferredDirectionGroup(in preview: RoutePreview) -> RouteDirectionGroup? {
        let destination = request.destination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !destination.isEmpty,
           let matchingGroup = preview.directionGroups.first(where: { group in
               group.summary.lowercased().contains(destination)
                   || group.sequences.contains { sequence in
                       sequence.stops.last?.name.lowercased().contains(destination) == true
                   }
           }) {
            return matchingGroup
        }

        return preview.directionGroups.first
    }

    private func region(containing coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? first.latitude
        let maxLatitude = latitudes.max() ?? first.latitude
        let minLongitude = longitudes.min() ?? first.longitude
        let maxLongitude = longitudes.max() ?? first.longitude
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.012, (maxLatitude - minLatitude) * 1.25),
            longitudeDelta: max(0.012, (maxLongitude - minLongitude) * 1.25)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

struct LondonDeparturesBarBoardView: View {
    @EnvironmentObject private var store: LondonDeparturesBarStore
    @EnvironmentObject private var actions: AppActions
    @StateObject private var locationProvider = LocationProvider()
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var searchCenter: CLLocationCoordinate2D?
    private let focusedMapSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                mapPane
                selectedStopPane
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 520, minHeight: 560)
        .navigationTitle("London Departures Bar")
        .onAppear {
            focus(on: store.selectedStop.coordinate)
        }
        .onReceive(locationProvider.$coordinate.compactMap { $0 }) { coordinate in
            focus(on: coordinate)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stop manager")
                .font(.largeTitle.bold())
            Text("Move the map, click a point, and London Departures Bar will show the closest stops and stations around there. Tap one to inspect its arrivals and favourite it.")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Use current location") {
                    locationProvider.requestLocation()
                }
                .buttonStyle(.borderedProminent)

                Button("Quit") {
                    actions.quit?()
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)
            }

            if let error = locationProvider.locationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let searchCenter {
                Text("Searching near \(searchCenter.latitude, specifier: "%.4f"), \(searchCenter.longitude, specifier: "%.4f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let nearbySearchError = store.nearbySearchError {
                Text(nearbySearchError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.nearbyLoading {
                ProgressView("Loading nearby stops")
                    .controlSize(.small)
            }
        }
    }

    private var selectedStopPane: some View {
        section(title: "Selected stop") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.selectedStop.name)
                            .font(.headline)
                        StopMetaView(stop: store.selectedStop)
                        Text("Routes: \(store.routeSummary(for: store.selectedStop))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Destinations: \(store.destinationSummary(for: store.selectedStop))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button(store.favouriteIDs.contains(store.selectedStop.id) ? "Remove from favourites" : "Add to favourites") {
                        store.toggleFavourite(store.selectedStop.id)
                    }
                    .buttonStyle(.borderedProminent)
                }

                section(title: filterSectionTitle(for: store.selectedStop)) {
                    RouteFilterPicker(stop: store.selectedStop)
                }

                DisruptionStrip(disruptions: store.selectedDisruptions(for: store.selectedStop))

                VStack(spacing: 8) {
                    let departures = store.nextDepartures(for: store.selectedStop)
                    if departures.isEmpty {
                        Text(departuresEmptyText(for: store.selectedStop))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(departures) { departure in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .center, spacing: 6) {
                                    Button {
                                        actions.openRoutePreview?(
                                            store.routePreviewRequest(for: departure, at: store.selectedStop)
                                        )
                                    } label: {
                                        RouteBadge(
                                            route: departure.departureBadgeLabel,
                                            mode: departure.mode,
                                            selected: store.selectedFilters(for: store.selectedStop.id).contains(departure.filterKey),
                                            colorRoute: store.colorRoute(for: departure, at: store.selectedStop)
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if departure.showsVehiclePlate, let vehicleID = departure.vehicleID {
                                        VehiclePlateView(vehicleID: vehicleID)
                                    }
                                }

                                Text(departure.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatCountdown(until: departure.dueAt, now: store.now))
                                    .font(.headline)
                                Text(formatClock(departure.dueAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var mapPane: some View {
        section(title: "Map") {
            MapReader { proxy in
                Map(position: $mapPosition) {
                    if let searchCenter {
                        Annotation("Search", coordinate: searchCenter, anchor: .center) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.18))
                                    .frame(width: 24, height: 24)
                                Circle()
                                    .stroke(Color.accentColor, lineWidth: 2)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }

                    ForEach(store.nearbyStops) { stop in
                        Annotation(stop.name, coordinate: stop.coordinate, anchor: .bottom) {
                            Button {
                                focusOn(stop: stop)
                            } label: {
                                StopPinView(
                                    stop: stop,
                                    selected: stop.id == store.selectedStopID,
                                    favourite: store.favouriteIDs.contains(stop.id)
                                )
                            }
                            .contextMenu {
                                Button(store.favouriteIDs.contains(stop.id) ? "Remove from favourites" : "Add to favourites") {
                                    store.toggleFavourite(stop.id)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                            focus(on: coordinate)
                        }
                )
            }
            .frame(height: 340)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func focusOn(stop: Stop) {
        store.selectStop(stop.id)
        focus(on: stop.coordinate)
    }

    private func focus(on coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(
            center: coordinate,
            span: focusedMapSpan
        )
        mapPosition = .region(region)
        searchCenter = coordinate
        store.loadNearbyStops(around: coordinate)
    }

    private func formatClock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func departuresEmptyText(for stop: Stop) -> String {
        store.routeFilterIsActive(for: stop.id) ? "No departures for selected filters" : "No live TfL departures"
    }

    private func filterSectionTitle(for stop: Stop) -> String {
        switch stop.primaryMode {
        case .bus:
            return "Routes"
        case .nationalRail:
            return "Platforms"
        default:
            return "Destinations"
        }
    }

}

struct StopPinView: View {
    let stop: Stop
    let selected: Bool
    let favourite: Bool

    var body: some View {
        StopCodeBadge(code: stop.displayCode, size: .small, mode: stop.primaryMode, colorRoute: stop.colorRoute)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(selected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(favourite ? 0.18 : 0.1), radius: 2, y: 1)
        .padding(.vertical, 2)
    }
}

struct StopMetaView: View {
    let stop: Stop

    private var area: String? {
        let value = stop.area.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let lower = value.lowercased()
        guard lower != "nearby stops" && lower != "map" else { return nil }
        return value
    }

    var body: some View {
        HStack(spacing: 6) {
            if let area {
                Text(area)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !stop.displayCode.isEmpty {
                StopCodeBadge(code: stop.displayCode, mode: stop.primaryMode, colorRoute: stop.colorRoute)
            }
        }
    }
}

struct StopCodeBadge: View {
    enum Size {
        case regular
        case small
    }

    let code: String
    var size: Size = .regular
    var mode: TransitMode = .bus
    var colorRoute: String?

    var body: some View {
        Text(code)
            .font(size == .regular ? .caption.bold() : .caption2.bold())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minWidth: size == .regular ? 22 : 18, minHeight: size == .regular ? 18 : 16)
            .padding(.horizontal, size == .regular ? 5 : 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(mode.color(for: colorRoute))
            )
    }
}

struct RouteBadge: View {
    let route: String
    let mode: TransitMode
    var selected: Bool = false
    var colorRoute: String?

    var body: some View {
        let badgeRoute = colorRoute ?? route
        Text(displayRouteLabel(route, mode: mode))
            .font(.caption.bold())
            .foregroundStyle(TransitMode.usesNightBusColor(mode: mode, route: badgeRoute) ? Color.primary : Color.white)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                RouteColorBackground(route: badgeRoute, mode: mode, cornerRadius: 4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(selected ? Color.primary.opacity(0.65) : Color.clear, lineWidth: 1.5)
            )
    }
}
