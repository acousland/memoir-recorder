# Memoir

A local-first macOS menu bar meeting recorder. Captures system playback and an optional microphone into separate, aligned mono PCM WAV tracks. Requires macOS 15 or later; release builds currently target Apple Silicon.

## Use

Open Memoir, choose a recording name if desired, and start recording from the menu bar. Grant Screen & System Audio Recording and microphone access when prompted. Recordings default to `~/Documents/Recordings`. Names are display metadata; renaming keeps the folder path stable.

For processing, configure the processor URL and API token in Settings. The token is stored in Keychain. Test Connection verifies both service compatibility and authentication. Enable auto-upload to transfer completed recordings. Queued sessions are polled until they complete. Originals remain available locally.

The processor creates a self-signed HTTPS certificate by default. Transfer its `tls/server.crt` to the recording Mac through a trusted channel, verify its fingerprint, and install/trust it in Keychain Access for SSL. Connect using a hostname or address listed on the certificate. Alternatively provision a trusted server certificate. Memoir does not bypass certificate validation. Regenerate/provision certificates deliberately when the hostname changes.

## Develop and test

```sh
swift test
scripts/build-app.sh
```

Xcode with Swift 6 is required. The release script locates SwiftPM output dynamically, embeds Sparkle, signs its nested helpers, and applies the microphone entitlement. `MEMOIR_SIGNING_IDENTITY` may select a Developer ID Application identity.

Tests cover actual WAV padding, retained buffer ownership, drift-corrected duration, empty recording rejection, metadata and session management. Real permissions, device changes, sleep/wake, and long-session synchronization still need acceptance testing on the intended recording hardware. Headphones reduce playback bleed; acoustic echo cancellation is not implemented.

## Release and updates

```sh
scripts/notarize-release.sh
# Review, commit and push source, then explicitly publish:
scripts/publish-release.sh
```

Set `MEMOIR_NOTARY_PROFILE` to a saved `notarytool` Keychain profile (on the development Mac the default is `renoir-notary`). No credential is stored in this repository. Sparkle's private signing key lives in Keychain under account `memoir`; its public key is in `Assets/sparkle-public-key`. Keep a secure private-key backup independently of the repository.

Increment `Assets/version` and the monotonically increasing `Assets/build-number` before another release. The notarization script builds, signs, submits, staples and verifies both the app and DMG, then signs the ZIP and appcast. Publishing uploads immutable versioned downloads and replaces only the signed `updates/appcast.xml` asset after verifying the download. CI tests source; it cannot publish unsigned builds.

Sparkle checks automatically and provides **Check for Updates…** in the menu. Automatic installation is off by default. Installation waits for active recording/finalization to end. Old builds without Sparkle require one manual installation before future in-app updates work.
