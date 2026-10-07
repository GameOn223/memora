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
- [ ] "Memora capture" appears in Accessibility settings at all. Turn it on, then tap the tile: the shade closes, no dialog appears, and the screenshot is saved.
- [ ] Check the accessibility entry's description in system settings. It explains that the service only takes a screenshot when you tap the tile.
- [ ] Tap the tile twice in a row with accessibility capture on. The second tap runs into the system's one-per-second limit and falls back to the consent dialog instead of failing quietly.
- [ ] Tap the tile while Memora is closed. The capture still lands in Memories the next time you open the app, or sooner through the background worker.
- [ ] Turn notifications off for Memora, then capture. The image is still saved and a toast says so, so a capture is never silent.
- [ ] Kill the app (`adb shell am force-stop io.github.gameon223.memora`) right after a capture, before it is filed. The next launch files it, and the image appears once, not twice.

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

## Generative models on the device

Needs a Gemma model file on the phone. Get them from Hugging Face, accept the Gemma terms there, and push them with `adb push`:

```bash
# Text only, about 550 MB
adb push gemma-3-1b-it-int4.task /sdcard/Download/
# Text and images, about 3 GB
adb push gemma-3n-E2B-it-int4.litertlm /sdcard/Download/
```

Downloading it:

- [ ] Settings, on-device models: paste a Hugging Face read token, save it. The row turns from Import into Download.
- [ ] Download Gemma 3 1B. The bar moves the whole way and the row ends up installed, with the real file size.
- [ ] Minimise Memora while the download runs. A notification shows the model name and the percentage, and it keeps climbing.
- [ ] Leave it minimised for several minutes with other apps open. The download finishes rather than being killed, and the notification says it is ready.
- [ ] Tap Cancel on the notification. The download stops, the notification goes, and `adb shell run-as io.github.gameon223.memora ls files/models/imported` shows nothing left behind.
- [ ] Reopen settings while a download runs. The row shows it downloading with the bar where it should be, and does not start a second one.
- [ ] Force-stop Memora mid-download, then reopen it. Nothing claims to be downloading that is not, and the model is either installed or offered again.
- [ ] Turn notifications off for Memora, then download. It still works, which is the point of the toast fallback.
- [ ] Save a token with a character missing. The download comes back saying the token was not taken, and nothing is left in `files/models/imported`.
- [ ] Use a valid token on an account that has not accepted the Gemma licence. It says the licence, not the token, and points at the model page.
- [ ] Try Gemma 3n E2B without a granted access request. It says that one is granted by hand, rather than telling you to try again.
- [ ] Turn the network off halfway through a download. It reports a download that stopped, keeps nothing, and downloading again starts clean.
- [ ] Check the token is not in an export: run an export and grep it for `hf_`.

Bringing a file in:

- [ ] Settings, on-device models: import a model. The system file picker opens, and the chosen file ends up listed with its real size.
- [ ] Import from Google Drive rather than Downloads. The copy still succeeds, which is the whole point of going through the picker.
- [ ] Watch the bar during a 3 GB copy. It moves the whole way through, reaches the end, and the row then reads as installed.
- [ ] Import from a source that reports no size (some cloud providers do this). The bar runs with no end instead of sitting at zero, and the import still finishes.
- [ ] Pick something that isn't a model (a photo, a `.gguf`, a zip). Memora names the three extensions it accepts and copies nothing.
- [ ] Import the same file twice. The second copy is listed under a counted name, not silently replacing the first.
- [ ] Kill the app during a 3 GB copy (`adb shell am force-stop io.github.gameon223.memora`). `adb shell run-as io.github.gameon223.memora ls files/models/imported` shows only a `.part` file, the model is not offered, and importing again works.
- [ ] Fill the phone's storage to under the model's size, then import. Memora says how much room is needed and how much is free, and leaves nothing behind.
- [ ] Remove an imported model while it is loaded. It unloads, the file is gone, and generating afterwards asks for a model instead of crashing.

Generating:

- [ ] Select the on-device provider for chat and ask a question. Text streams in rather than appearing all at once.
- [ ] Ask a second question. The answer does not refer back to the first one, because each turn gets a fresh session.
- [ ] Cancel mid-answer. The text stops within a second or two, and the next question works.
- [ ] Send a question while one is still generating. The second one is refused with a clear message and the first keeps streaming.
- [ ] With the vision-capable model loaded, process a screenshot with text. The summary and extracted facts come from the image, not from OCR alone.
- [ ] With the text-only model loaded, try the vision capability. It is reported as unavailable instead of sending images to a model that can't read them.
- [ ] The image path in particular. `libmediapipe_tasks_jni.so` is excluded from the APK because nothing on this path loads it. An `UnsatisfiedLinkError` in `adb logcat` when an image is sent means that call was wrong and the exclusion in `app/build.gradle.kts` has to come out.

Memory and lifetime, which is where this breaks if it breaks:

- [ ] On a phone with 8 GB or more, load the 3 GB model. It loads, and `adb shell dumpsys meminfo io.github.gameon223.memora` shows the growth outside the Java heap.
- [ ] On a phone with 4 GB, try the 3 GB model. Memora refuses it with a message naming the device's memory, and the process stays alive. This is the failure that matters: a crash here means the headroom check is too generous.
- [ ] Load a model, open ten heavy apps, then come back. Memora has freed the model and loads it again on the next question.
- [ ] Load a model, press home, and watch `adb logcat` for the trim callback. The model is released.
- [ ] Run a background processing batch with the on-device vision provider selected and the small model. It finishes inside the worker's budget. Then try it with the 3 GB model and record what happens, since that is the combination the architecture advises against.
- [ ] After a worker finishes, `adb shell dumpsys meminfo` shows the model is no longer resident, because the worker's engine was the last one.
- [ ] Rotate the screen mid-generation. The stream keeps going and lands in the right conversation.

## Export and deletion

- [ ] Settings, export: the system save dialog appears. Save to Downloads and open the zip. It has `manifest.json`, `memories.jsonl`, `conversations.jsonl` and an `images/` folder.
- [ ] Cancel the save dialog. The app reports nothing was saved and leaves no zip in the cache.
- [ ] Delete all data. Memories, images, thumbnails and the inbox are gone, and `adb shell run-as io.github.gameon223.memora ls files` shows empty folders.

## Privacy checks

- [ ] `adb shell dumpsys package io.github.gameon223.memora | grep -A20 "requested permissions"` lists only the permissions in the manifest.
- [ ] With local-only mode on, capture and process an image, then check `adb shell dumpsys netstats` or a proxy: no outgoing requests.
- [ ] In a release build, `adb logcat` during import and processing shows no extracted text, prompts or API keys.
- [ ] Back up and restore with `adb backup` (or a device transfer): Memora's data is not included.
