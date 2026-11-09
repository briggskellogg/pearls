# Pearls 0.1 — native acceptance checks

The core suite (20 tests), Mac compilation, iOS Simulator compilation, Mac Release build/signature, installation, and initial Mac launch passed on November 8, 2026. The detailed runtime journeys below remain pending unless marked in [STATUS.md](STATUS.md). Compilation does not establish behavior on a physical iPhone.

## Build gate

- Run `scripts/validate-apple.sh` on a Mac. All core tests, Mac compilation, and iOS Simulator compilation must pass.
- Build/run both app schemes in Xcode. Confirm the bundled font resolves to PP Neue York and the icon catalog has no missing-slot errors.
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

## Presentation and accessibility

- Test a compact iPhone and a larger iPhone, portrait/landscape, dark/light appearances, VoiceOver, and accessibility text sizes.
- Check that search, save, detail dismissal, original-file sharing, and settings remain reachable when the keyboard is visible.
- On Mac, resize from the minimum window to a large display; test Command-N, Command-F, Command-O, file drop, and a dropped web URL.
- Confirm neutral outlines remain legible and all primary controls keep adequate hit areas.

## Delivery gate

Confirm successful signed archive, App Store Connect upload and processing, privacy/compliance responses, and assignment of that exact build to the intended TestFlight group. Verify invitation delivery to the confirmed tester identity and launch on the user's physical iPhone. Verify `Pearls.app` exists in the intended Mac Applications directory and launches with saved data intact. Record actual evidence; do not mark these complete from source configuration alone.
