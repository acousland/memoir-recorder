# Memoir – Mac Menu Bar Meeting Recorder Product Specification

## 1. Overview

Memoir is a lightweight macOS menu bar application that allows users to record meeting audio with a single click. The app captures:

- System audio (via Core Audio taps)
- Optional microphone input

Recordings are stored locally and optionally synced to a Mac Mini for later transcription and analysis.

**Product name:** Memoir

**Primary goal:** Reliable, zero-friction meeting recording.

**Non-goals (v1):**
- Live transcription
- Real-time streaming
- Advanced diarization

---

## 2. Target User Experience

### First Launch

1. User installs and opens app
2. Menu bar icon appears
3. User clicks icon → sees “Start Recording”
4. On first recording:
   - macOS prompts for:
     - System Audio Recording permission
     - Microphone permission (if enabled)

### Daily Use

Menu bar dropdown:

- Start Recording
- Stop Recording
- Settings
- Quit

While recording:
- Icon changes (e.g., red dot)
- Tooltip: “Recording…”

After stopping:
- Notification: “Recording saved”
- Optional: “Uploading to Mac Mini…”

---

## 3. Functional Requirements

### 3.1 Recording

- One-click start/stop
- Capture:
  - System audio via Core Audio tap
  - Microphone via AVAudioEngine or Core Audio input
- Record both as **separate tracks**
- No dependency on network

### 3.2 File Output

Each session creates a folder:

```
YYYY-MM-DD_HH-MM-SS_<SessionName>/
  system.wav
  mic.wav
  metadata.json
```

### 3.3 Metadata

Example:

```json
{
  "session_id": "uuid",
  "started_at": "ISO8601",
  "ended_at": "ISO8601",
  "sample_rate": 16000,
  "channels": {
    "system": 1,
    "mic": 1
  },
  "device": "MacBook Pro",
  "app_version": "1.0.0"
}
```

### 3.4 Settings

- Toggle microphone recording (on/off)
- Recording location (default: ~/Documents/Recordings)
- Audio format:
  - WAV (default)
  - Optional: FLAC
- Sample rate (default: 16kHz)
- Auto-upload toggle
- Target Mac Mini address

---

## 4. System Architecture

### 4.1 High-Level

```
Menu Bar App
  ├── Recording Controller
  ├── Audio Capture Layer
  ├── File Writer
  ├── Session Manager
  └── Upload Manager (optional)
```

### 4.2 Components

#### Recording Controller
- Handles Start/Stop lifecycle
- Coordinates all subsystems

#### Audio Capture Layer
- Core Audio tap → system audio
- AVAudioEngine → microphone
- Outputs PCM buffers

#### File Writer
- Writes buffers to disk
- Ensures safe flushing
- Handles file rotation if needed

#### Session Manager
- Creates session folder
- Generates metadata
- Tracks session state

#### Upload Manager
- Handles background upload to Mac Mini
- Retry queue

---

## 5. Audio Pipeline

### 5.1 System Audio

- Use Core Audio tap (macOS 14.2+)
- Attach tap to default output device
- Configure as input source via aggregate device

### 5.2 Microphone

- Capture via AVAudioEngine input node
- Convert to mono PCM

### 5.3 Format

- PCM16
- 16kHz sample rate
- Mono per track

### 5.4 Synchronization

- Use shared clock/timestamps
- Write timestamps into metadata if needed

---

## 6. Recording Lifecycle

### Start Recording

1. Create session folder
2. Initialize audio capture
3. Open file handles
4. Begin writing buffers
5. Update UI state

### Stop Recording

1. Stop audio capture
2. Flush buffers
3. Close files
4. Write metadata
5. Trigger upload (optional)

---

## 7. Permissions

Required:

- `NSAudioCaptureUsageDescription` (system audio)
- `NSMicrophoneUsageDescription`

Behavior:
- Prompt on first use
- If denied → show guidance UI

---

## 8. Upload to Mac Mini (Optional)

### Strategy

- Upload only after recording completes
- Never block recording on network

### Options

#### Option A: SMB Share
- Copy session folder to shared directory

#### Option B: HTTP Upload
- POST session folder to Mini service

### Retry Logic

- Queue failed uploads
- Retry with exponential backoff
- Mark session as:
  - pending
  - uploaded
  - failed

---

## 9. Error Handling

### Audio Failure
- Show: “Audio capture failed”
- Stop recording safely

### Disk Full
- Stop recording
- Alert user

### Permission Denied
- Disable recording
- Provide instructions

### Crash Recovery
- On launch:
  - detect incomplete session
  - finalize files if possible

---

## 10. Performance Considerations

- Minimal CPU usage
- Use buffered writes
- Avoid blocking main thread
- Use background queues for I/O

---

## 11. UI Specification

### Menu Bar Icon States

- Idle: neutral icon
- Recording: red dot indicator

### Dropdown

Idle:
- Start Recording
- Settings
- Quit

Recording:
- Stop Recording
- Status: Recording…

---

## 12. Future Enhancements

- Auto-detect meeting apps
- App-specific capture (Zoom/Chrome)
- Automatic naming (calendar integration)
- Post-record transcription trigger
- Speaker diarization
- Searchable archive UI

---

## 13. Tech Stack Recommendation

- Language: Swift
- Frameworks:
  - AppKit / SwiftUI (menu bar UI)
  - Core Audio (taps)
  - AVFoundation (mic capture)
- Storage: local filesystem
- Optional backend: lightweight HTTP server on Mac Mini

---

## 14. MVP Scope

Deliver:

- Menu bar app
- Start/Stop recording
- System audio capture
- Optional mic capture
- Local file storage

Exclude:

- Streaming
- Transcription
- Diarization

---

## 15. Success Criteria

- Recording never fails due to network
- One-click operation
- Clean audio files generated
- Minimal user setup

---

This specification defines a reliable, minimal, and extensible foundation for Memoir, a local-first meeting recording system.

