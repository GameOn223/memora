# Testing Memora on a device

Most of Memora is covered by host tests (`flutter test`, `dart test`, `./gradlew :app:testDebugUnitTest`). The parts that talk to Android can only be checked on a real phone. Work through this list before a release, and after any change to capture, the gallery, background work or on-device inference.

Build and install a debug APK:

```bash
cd app
flutter build apk --debug --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Record the device model and Android version with your results. Where behavior differs by version, the checklist says so.

## Gallery import

- [ ] First launch, Add tab: the permission prompt appears. Allow it, and the grid fills with your images, newest taken first.
- [ ] Deny the prompt instead: the Add tab offers "Allow access" and "Pick with system picker". The picker works without any permission.
- [ ] Deny twice so Android stops asking: the Add tab offers to open app settings, and returning from settings with access granted shows the grid.
- [ ] Android 14 or newer: choose "Select photos" and pick three images. Only those images appear in the grid. Asking again lets you add more.
- [ ] Select several images and add them. The toast counts what was added.
- [ ] Add the same images again. They are counted as already in Memora and no duplicates appear in the grid.
- [ ] A photo taken in another month is filed under the month it was taken, with the "added later" glyph.
- [ ] A photo with rotation EXIF shows upright in the grid and on the detail screen, with sensible dimensions.
- [ ] Add 200 images in one go. The app stays responsive, and every image gets a thumbnail.

## Quick Settings tile

- [ ] Settings, capture section: "Add tile" puts the Memora tile in the shade on Android 13 or newer. On older versions, add it by hand from the shade editor.
- [ ] Tap the tile with accessibility capture off: Android asks for screen capture consent. Accept. A "Saved to Memora" notification appears, then "Filed in Memora", and the screenshot shows up in Memories.
- [ ] Tap the tile and cancel the consent dialog: a "Capture cancelled" notification appears and nothing is saved.
- [ ] Turn on "Memora capture" in Accessibility settings, then tap the tile: the shade closes, no dialog appears, and the screenshot is saved.
- [ ] Check the accessibility entry's description in system settings. It explains that the service only takes a screenshot when you tap the tile.
- [ ] Tap the tile while Memora is closed. The capture still lands in Memories the next time you open the app, or sooner through the background worker.
- [ ] Turn notifications off for Memora, then capture. The image is still saved, and no notification appears.

## Share to Memora

- [ ] Share one image from another app: a toast says one image was saved, and it appears in Memories with source `share`.
- [ ] Share several images at once: the toast counts them, and all of them appear.
- [ ] Share something that isn't an image: Memora says it only accepts images and saves nothing.
- [ ] Share from an app that grants a one-time URI (Gmail, Chrome downloads). The copy still succeeds.

## Processing queue

- [ ] Configure a vision provider, add images, and set "As you add". Processing starts within a minute and the queue screen counts down.
- [ ] Set "Overnight". The queue screen says when it will run. Force a run with:
      `adb shell cmd jobscheduler run -f io.github.gameon223.memora <job id>`
      (list jobs with `adb shell dumpsys jobscheduler | grep memora`).
- [ ] "Process now" runs immediately even outside the window and with the phone unplugged.
- [ ] Pause during a run. The item in progress finishes, then processing stops. Nothing is left in `processing` state.
- [ ] Turn on airplane mode with a cloud provider selected. The queue waits for a connection instead of failing every item.
- [ ] Overnight with a cloud provider: processing waits for Wi-Fi. On mobile data it stays queued.
- [ ] Kill the app during processing (`adb shell am force-stop io.github.gameon223.memora`). The item goes back to the queue after its lease expires and is picked up again.
- [ ] A batch that takes longer than nine minutes continues in a second run without losing items.

## On-device inference

- [ ] Settings, on-device models: download bge-small-en v1.5. Progress moves, and the model ends up as "Ready".
- [ ] Interrupt the download (airplane mode halfway). The model goes back to "Not downloaded" and no partial file is left in `files/models/`.
- [ ] Reindex embeddings after the download. Memories become searchable by meaning, and the detail screen shows the embedding provenance line.
- [ ] Select the on-device vision provider and process an image with text. The extracted text matches the screenshot.
- [ ] Remove the model. Semantic search stops being offered, and text search still works.

## Export and deletion

- [ ] Settings, export: the system save dialog appears. Save to Downloads and open the zip. It has `manifest.json`, `memories.jsonl`, `conversations.jsonl` and an `images/` folder.
- [ ] Cancel the save dialog. The app reports nothing was saved and leaves no zip in the cache.
- [ ] Delete all data. Memories, images, thumbnails and the inbox are gone, and `adb shell run-as io.github.gameon223.memora ls files` shows empty folders.

## Privacy checks

- [ ] `adb shell dumpsys package io.github.gameon223.memora | grep -A20 "requested permissions"` lists only the permissions in the manifest.
- [ ] With local-only mode on, capture and process an image, then check `adb shell dumpsys netstats` or a proxy: no outgoing requests.
- [ ] In a release build, `adb logcat` during import and processing shows no extracted text, prompts or API keys.
- [ ] Back up and restore with `adb backup` (or a device transfer): Memora's data is not included.
