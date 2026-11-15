# PlateLab for Mac

A first native Mac app in the existing PlateEditor fork. SwiftUI provides the sample library, SwiftData stores sample history, and a bundled WKWebView runs the existing plate workspace offline. No server or account is required. Requires macOS 14 or later; builds for the Mac's architecture (including Apple Silicon).

## Build and open

Install Xcode and Node.js, then run from the repository root:

```sh
native/macOS/Scripts/build-app.sh
open dist/PlateLab.app
```

Set `NODE_BIN` if Node is not on your PATH. The script creates `dist/PlateLab.app` and `dist/PlateLab-Mac.zip`. This is a locally ad-hoc signed development build, not a notarized release. Generated assets and personal data are excluded from Git.

## Samples

1. Create a protein batch with its construct, batch ID, optional concentration, buffer, preparation date, and notes.
2. Register each existing tube with a unique ID, current remaining volume in µL, optional concentration in mg/mL, current state, storage location, and previous thaw count. Leave the count blank if the earlier history is unknown. Registration does not transfer material from another tube.
3. Record withdrawals, thawing, freezing, storage moves, and volume corrections. Corrections require a reason. Each action adds a dated history entry; archiving preserves the history.

An aliquot inherits the batch concentration at registration and keeps its own concentration snapshot. Remaining protein mass is calculated as volume (µL) × concentration (mg/mL), in µg. Each tube has independent volume and thaw history. Marking a frozen tube thawed adds one thaw; refreezing does not add another. Unknown previous history stays unknown.

Leave the volume blank when it is unknown. The app preserves that distinction from zero and requires a measured volume before recording withdrawals. Use **Correct volume** with a reason to establish the first known balance. Imported history can retain undated events or dates without an invented time. Sample backup version 2 preserves these fields; version 1 backups remain readable.

## Plates and sample usage

The Plates tab retains the compact plate overview, compact hover details, recipes, volumes, layout import, and detailed print/export settings. Import an existing `.save` or `.plate.json` once; subsequent edits save automatically on this Mac. The Mac library is separate from your browser library. Browser-only recipes need a `.plate.json` backup to transfer them completely.

Select the destination wells, then choose **Record completed sample transfer…** to record the actual total volume used from a source aliquot. The event retains the plate ID, title, and selected well names. Planning and editing a plate never deduct inventory. This first version records transfers in the sample history; it does not automatically fill well recipes or calculate pipetting transfers.

The original editor opens an analysis copy. Its changes do not update saved recipes. The native save/print integrations apply to the Plate Setup workspace; original-editor downloads and analysis windows remain available in the browser version.

## Local storage and backups

Data live in `~/Library/Application Support/PlateLab/`:

- `Samples.store` and its SQLite sidecars: sample library and event history.
- `plates.json`: plate library.
- `plate-display.json`: plate display preferences.

Use **Backups & export → Export samples backup** to export all sample records and history as JSON. Imports add missing batches, skip identical records, and reject conflicting history without overwriting the existing library. CSV is an inventory snapshot, not a full backup. Plate backups are exported separately from the Plates tab. There is no automatic backup schedule, cloud sync, or shared team database in this version.

## Validation

```sh
xcrun swift test --package-path native/macOS --scratch-path .local/macos-build --disable-sandbox
node --test tests/setup/*.test.cjs
```

Swift tests cover withdrawal limits, corrections, independent aliquots, thaw transitions, unknown history, archive restrictions, backup round trips, invalid/conflicting imports, and database reopen. To use an isolated manual test library, launch the executable with `--data-directory /absolute/path/to/test-library`.
