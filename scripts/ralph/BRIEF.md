# Miqat

A local-only iOS prayer-lock alarm. No account, no cloud, no network.

When an alarm fires the phone becomes a full-screen locked chapel. No slide-to-stop. No one-tap snooze. The only exits: complete the rite, or the emergency exit (5-second long-press + typed install-time phrase).

Name: **Miqat** (an appointed boundary). Not Vigil. Not Fajr.

Home is a sacred chapel with a Canvas clock, not a DatePicker screenshot. User can create an alarm with time, repeat days, prayer pack (1-4 rakaat: stand, bow, prostrate, sit), recitation, seal pack.

Simulator assist: three-finger tap completes the current posture (DEBUG + simulator only).

Compile rules:
- `Miqat.xcodeproj` with scheme Miqat
- Destination: `platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5`
- Every referenced type must exist (`SealCameraController` if mentioned, `AlarmDraft` if mentioned)
- No fake SwiftData preview inits
- `AVSpeechSynthesisDelegate` requires `import AVFAudio`
- No missing modules, no clamped/unknown APIs

Visual: oil-lamp chapel, dark stone, warm wick, breath ring during holds. This is a companion to prayer, not a generic Clock.app skin.
