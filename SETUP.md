# Plate Setup

This fork adds a visual setup workspace at `index.html`. The original PlateEditor remains available at `Editor.html` for importing results and analysis.

## Open locally

On macOS, double-click **Start Plate Setup.command**. It starts a localhost server and opens your default browser. Keep its Terminal window open while working; Control-C stops it. It needs Python 3. A stable URL (`http://127.0.0.1:8765/`) keeps the browser library in one place. Use the same browser each time. The Codex preview and your regular browser have separate libraries.

Alternatively, run `python3 scripts/serve.py` and open that URL. No npm install is needed for Plate Setup. To also use the original editor, build its assets once with `node scripts/build.mjs` (or `npm run build`). Node 18+ is supported. The legacy Gulp compilation command remains available. `npm run release` builds a portable ZIP in `dist/PlateSetup.zip`, including the ready-to-run original editor and excluding local lab layouts.

## Set up a plate

1. Create a named plate (24, 48, 96, or 384 wells), or import an existing `.save` layout or `.plate.json` backup. Imported layouts become entries in **My plates**.
2. Add a condition. Under **Contents per well**, choose **Reagent** for a final concentration (µM, mM, nM, pM, or M) or **Protein** for a mass per well (µg, mg, ng, or pg). **Volume & note** lets you enter a volume in µL or a note for either type. An optional target volume is compared with the sum of the entered volumes.
3. Set the replicate count, direction, and number of empty wells between replicates. Click **Place replicates**, then click a starting well. The preview shows the proposed placement. Occupied and used wells are protected.
4. For irregular positions, click, drag, Shift-click a rectangle, or Ctrl/Command-click individual wells, then **Apply to selected wells**. Row and column headers select whole rows or columns. When editing an existing condition, applying a changed name, recipe, notes, color, or target volume affects only the selected wells; other wells keep the original condition. A separate condition is created when needed, with a variant suffix if its name is unchanged. Clear wells first to replace an unrelated condition. Undo/redo covers plate changes during the current session.
5. The editor opens with the original compact **Overview**: individual colored wells show condition numbers and tagged concentrations, and the whole plate fits in its panel. Hover or keyboard-focus a well to see its complete condition name, recipe, volumes, concentrations, and notes at normal size. Click to select it or use **View well details**. Earlier oversized display preferences reset to Overview once, without changing saved plates or recipes. **Well contents** and **Full details** remain optional individual-well views. **Customize well display** controls the detailed fields, text size, card width, and hiding empty outer rows/columns. **Expand plate view** provides more room by hiding the editing panels. Display preferences persist separately from experimental data.
6. Click a condition or **Edit recipe for selected wells** to load its recipe. **Apply to selected wells** and **Place replicates** leave other wells unchanged. Only **Update all wells using this condition** changes the shared recipe for every well using it. **Use recipe for a new condition** also makes a separate variant. Recipe drafts survive refresh.

Mark selected wells **used** to protect them. Layouts with condition names starting with `USED` receive protection on import. Unlock them explicitly before clearing or assigning. Duplicating a plate keeps all layout, recipe, and used-well information.

A concentration series creates separate conditions in rows (or columns) with the supplied *tagged* concentrations. It copies the entered recipe unchanged; it does not calculate or claim the correct reagent volumes for a dilution series.

## Saving and compatibility

The library and recipe drafts autosave to localStorage in the current browser and origin. This is device-local storage, not cloud sync or permanent backup. Download a `.plate.json` backup to keep a separate copy or move browsers/devices. Storage errors are shown explicitly. CSV export includes one row per reagent per well, concentrations, entered totals, target volumes, and used status. **Print / PDF** first lets you choose an export layout independently of the editor. **Readable details** divides the plate into sections of up to four columns, repeats column headings, and retains your chosen detail fields at a readable size across multiple pages. **Fit whole plate on one page** scales every visible well and its chosen fields onto a single A4 landscape page; its text can be small. The one-page export uses the full individual-well content, even when the editor shows the compact Overview. Use A4 landscape with browser headers/footers disabled, then choose Save as PDF in the browser print dialog. Condition notes are saved on conditions as `SetupNotes` and included in backups.

Old layouts retain their original well positions, labels, colors, concentration values (including zero), units, layers, and range metadata. Ingredient volumes cannot be inferred from old labels and are left blank. Recipe extensions are stored on conditions as `SetupRecipe` and `SetupTargetVolume`; backups also preserve used-well markings, notes, and drafts. Indexed ranges can be viewed and preserved; edit their range-specific configuration in the original editor.

**Open in original editor** passes an analysis copy through sessionStorage without downloading/uploading a `.save` file. That copy supports upstream analysis. Edits or saves in the original editor do **not** update the setup library, and upstream saves omit recipe extensions. Use **Back to Plate Setup** to return to the original saved recipe.

## Development and local data

`node --test tests/setup/*.test.cjs` runs model tests. If an ignored `local-layouts/index.json` exists, each entry is also checked for lossless import/backup round trips. Its format is an array of `{source, title, layout}` entries. `source` is a stable identifier; seeds are imported only once per browser. This local directory is ignored by Git and must not be included in public packages.

The new UI is plain HTML, CSS, and JavaScript with no runtime packages, remote fonts, or network writes. The optional local seed fetch only reads from the same origin. `scripts/build.mjs` builds upstream scripts and styles without installing the old Gulp dependency tree. `scripts/serve.py` binds only to localhost and rejects dot-directory and directory-listing requests.

The upstream MIT license and attribution are retained. See the original README below for legacy features and scientific citation.
