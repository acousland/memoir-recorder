# Memoir

A private macOS meeting app backed by Memoir Processor. **Thread** combines quiet menu bar capture with a chronological conversation library: rose accents, serif headings, month sections, timestamped transcripts, speaker naming, search, copy and export. Completed transcripts are cached on the recorder Mac for offline use.

This version processes transcripts after a meeting ends. It has no notepad or AI summaries. Transcription and authoritative storage run on Memoir Processor 1.2.0 or later; update the processor first. Capture saves system playback and an optional microphone into separate, aligned mono PCM WAV tracks. Requires macOS 15 or later; release builds currently target Apple Silicon.

## Use

After pairing, Memoir opens quietly in the menu bar. Click its waveform icon and Start capture, or press **⇧⌘R** from any app. A name is optional. Starting a capture hides the library and Settings; the menu bar shows only a recording icon, without a duration. Click it again to stop, then choose **Your conversations** to browse finished transcripts. Opening the library brings back the Dock icon; closing it leaves Memoir running in the menu bar. The shortcut needs no keyboard-monitoring permission; if registration fails, the popover explains that capture is still available with a click. Grant Screen & System Audio Recording and microphone access when prompted. Recordings default to `~/Documents/Recordings`. Names are display metadata; renaming keeps the folder path stable.

During a capture, open the menu-bar popover to see speaker avatars. They appear after enough speech and glow for recently detected speech, a few seconds behind the audio. Click an avatar to name the person or use someone already known. The Processor stores voice embeddings locally and can recognize confirmed people in later meetings. Uncertain matches remain unnamed, and the finished transcript retains the names you supplied.

Live speakers require **Memoir Processor 1.5.0**, diarization enabled there, automatic upload, and **Show live speakers during recording** in Recorder Settings. Three-second preview chunks go to the paired Processor while the full recording saves locally. Preview delays do not interrupt capture; disabling live speakers or automatic upload stops previews. The live models download on the Processor automatically on first use. The menu bar itself continues to show only the icon.

For processing, configure the processor URL and API token in Settings. The token is stored in Keychain. Test Connection verifies both service compatibility and authentication. Enable auto-upload to transfer completed recordings. Queued sessions are polled until they complete. Originals remain available locally.

With Tailscale running and HTTPS certificates enabled in its admin console, the processor obtains and renews a trusted certificate automatically. Use its full `https://<machine>.<tailnet>.ts.net:8765` URL and keep both Macs connected to Tailscale. Other deployments need a trusted certificate matching the configured hostname, or deliberate trust of the processor's fallback self-signed certificate. Memoir uses normal system certificate validation.

## Develop and test

```sh
swift test
scripts/build-app.sh
```

Xcode with Swift 6 is required. The release script locates SwiftPM output dynamically, embeds Sparkle, signs its nested helpers, and applies the microphone entitlement. `MEMOIR_SIGNING_IDENTITY` may select a Developer ID Application identity.

Tests cover actual WAV padding, retained buffer ownership, drift-corrected duration, empty recording rejection, metadata, session management, window geometry and chronological month grouping in the local time zone. Real permissions, device changes, sleep/wake, and long-session synchronization still need acceptance testing on the intended recording hardware. Headphones reduce playback bleed; acoustic echo cancellation is not implemented.

## Release and updates

```sh
scripts/notarize-release.sh
# Review, commit and push source, then explicitly publish:
scripts/publish-release.sh
```

Set `MEMOIR_NOTARY_PROFILE` to a saved `notarytool` Keychain profile (on the development Mac the default is `renoir-notary`). No credential is stored in this repository. Sparkle's private signing key lives in Keychain under account `memoir`; its public key is in `Assets/sparkle-public-key`. Keep a secure private-key backup independently of the repository.

Increment `Assets/version` and the monotonically increasing `Assets/build-number` before another release. The notarization script builds, signs, submits, staples and verifies both the app and DMG, then signs the ZIP and appcast. Publishing uploads immutable versioned downloads and replaces only the signed `updates/appcast.xml` asset after verifying the download. CI tests source; it cannot publish unsigned builds.

Sparkle checks automatically and provides **Check for Updates…** in the menu. Automatic installation is off by default. Installation waits for active recording/finalization to end. Old builds without Sparkle require one manual installation before future in-app updates work.
