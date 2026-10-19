# Memoir 1.4.0 — Live voices in Thread

- Adds speaker avatars to the recording popover. Open the menu-bar icon to see who has been detected; a soft glow follows recently detected speech, a few seconds behind the conversation.
- Click a speaker to name them or choose an existing person. The Processor remembers explicitly named voices locally and can recognize them in future meetings. Names carry into the finished transcript.
- Keeps the menu bar quiet, with no duration beside the icon. Speaker cards scroll for larger meetings and the popover adapts to smaller screens.
- Adds **Show live speakers during recording** in Settings. Requires automatic upload and Processor 1.5.0 with diarization enabled. Preview interruptions do not stop recording or affect the full audio saved locally.
- Records short, bounded preview chunks while the complete recording continues independently. Finished transcription still starts after stopping; no live transcript, notepad or summaries are added.

Update Memoir Processor to 1.5.0 first for live speakers. Finished transcription remains compatible with older processors. Requires macOS 15 or later.
