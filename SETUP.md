# Plate Setup

This fork adds a visual setup workspace at `index.html`. The original PlateEditor remains available at `Editor.html` for importing results and analysis.

## Open locally

On macOS, double-click **Start Plate Setup.command**. It starts a localhost server and opens your default browser. Keep its Terminal window open while working; Control-C stops it. It needs Python 3. A stable URL (`http://127.0.0.1:8765/`) keeps the browser library in one place. Use the same browser each time. The Codex preview and your regular browser have separate libraries.

Alternatively, run `python3 scripts/serve.py` and open that URL. No npm install is needed for Plate Setup. To also use the original editor, build its assets once with `node scripts/build.mjs` (or `npm run build`). Node 18+ is supported. The legacy Gulp compilation command remains available. `npm run release` builds a portable ZIP in `dist/PlateSetup.zip`, including the ready-to-run original editor and excluding local lab layouts.

## Set up a plate

1. Create a named plate (24, 48, 96, or 384 wells), or import an existing `.save` layout or `.plate.json` backup. Imported layouts become entries in **My plates**.
2. Add a condition. Enter each reagent, its volume in µL, and an optional concentration or note. Blank volumes remain unknown; the app totals only entered volumes. An optional target volume shows the amount remaining or over target. These are recorded volumes, not dilution calculations.
3. Set the replicate count, direction, and number of empty wells between replicates. Click **Place replicates**, then click a starting well. The preview shows the proposed placement. Occupied and used wells are protected.
4. For irregular positions, click, drag, Shift-click a rectangle, or Ctrl/Command-click individual wells, then **Apply to selected wells**. Row and column headers select whole rows or columns. Clear assigned wells before giving them a different condition. Undo/redo covers plate changes during the current session.
5. Click a well to inspect its full recipe. **Full details** displays the complete condition name, type, tagged concentration, ingredients, concentrations/notes, volumes, totals, target volume, and condition notes directly inside each well. **Customize well display** lets you choose fields, well width, text size, and whether to hide empty outer rows/columns. Interior gaps and coordinates are preserved. **Expand plate view** hides the editing panels until you restore them or edit a condition. **Overview** and **Contents & volumes** remain available as presets. Display preferences persist separately from the plate data.
6. Click a condition to edit its recipe for every well using it. **Use recipe for a new condition** makes a separate variant without changing the original wells. Recipe drafts survive refresh; click **Save condition** or place the condition to apply the draft to wells.

Mark selected wells **used** to protect them. Layouts with condition names starting with `USED` receive protection on import. Unlock them explicitly before clearing or assigning. Duplicating a plate keeps all layout, recipe, and used-well information.

A concentration series creates separate conditions in rows (or columns) with the supplied *tagged* concentrations. It copies the entered recipe unchanged; it does not calculate or claim the correct reagent volumes for a dilution series.

## Saving and compatibility

The library and recipe drafts autosave to localStorage in the current browser and origin. This is device-local storage, not cloud sync or permanent backup. Download a `.plate.json` backup to keep a separate copy or move browsers/devices. Storage errors are shown explicitly. CSV export includes one row per reagent per well, concentrations, entered totals, target volumes, and used status. Print/PDF uses the browser print dialog. The default **Readable details** print layout divides the plate into sections of up to four columns, repeats column headings, and retains your chosen detail fields at a readable size. **Whole plate** remains an option for a compact overview. Long printed plates may span several pages. Condition notes are saved on conditions as `SetupNotes` and included in backups.

Old layouts retain their original well positions, labels, colors, concentration values (including zero), units, layers, and range metadata. Ingredient volumes cannot be inferred from old labels and are left blank. Recipe extensions are stored on conditions as `SetupRecipe` and `SetupTargetVolume`; backups also preserve used-well markings, notes, and drafts. Indexed ranges can be viewed and preserved; edit their range-specific configuration in the original editor.

**Open in original editor** passes an analysis copy through sessionStorage without downloading/uploading a `.save` file. That copy supports upstream analysis. Edits or saves in the original editor do **not** update the setup library, and upstream saves omit recipe extensions. Use **Back to Plate Setup** to return to the original saved recipe.

## Development and local data

`node --test tests/setup/*.test.cjs` runs model tests. If an ignored `local-layouts/index.json` exists, each entry is also checked for lossless import/backup round trips. Its format is an array of `{source, title, layout}` entries. `source` is a stable identifier; seeds are imported only once per browser. This local directory is ignored by Git and must not be included in public packages.

The new UI is plain HTML, CSS, and JavaScript with no runtime packages, remote fonts, or network writes. The optional local seed fetch only reads from the same origin. `scripts/build.mjs` builds upstream scripts and styles without installing the old Gulp dependency tree. `scripts/serve.py` binds only to localhost and rejects dot-directory and directory-listing requests.

The upstream MIT license and attribution are retained. See the original README below for legacy features and scientific citation.
