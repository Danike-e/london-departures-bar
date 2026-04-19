# Security Policy

## Reporting Vulnerabilities

Please do not report security vulnerabilities through public issues.

If you discover a vulnerability, open a private security advisory on GitHub when available, or contact the maintainers privately through the repository owner's preferred contact route. Include:

- A short description of the issue.
- Steps to reproduce it.
- The affected version or commit.
- Any privacy impact, especially around location, saved stops, or API requests.

Please allow reasonable time for review before public disclosure.

## Privacy And Abuse Boundaries

This app is intended for personal, low-volume use with public transport departure APIs. Contributions should not add:

- Tracking, analytics, advertising identifiers, or telemetry without explicit opt-in and documentation.
- Collection or upload of saved stops, favourites, recents, location history, or precise coordinates beyond the API calls needed for the user's requested lookup.
- API scraping, high-rate polling, bypasses for provider limits, or features designed to overload TfL, Huxley, or other transport services.
- Secrets, private keys, personal access tokens, `.netrc` files, or local user paths.

Public releases should be built from a clean checkout, signed, notarized, and distributed separately from source code.
