# Notebooks Feature — Implementation Plan

**Date:** March 2026
**Status:** Phase 3 complete (combined into Learning Space)
**Estimated effort:** ~1.5 hours total

---

## Core Concept

A notebook is just a blank PDF. The pencil plugin already handles all drawing — stylus input, stroke rendering, undo, colors, eraser, and export. The notebooks feature in Cozy Home is a thin UI layer that manages notebook files. It never touches a stylus or renders a stroke.

**Pencil plugin** owns: drawing, pen stroke types, pressure, brushes, colors, eraser, undo, export.
**Notebooks** owns: creating blank template PDFs, listing them, rename/duplicate/delete, opening them in KOReader.

---

## Architecture

### What notebooks.lua does:
- Shows a list screen of PDF files from a dedicated notebooks folder
- Creates new blank PDFs with template backgrounds (blank, lined, graph, dotted)
- Lets user pick page count via SpinWidget when creating
- Duplicates existing notebooks (file copy)
- Renames and deletes notebook files
- Opens notebooks in KOReader via ReaderUI:showReader() — pencil takes over

### What notebooks.lua does NOT do:
- No stylus/touch input handling
- No stroke rendering or storage
- No undo system
- No custom canvas widget
- No SQLite tables for strokes

### Files changed:

| File | Action | What |
|------|--------|------|
| `notebooks.lua` | **Create** | List screen + PDF generation |
| `config.lua` | Modify | Add tile definition + constants |
| `main.lua` | Modify | Add "notebooks" to shared_keys |
| `home.lua` | Modify | Add tile callback (one line) |

---

## Phase 1 — Config + Wiring (~10 min)

**Goal:** Tile appears on the dashboard and navigation works (opens a placeholder screen).

### 1A. config.lua

Add tile to `Config.TILES` (insert before the "settings" entry):
```lua
{
    key = "notebooks",
    label = "Notebooks",
    icon_text = "✎",
    enabled = true,
    description = "Freehand drawing notebooks",
},
```

Add display constants to `Config.UI`:
```lua
row_height_notebook_list = 68,
reserved_height_notebook_list = 200,
max_notebook_name = 50,
```

Add new config section:
```lua
Config.NOTEBOOKS = {
    folder_name = "notebooks",
    default_page_count = 20,
    min_page_count = 1,
    max_page_count = 200,
    page_w_pt = 595,   -- A4 width in PDF points
    page_h_pt = 842,   -- A4 height in PDF points
}
```

### 1B. main.lua

Add `"notebooks"` to the `shared_keys` table (line ~42).

### 1C. home.lua

Add to the `getTileCallbacks()` return table:
```lua
notebooks = nav("notebooks"),
```

### 1D. notebooks.lua (skeleton)

Create a minimal `notebooks.lua` that just shows an empty screen with a header and "Coming soon" message, plus the `Notebooks.show(ui, on_back)` public API. This confirms wiring works before building the real UI.

**Test:** Tap Notebooks tile → screen opens → back button returns to home.

---

## Phase 2 — PDF Template Generator (~30 min)

**Goal:** Can generate multi-page PDFs with template backgrounds (blank, lined, graph, dotted).

### 2A. Template content stream functions

Each function returns a PDF content stream string (path operators) that draws the template pattern for one page:

- `blank` — empty string (white page)
- `lined` — horizontal rules in light gray, ~24pt spacing, skip top margin
- `graph` — grid lines in light gray, ~20pt spacing
- `dotted` — dot grid using tiny filled circles, ~20pt spacing

### 2B. PDF assembly

Use a local copy/adaptation of pencil's `PdfWriter` approach (pure-Lua PDF 1.4 generation). Each page gets: white background + template content stream. No strokes — those come later via pencil when the user draws.

The generator function:
```lua
Notebooks.generatePDF(filepath, template_type, page_count)
-- Returns: true on success, nil + error on failure
```

### 2C. Notebooks folder

On first use, create the folder if it doesn't exist:
- Path: `home_dir .. "/notebooks/"` (e.g., `/mnt/onboard/notebooks/`)
- Uses `lfs.mkdir()` with existence check

