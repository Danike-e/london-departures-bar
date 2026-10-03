# Releases

## v1.0.11 - 2026-07-29

- Estimated each live bus's progress between its previous and next predicted stops.
- Moved bus markers every second along the route line between TfL refreshes.
- Corrected estimated positions against fresh TfL predictions every 30 seconds.
- Bumped the app version to 1.0.11 with build number 12.

## v1.0.10 - 2026-07-29

- Showed inbound and outbound buses together on route maps.
- Added distinct `IN` and `OUT` bus markers with directional arrows.
- Added separate live inbound and outbound vehicle counts above the map.
- Bumped the app version to 1.0.10 with build number 11.

## v1.0.9 - 2026-07-29

- Added live bus markers to route maps, with one marker per TfL-reported vehicle.
- Filtered live vehicle markers and counts by inbound or outbound direction.
- Added automatic 30-second vehicle refreshes and a manual refresh button.
- Bumped the app version to 1.0.9 with build number 10.

## v1.0.8 - 2026-07-29

- Added "to" before the destination in spoken departure announcements.
- Slowed spoken announcements to 160 words per minute.
- Bumped the app version to 1.0.8 with build number 9.

## v1.0.7 - 2026-07-29

- Changed spoken departures to use the Mac's default `say` voice.
- Bumped the app version to 1.0.7 with build number 8.

## v1.0.6 - 2026-07-29

- Added a Speak button that announces the next departure using the Mac's system voice.
- Pronounced three-digit bus routes digit by digit while keeping shorter route numbers natural.
- Bumped the app version to 1.0.6 with build number 7.

## v1.0.5 - 2026-07-29

- Reordered favourites by most recent stop selection, matching the Recents section.
- Kept automatic nearby-stop updates from changing favourite order.
- Bumped the app version to 1.0.5 with build number 6.

## v1.0.4 - 2026-04-24

- Added a compact TfL disruption warning strip for the selected route or line.
- Fetches TfL line status alongside live arrivals and filters warnings to the currently selected service.
- Bumped the app version to 1.0.4 with build number 5.

## v1.0.3 - 2026-04-21

- Kept the popover anchored under the menu bar time remaining when switching stops or transport modes.
- Stabilized the menu bar status item fallback label while departures are loading.
- Added Bakerloo brown styling for the `BL1` bus route.
- Added four-colour Superloop styling for bus routes beginning with `SL`.
- Added official TfL Night Bus Blue styling for bus routes beginning with `N`, with dark text for contrast.
- Kept all known bus routes available as filter options, even when no live arrivals are currently returned.
- De-duplicated bus filter routes after display normalization, so casing variants like `n199` and `N199` only appear once.
- Bumped the app version to 1.0.3 with build number 4.

## v1.0.2 - 2026-04-20

- Fixed National Rail departures not loading by switching Huxley rail lookups to the working `hux.azurewebsites.net` endpoint.
- Improved CRS station matching so London station lookups prefer exact or London-prefixed matches before falling back to the first result.
- Bumped the app version to 1.0.2 with build number 3.

## v1.0.1 - 2026-04-20

- Restyled the closed menu bar countdown so the route badge stays unchanged while the time-to-departure appears as a compact black departure-board tile.
- Kept the opened menu and map departure rows in their original time style.
- Uppercased route summaries on the map page for buses, rail, and other transport modes.
- Removed the inactive "Open menu bar" button from the Stop manager map page.
- Bumped the app version to 1.0.1 with build number 2.

## v1.0.0 - 2026-04-19

- Initial public release of London Departures Bar.
- Added the menu bar departures status, departures popover, favourites, recents, route filters, and Stop manager map.
- Added release packaging for an ad-hoc signed DMG.
