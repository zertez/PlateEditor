# PlateLab for Mac

A first native Mac app in the existing PlateEditor fork. SwiftUI provides the sample library, SwiftData stores sample history, and a bundled WKWebView runs the existing plate workspace offline. No server or account is required. Requires macOS 14 or later; builds for the Mac's architecture (including Apple Silicon).

PlateLab uses light mode throughout, independently of the Mac’s system appearance.

## Build and open

Install Xcode and Node.js, then run from the repository root:

```sh
native/macOS/Scripts/build-app.sh
open dist/PlateLab.app
```

Set `NODE_BIN` if Node is not on your PATH. The script creates `dist/PlateLab.app` and `dist/PlateLab-Mac.zip`. This is a locally ad-hoc signed development build, not a notarized release. Generated assets and personal data are excluded from Git.

## Samples

The tracker opens as one compact table: sample, volume left, taken out today, concentration, protein left, thaw count, and location. Use the **Concentration** selector above the table to choose **mg/mL** or **µg/µL**. These units have the same numerical value; the selected label is remembered and used in the table, editing, sample registration, details, and concentration history. Data exports remain labeled in mg/mL. Numeric readouts use three decimal places (for example, 483.840 µL). Stored measurements, calculations, and data exports retain their full precision; accepting an unchanged prefilled number does not round the stored value.

Double-click **volume** or **concentration** to open a compact dialog centered in the app window. Enter the new value and press Return (or **Next**) to slide to **Reason for change**. Type the reason and press Return (or **Save change**) to save. **Back** slides to the value while keeping your draft reason. The transition uses a short fade when Reduce Motion is enabled. The change is stored with its old value, new value, explanation, date, and time. Escape or Cancel leaves the saved value unchanged. Clicking a sample name opens the full history; double-clicking other cells no longer opens that window. Volume edits replace the total remaining volume, so enter what is left after a transfer or assay. Concentration edits update that tube’s current concentration and remaining protein mass.

1. Choose **Add sample** and enter the name and any known values. Each sample represents one tube; protein records are created in the background in the same save. Extra fields are optional.
2. Click **Taken out today (µL)** beside a sample. Enter only the amount removed in this withdrawal, press Return to slide to the reason, then press **Log withdrawal**. The app subtracts it once from the remaining volume, updates remaining protein mass, and logs the amount, reason, date, and time. The preview shows the resulting balance; Cancel changes nothing. The daily total shows manually logged withdrawals (including plate transfers) for the local calendar day, such as 3.5 µL for an assay. Concentration measurements, balance corrections, and undated history are excluded. Existing concentration-measurement deductions stay in the remaining balance and history.
3. Use **− / +** in the **Thaws** column to update the count directly. **+** asks **“Used 1.5 µL to measure concentration?”**. **Yes** logs one thaw and deducts **1.5 µL**; **No** logs one thaw without deducting volume. Both mark the sample thawed and work even if a previous refreeze was not logged. **Cancel** changes nothing. The same prompt appears in sample details and the **Add thaw…** context-menu action. **−** corrects the latest counted thaw and restores its associated measurement volume, without deleting history or changing storage state. Counts cannot go below zero, and a known balance below 1.5 µL blocks **Yes** without changing either volume or count; **No** remains available.
4. Click a sample name to see its history. Notes, import sources, and additional protein details expand only when needed. Use the row’s **…** menu to mark refrozen, move storage, adjust volume, or archive the sample.

Each tube has independent volume and thaw history. Refreezing does not add a thaw. Unknown previous history stays unknown: the counter shows only newly recorded thaws alongside a question mark. The Add sample form also has − / + controls for its starting count. The **Protein left** column automatically calculates remaining protein mass as volume (µL) × concentration (mg/mL), in µg. Use the **Protein left** selector above the table to show every amount in **µg** or **mg**, or choose **Auto** to show amounts of 1,000 µg or more in mg. Your choice is remembered on this Mac and also applies in sample details. Unit changes use the full calculated amount and do not change sample measurements or history; CSV exports remain explicitly labeled in µg. The value updates with volume and concentration changes; a missing input shows a dash rather than zero.

Starting counts and historical counter entries do not deduct volume retrospectively and do not restore unrecorded measurement volumes when corrected. Registration counters only set the opening count. If a remaining volume has been manually corrected since a thaw, correcting that earlier thaw does not add volume to the newer measured balance.

Leave the volume blank when it is unknown. The app preserves that distinction from zero. A thaw measurement still logs the known 1.5 µL use, while the remaining balance stays unknown. Other withdrawals require a known balance. Double-click the volume cell (or use **Adjust volume**) to establish the first measured balance. Imported history can retain undated events or dates without an invented time. Sample backup version 6 includes group membership and value-change history; versions 1–5 remain readable. CSV exports include current concentration, thaw count, and remaining volume.

## Sample groups

Use **New group** above the table to name a group and select its samples. The visible samples start selected; uncheck any that belong elsewhere. Choose a group in the **Group** selector to see only those tubes, or choose **All samples** or **Ungrouped**. **Edit group** changes the name or membership. A sample’s **… → Move to group** menu moves that tube directly. New samples default to the currently selected group. Empty groups disappear automatically.

Groups organize tubes without merging protein records, volumes, concentrations, or histories. Each sample belongs to at most one group; selecting a sample already in another group moves it. Group names appear beside samples in the all-samples view and can be searched in Samples and Logs. Backups include group membership, and inventory CSV includes a Group column.

## Logs

Choose **Logs**, directly below **Samples** in the sidebar, to see activity across all samples, newest first. Each entry shows the date and time, sample, change, and reason, with experiment, location, and well details when recorded. Search the log or filter to a single sample; click a sample name for its full history. Archived samples retain their logs. Imported dates without a time are marked **Time not recorded**, and undated records appear at the end. The log reads the existing history and updates automatically when an event is saved.

## Plates and sample usage

The Plates tab retains the compact plate overview, compact hover details, recipes, volumes, layout import, and detailed print/export settings. Import an existing `.save` or `.plate.json` once; subsequent edits save automatically on this Mac. The Mac library is separate from your browser library. Browser-only recipes need a `.plate.json` backup to transfer them completely.

**Print / PDF** offers readable details across multiple pages or the whole plate on one landscape page. Choose PDF in the Mac print sheet to save it. The native print operation runs asynchronously so WebKit can finish drawing the saved pages. When checking this flow, reopen the saved PDF (the preview alone is insufficient), check that every well is present, and verify that a second export works after saving or cancelling the first.

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
