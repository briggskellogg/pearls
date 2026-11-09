# Pearls 0.1 — native acceptance checks

For released build 3, the core suite (20 tests), Mac compilation, iOS Simulator compilation, Mac Release build/signature, installation, and Mac appearance/font checks passed on November 8, 2026. Upcoming build 4 has passed 36 core tests with synthetic local sync folders plus Mac Debug and iOS Simulator compilation; Mac Release installation/runtime, signing/TestFlight, and the live private-sync checks below remain pending, as do other runtime journeys unless marked in [STATUS.md](STATUS.md). Compilation does not establish behavior on a physical iPhone.

## Build gate

- Run `scripts/validate-apple.sh` on a Mac. All core tests, Mac compilation, and iOS Simulator compilation must pass.
- Build/run both app schemes in Xcode. Confirm PP Neue Montreal resolves for interface/brand text, PP Neue York for headings/reading, all five bundled fonts register, and the icon catalog has no missing-slot errors.
- Verify that the iPhone archive embeds `PearlsShare.appex` with matching team and App Group entitlements.

## Core user journeys

1. Save a note, quit the app, reopen, and confirm exact content. Edit it, cancel/discard deliberately, and save another edit. A failed save must keep the draft available.
2. Save a full HTTPS link and open its destination. Confirm pasted prose containing a URL remains a note rather than losing its text.
3. Import an image and a PDF. Quit/relaunch, inspect both, then share the originals and compare their bytes with the source files. Search for a recognizable word from each after indexing finishes.
4. Mark and unmark favorites. Check that destination colors persist in both selection states and that favorite controls change outline/fill state.
5. Remove a pearl, use Undo, remove it again, quit/relaunch, then restore from Settings → Recently Deleted.
6. Export a small mixed collection. Import it into an empty test installation. Verify notes, titles, favorites, original bytes, source links, and deleted items. Import it again; identical captures must not duplicate. Conflicting same-ID records must report an error without partial record import.
7. Test the documented 25 MiB file and 100 MiB archive limits. Oversized input must show an error and retain the existing collection.

## iPhone capture

- Share a Safari link, selected plain text, a Photos image, a PDF from Files, and several image providers. Confirm Save is explicit, Cancel saves nothing new, and the main app ingests successful captures on its next foreground activation.
- Interrupt an extension session after one of multiple captures is committed. Retry or reopen Pearls; successful captures must appear once.
- Share a file named `CAPTURE.JSON` to confirm the original cannot collide with inbox metadata.
- Test a file-provider loading failure, a file larger than 25 MiB, and a missing App Group configuration. Preserve errors and staged data until deliberate cancellation; never show false success.

## Private iCloud folder sync — pending build 4

- Connect a dedicated private iCloud Drive Pearls folder through Settings on both Apple devices; verify that the same folder/collection is selected. No folder is connected yet.
- Save a synthetic note and attachment on one device, leave both apps active, wait for provider completion, and verify exact content/original bytes on the other. Repeat in the reverse direction and after relaunch.
- Edit while offline on both devices, reconnect, and verify preserved conflict copies/edits, deletions, restoration, favorites, and originals without silent loss.
- Interrupt a provider download/upload and retry. An incomplete folder or a cloud conflict must not produce false success or erase the local library.
- Disconnect and confirm that both local and cloud files remain. Reconnect to the same collection and confirm no duplicates. Do not delete cloud history as a reset.
- Reject the project-source/Proton source folder, a shared-with-other-people folder, unrelated contents, and redirected paths; preserve existing files.
- On Windows with the same personal iCloud account, finish downloading and inspect the synthetic JSON/originals without editing protocol files. Record file access separately from native Apple app testing; there is no Windows Pearls editor.
- Verify saved content is absent from source commits, source mirrors, and release packages. Run the private-data, source-sync, and release-package guard suites with synthetic inputs.

## Presentation and accessibility

- Test a compact iPhone and a larger iPhone, portrait/landscape, dark/light appearances, VoiceOver, and accessibility text sizes.
- Check that search, save, detail dismissal, original-file sharing, and settings remain reachable when the keyboard is visible.
- On Mac, resize from the minimum window to a large display; test Command-N, Command-F, Command-O, file drop, and a dropped web URL.
- Confirm neutral outlines remain legible and all primary controls keep adequate hit areas.

## Delivery gate

Confirm successful signed archive, App Store Connect upload and processing, privacy/compliance responses, and assignment of that exact build to the intended TestFlight group. Verify invitation delivery to the confirmed tester identity and launch on the user's physical iPhone. Verify `Pearls.app` exists in the intended Mac Applications directory and launches with saved data intact. Record actual evidence; do not mark these complete from source configuration alone.
