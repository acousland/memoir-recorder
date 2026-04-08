# Release Workflow

GitHub Actions workflow:

- runs `swift test`
- builds `dist/Memoir.app`
- packages a zip archive from the app bundle
- uploads the bundle and zip as workflow artifacts
- uploads the zip to GitHub Releases for tag pushes like `v1.0.0` and published releases

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
