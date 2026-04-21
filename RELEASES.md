# Releases

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
