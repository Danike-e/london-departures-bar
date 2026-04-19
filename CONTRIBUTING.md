# Contributing

Thanks for helping improve London Departures Bar.

## Ground Rules

- Keep the app privacy-preserving by default.
- Do not add analytics, advertising, telemetry, or location history.
- Do not increase polling frequency or add bulk scraping of TfL, Huxley, or other transport APIs.
- Do not commit generated app bundles, build output, credentials, local paths, or personal stop data.
- Prefer small changes with clear behaviour and simple tests or manual verification notes.

## Before Opening A Pull Request

- Run `swift build`.
- Check that no generated files are included.
- Check that no secrets or personal data are included.
- Document any new network service, permission, stored user data, or privacy impact in `README.md`.

## Local Build

```bash
swift build
./scripts/build-app.sh
```
