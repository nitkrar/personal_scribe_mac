# Manual Audio Level Verification

1. Grant microphone permission, instantiate `AVAudioCaptureService()`, and call `start()`.
2. Subscribe to `await audioLevelStream()` immediately after `start()`.
3. Stay silent for 1 second and confirm emitted levels stay at `0.0`.
4. Speak for 2 to 3 seconds and confirm levels update roughly every 100 ms and stay within `[0, 1]`.
5. Stop capture and confirm the level stream finishes.
6. Repeat through `SessionCoordinator.audioLevelStream()` and confirm the final published level returns to `0.0` when recording stops.