**Test:** Call `generatePDF()` from the Lua console or a temporary button. Open the resulting PDF on a computer to verify template patterns render correctly.

---

## Phase 3 — List Screen (~30 min)

**Goal:** Full notebook list UI with scan, display, and navigation.

### 3A. Folder scanning

Scan the notebooks folder for `*.pdf` files. For each file, collect:
- Filename (display name = filename without `.pdf`)
- File size (from `lfs.attributes`)
- Last modified date (from `lfs.attributes`)

Sort by last modified (newest first).

### 3B. List UI

Standard Cozy Home list screen pattern (same as learningspace class list):
- `CozyUI.buildScreenHeader()` with title "Notebooks" and back button
- "+" button in header for creating new notebooks
- Paginated list using `calcItemsPerPage()` with `Config.UI.row_height_notebook_list`
- Each row: notebook name (left), page count or file size + date (right)
- Empty state: centered message "No notebooks yet — tap + to create one"

### 3C. Tap to open

Tapping a notebook row:
1. Closes the notebooks screen
2. Opens the PDF in KOReader via `ReaderUI:showReader(filepath)`
3. Pencil plugin activates automatically (it hooks into any open document)

**Test:** Create a notebook manually (or from Phase 2), see it in the list, tap to open, draw with pencil.

---

## Phase 4 — Create, Duplicate, Rename, Delete (~20 min)

**Goal:** Full CRUD operations on notebooks.

### 4A. Create new notebook

Flow:
1. Tap "+" → `InputDialog` for notebook name
   - Validated with `CozyUI.sanitizeInput(name, Config.UI.max_notebook_name)`
   - Check for duplicate filename
2. → `ButtonDialog` to pick template: Blank / Lined / Graph / Dotted
3. → `SpinWidget` for page count (min 1, max 200, default 20)
4. → Generate PDF via `Notebooks.generatePDF()`
5. → Refresh list
6. → Optionally auto-open the new notebook

### 4B. Long-press context menu

Long-press a notebook row → `ButtonDialog` with:
- **Rename** → `InputDialog` with current name pre-filled → `os.rename()` the file
- **Duplicate** → copies file as `name (copy).pdf` → refresh list
- **Delete** → `ConfirmBox` → `os.remove()` → refresh list

### 4C. Error handling

All file operations wrapped in `pcall()`. On failure, show `InfoMessage` to the user. Never fail silently.

**Test:** Create 3 notebooks with different templates, duplicate one, rename one, delete one. Verify list updates correctly after each operation.

---

## Phase 5 — Polish (~10 min)

**Goal:** Edge cases and integration.

### 5A. Edge cases
- Empty notebooks folder (shows empty state message)
- Very long notebook names (truncated in list display)
- Notebook folder doesn't exist yet (auto-create on first access)
- PDF file is open in KOReader when trying to delete/rename (show "close the notebook first" message, or just let the OS error bubble up gracefully)

### 5B. Home screen stats (optional)
- Add notebook count to the stats bar: "3 notebooks"
- Only if the notebooks folder exists and has files

### 5C. Luacheck
- Run `luacheck notebooks.lua` — ensure clean

---

## Quick Commands for Sessions

```
"Start notebooks — Phase 1: config + wiring + skeleton screen"
"Continue notebooks — Phase 2: PDF template generator"
"Continue notebooks — Phase 3: list screen"
"Continue notebooks — Phase 4: create/duplicate/rename/delete"
"Continue notebooks — Phase 5: polish"
```

---

## Future Enhancements (Not This Session)

These belong in **pencil.koplugin**, not notebooks:
- New pen stroke types (calligraphy, pressure-sensitive width, brush styles)
- Improved color picker
- Pen thickness presets

These could go in notebooks later:
- Cover thumbnails in the list (render first page as image)
- Notebook categories/folders
- Export all pages as images
- Custom template upload (user-provided PDF as template)

---

*Last updated: March 2026*
