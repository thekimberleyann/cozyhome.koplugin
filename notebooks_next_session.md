# Notebooks Feature — Next Session Prompt

Paste everything below the line into a new chat.

---

## Context

I'm building a **Cozy Home** plugin for KOReader (`cozyhome.koplugin`). It's a Lua plugin that runs on a **Kobo Libra Colour** (color e-ink, stylus). The plugin provides a custom dashboard, library browser, highlights browser, learning spaces, flashcards, and focus timer.

I have a separate **pencil.koplugin** that handles all stylus drawing — stroke capture, rendering, undo, colors, eraser, and PDF export. It activates automatically when any document is open in KOReader.

You have filesystem access to both plugins. Read files directly — don't ask me to paste code.

**Cozy Home:** `C:\projects\Koreader Plugins\cozyhome.koplugin\`
**Pencil:** `C:\projects\Koreader Plugins\pencil.koplugin\pencil.koplugin\`
**KOReader source:** `\\wsl.localhost\Ubuntu\home\kag\projects\koreader`

## What Was Just Completed

**Notebooks feature integrated into Learning Space.** Instead of building a separate canvas/stroke system, notebooks are simply blank template PDFs that the user draws on with the pencil plugin. The notebooks UI lives inside Learning Space as a 4th tab (Books | Flashcards | Highlights | **Notebooks**).

### What was built:

1. **config.lua** — Added Notebooks tile definition, UI constants (`row_height_notebook_list`, `reserved_height_notebook_list`, `max_notebook_name`), and `Config.NOTEBOOKS` section (folder name, page count limits, PDF dimensions).

2. **main.lua** — Added `"notebooks"` to `shared_keys` cache clearing.

3. **home.lua** — Added `notebooks = nav("notebooks")` tile callback.

4. **notebooks.lua** — Standalone module with:
   - Pure-Lua PDF generator (`generatePDF(filepath, template, page_count)`) that creates valid PDF 1.4 files with template backgrounds (blank, lined, graph, dotted). Templates verified with pdfinfo and visual render.
   - Folder helpers: `getNotebooksDir()`, `scanNotebooks()`, `formatSize()`
   - Skeleton screen that shows a message pointing to Learning Spaces + a quick-open list of all notebooks across all classes.

5. **learningspace.lua** — Major additions:
   - 4th tab "Notebooks" in ClassDetailScreen tab bar
   - `buildNotebooksTab()` — paginated list of PDFs from class-specific subfolder
   - `showCreateNotebookDialog()` → name → template picker → page count spinner → generates PDF
   - `showNotebookActions()` — long-press context menu: Open / Rename / Duplicate / Delete
   - `renameNotebook()`, `duplicateNotebook()`, `deleteNotebook()` (with sidecar cleanup)
   - Class-specific folders: `/mnt/onboard/notebooks/ClassName/`

### Folder structure on device:
```
/mnt/onboard/notebooks/
├── Biology 101/
│   ├── Lecture Notes.pdf
│   └── Lab Drawings.pdf
├── History/
│   └── Timeline.pdf
```

## What Needs To Be Done — Phase 5: Polish

This is the final phase. Focus areas:

### 5A. Test and fix edge cases
- Read the actual code in `learningspace.lua` (the notebooks tab section and CRUD functions) and look for bugs
- Verify the `scanNotebooks()` recursive scan in `notebooks.lua` scans subdirectories (class folders) so the standalone notebooks tile shows all notebooks across all classes
- Check that the ✎ unicode character renders properly on e-ink — if not, replace with a safe ASCII alternative like `[N]`
- Make sure template picker buttons have consistent widths

### 5B. Handle the "Notebooks" tile on the dashboard
- Currently the Notebooks tile opens a standalone `notebooks.lua` screen
- Decide: should it redirect to Learning Space instead? Or should it stay as a "view all notebooks" quick-access screen?
- The standalone screen currently shows a message + quick-open list — verify this works when there are notebooks in class folders

### 5C. Edge cases in notebook CRUD
- Class name with special characters (how does `getClassNotebooksDir` sanitize?)
- Very long class names (filesystem path length)
- Creating a notebook when the notebooks folder doesn't exist yet
- Renaming a notebook that's currently open in KOReader
- Deleting a class that has notebooks (the folder persists — should it be cleaned up?)

### 5D. Optional: notebook count in class list
- In `ClassListScreen:buildUI()`, the class detail line shows "3 books -- 5 cards due -- 12 highlights"
- Add notebook count: "3 books -- 2 notebooks -- 5 cards due"
- This means scanning the class notebook folder in the class list — may be slow if there are many classes. Consider caching or skipping if the folder doesn't exist.

### 5E. Optional: home screen stats
- Add notebook count to the stats bar in `home.lua:computeStatsDeferred()`
- "3 books in progress · 42 highlights · 4 notebooks"

### 5F. Luacheck
- Run luacheck on `notebooks.lua` and the modified sections of `learningspace.lua`
- Fix any warnings (unused variables, shadowed locals, etc.)

## Coding Standards
- Lua 5.1 / LuaJIT compatible
- Use local variables; avoid globals
- Prefer early returns over deep nesting
- All user text inputs through `CozyUI.sanitizeInput()`
- All file operations wrapped in `pcall()`, show `InfoMessage` on failure
- E-ink friendly: no animations, use partial refresh where possible

## Quick Command
```
"Continue notebooks — Phase 5: polish and testing"
```
