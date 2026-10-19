# Release workflow

See [the README](../README.md#release-and-updates). The previous unsigned rolling release workflow has been removed. CI tests code; local scripts handle Developer ID signing, Apple notarization, stapling, Sparkle signing and deliberate publication.

- `scripts/build-app.sh`: build and sign the app bundle.
- `scripts/notarize-release.sh`: create verified notarized ZIP/DMG artifacts and a signed appcast.
- `scripts/publish-release.sh`: publish the committed version and verified feed to the existing public GitHub repository.

Never change a versioned archive after publication. Generate a new version/build number instead. The stable `updates` release contains the mutable appcast; its downloads point to immutable versioned releases. Keep the Sparkle private key in Keychain and secure backup. Only its public key belongs in source control.
