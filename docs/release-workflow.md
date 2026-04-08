# Release Workflow

GitHub Actions workflow:

- runs `swift test`
- builds `dist/Memoir.app`
- packages both a zip archive and a dmg from the app bundle
- uploads the bundle, zip, and dmg as workflow artifacts
- refreshes a rolling GitHub Release at tag `latest` for every push to `main`
- creates a versioned GitHub Release for tag pushes like `v1.0.0`
- uploads the zip and dmg to both release types
- marks the published release as the repository's latest release

Local commands:

```sh
chmod +x scripts/build-app.sh scripts/package-release.sh
./scripts/build-app.sh
./scripts/package-release.sh
```

Notes:

- the current workflow uses ad-hoc signing via `codesign --sign -`
- that is fine for CI artifacts and local testing, but not enough for public distribution
- for public releases, the next step is adding Developer ID signing and notarization secrets to the workflow
- pushing to `main` now recreates the `latest` release so the Releases section always has a downloadable current build
