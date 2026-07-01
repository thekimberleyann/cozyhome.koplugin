-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         main.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-05
--   ⊹  Modified:     2026-02-24
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Plugin entry point. Registers menus, actions,
--       and loads all Cozy Home modules. Sets up the
--       highlight context menu integration for flashcard
--       creation.
--
--   🎀 Optimization note (2026-02-11):
--       All screen modules (home, highlights, focusmode,
--       highlight_bridge) are now LAZY-LOADED — they are
--       only require()'d when the user actually opens them.
--       This cuts plugin boot time from several seconds
--       to near-instant on Kobo hardware.
--
--   🎀 License:      MIT
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

-- ============================================
-- IMPORTS (lightweight only — no screen modules!)
-- ============================================

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Dispatcher = require("dispatcher")
local _ = require("gettext")
local logger = require("logger")

-- ============================================
-- MODULE CACHE CLEARING
-- ============================================
-- Clear module cache for names shared with other cozy plugins.
-- cozy.koplugin loads first alphabetically and caches its own
-- config.lua, lib/database.lua, etc. under these generic keys.
-- Without this, require() returns the wrong plugin's modules.

local shared_keys = {
    "config", "lib/database", "home", "statusbar", "history",
    "learningspace", "flashcards", "notebooks",
    "settings", "highlight_bridge", "lib/bookscanner",
    "lib/highlights", "lib/conflict_checker",
    "lib/kobo", "lib/anki_export", "lib/anki_import",
    "highlights", "focusmode", "lib/cozyui", "cozyui",
}
for _, key in ipairs(shared_keys) do
    package.loaded[key] = nil
end

-- Config is small and has no dependencies — safe to load at boot
local Config = require("config")

-- ============================================
-- LAZY LOADER HELPER
-- ============================================
-- Returns a function that require()s a module on first call,
-- then caches it. If loading fails, returns nil + error string.

local _module_cache = {}

local function lazyRequire(mod_name)
    if _module_cache[mod_name] ~= nil then
        -- false means "tried and failed"
        if _module_cache[mod_name] == false then return nil end
        return _module_cache[mod_name]
    end
    local ok, mod = pcall(require, mod_name)
    if ok and mod then
        _module_cache[mod_name] = mod
        return mod
    else
        logger.warn("CozyHome: Failed to load", mod_name, ":", mod)
        _module_cache[mod_name] = false
        return nil
    end
end

-- ============================================
-- PLUGIN DEFINITION
-- ============================================

local CozyHome = WidgetContainer:extend{
    name = Config.PLUGIN.name,
    human_name = _(Config.PLUGIN.human_name),
    description = _(Config.PLUGIN.description),
}

-- ============================================
-- INITIALIZATION
-- ============================================

function CozyHome:init()
    self:registerActions()
    self.ui.menu:registerToMainMenu(self)

    -- Register highlight menu item if we are in the reader context
    self:registerHighlightMenuItem()

    -- Register "Add to Learning Space" in file manager hold dialog
    self:registerFileManagerHold()

    -- Protect against freeze when long-pressing scanned PDFs
    self:patchScannedPdfProtection()

    -- Auto-launch Cozy Home on startup (file manager context only)
    self:maybeAutoLaunch()

    logger.info("Cozy Home v" .. Config.PLUGIN.version .. " initialized")
end

-- ============================================
-- SCANNED PDF PROTECTION
-- ============================================
-- Monkey-patches ReaderHighlight:onHold to add a pre-flight
-- check for scanned PDFs. Without this, long-pressing on a
-- scanned PDF page triggers Leptonica OCR layout analysis
-- that floods stderr with errors and freezes the device.
--
-- How it works:
--   1. Before the original onHold runs, we call
--      doc:getPageTextBoxes(pageno) which reads only the
--      native text layer (fast, no OCR).
--   2. If the page has no native text (nil or <=1 boxes)
--      AND the document is a PDF, we show a user-friendly
--      message and consume the gesture, preventing the
--      Leptonica cascade entirely.
--   3. If the page has text, we call the original onHold
--      so highlighting works normally.

function CozyHome:patchScannedPdfProtection()
    -- Only applies in reader context with highlight module
    if not self.ui or not self.ui.highlight then return end
    if not self.ui.document then return end

    -- Only patch for PDF documents (DJVU also uses kopt but
    -- is less likely to trigger this issue)
    local file = self.ui.document.file or ""
    if not file:lower():match("%.pdf$") then return end

    local highlight = self.ui.highlight
    local original_onHold = highlight.onHold

    -- Guard: don't patch twice if plugin reinitializes
    if highlight._cozy_onHold_patched then return end
    highlight._cozy_onHold_patched = true

    highlight.onHold = function(self_hl, arg, ges)
        -- Quick check: does this page have a native text layer?
        -- getPageTextBoxes reads the PDF's embedded text objects;
        -- it does NOT trigger OCR/Leptonica processing.
        local doc = self_hl.ui and self_hl.ui.document
        if doc and doc.getPageTextBoxes then
            local hold_pos = self_hl.view:screenToPageTransform(ges.pos)
            if hold_pos then
                local text_ok, text = pcall(doc.getPageTextBoxes, doc, hold_pos.page)
                if text_ok and (not text or #text <= 1) then
                    -- No native text layer on this page.
                    -- Check if forced_ocr is enabled (user explicitly
                    -- wants OCR) — if so, let KOReader handle it.
                    local forced_ocr = doc.configurable
                        and doc.configurable.forced_ocr == 1
                    if not forced_ocr then
                        logger.dbg("CozyHome: Blocked onHold on scanned PDF page",
                            hold_pos.page, "(no native text layer)")
                        UIManager:show(InfoMessage:new{
                            text = _("This page has no selectable text.\n\nThis appears to be a scanned PDF. Text selection requires either a native text layer or Tesseract OCR data (koreader/data/tessdata)."),
                            timeout = 5,
                        })
                        return true  -- consume gesture, prevent Leptonica cascade
                    end
                end
            end
        end

        -- Page has text (or it's not a PDF) — run original handler
        return original_onHold(self_hl, arg, ges)
    end

    logger.dbg("CozyHome: Scanned PDF hold protection installed")
end

-- ============================================
-- AUTO-LAUNCH ON STARTUP
-- ============================================

function CozyHome:maybeAutoLaunch()
    -- Only auto-launch in file manager context (not when a book is open)
    if self.ui.document then return end

    -- Check user preference (default: off until they enable it)
    local auto_launch = G_reader_settings
        and G_reader_settings:isTrue("cozyhome_auto_launch")
    if not auto_launch then return end

    -- Use nextTick so the file manager finishes its own init first.
    UIManager:nextTick(function()
        local Home = lazyRequire("home")
        if Home then
            Home.show(self.ui)
        end
    end)
end

-- ============================================
-- HIGHLIGHT MENU INTEGRATION
-- ============================================

function CozyHome:registerHighlightMenuItem()
    if not self.ui or not self.ui.highlight then
        return
    end

    local cozyhome = self
    self.ui.highlight:addToHighlightDialog("cozyhome_create_card", function(this)
        return {
            text = _("Create Flashcard"),
            enabled = this.hold_pos ~= nil,
            callback = function()
                local HighlightBridge = lazyRequire("highlight_bridge")
                if not HighlightBridge then
                    UIManager:show(InfoMessage:new{
                        text = _("Highlight bridge not available."),
                        timeout = 3,
                    })
                    return
                end

                local selected = this.selected_text
                if not selected or not selected.text or selected.text == "" then
                    -- This typically happens on scanned PDFs without a text
                    -- layer. KOReader's OCR engine couldn't extract text.
                    UIManager:show(InfoMessage:new{
                        text = _("No text could be selected.\n\nThis book may be a scanned PDF without selectable text. To enable text selection, install Tesseract OCR language data in koreader/data/tessdata."),
                        timeout = 6,
                    })
                    return
                end

                local highlight_data = {
                    text = selected.text or "",
                    book_path = cozyhome.ui.document and cozyhome.ui.document.file or "",
                    book_title = "",
                    page = selected.pos0 and selected.pos0.page or nil,
                    chapter = nil,
                }

                local ok_props, props = pcall(function()
                    return cozyhome.ui.doc_props
                end)
                if ok_props and props then
                    highlight_data.book_title = props.title or ""
                end
                if highlight_data.book_title == "" and highlight_data.book_path ~= "" then
                    highlight_data.book_title = highlight_data.book_path:match("([^/]+)$") or ""
                end

                local ok_toc, toc_mgr = pcall(function()
                    return cozyhome.ui.toc
                end)
                if ok_toc and toc_mgr and toc_mgr.getTocTitleByPage then
                    local ok_ch, ch = pcall(toc_mgr.getTocTitleByPage, toc_mgr,
                        selected.pos0 and selected.pos0.page or 0)
                    if ok_ch and ch then
                        highlight_data.chapter = ch
                    end
                end

                -- Don't call this:onClose() yet — we need selected_text
                -- and hold_pos to remain available so the bridge can
                -- optionally save the highlight as a KOReader bookmark.
                -- The highlight dialog is closed, but the selection stays.
                if this.highlight_dialog then
                    UIManager:close(this.highlight_dialog)
                    this.highlight_dialog = nil
                end
                UIManager:nextTick(function()
                    HighlightBridge.createCardFromHighlight(highlight_data, this)
                end)
            end,
        }
    end)
end

-- ============================================
-- FILE MANAGER HOLD DIALOG INTEGRATION
-- ============================================
-- When the user long-presses a book file in KOReader's file
-- manager, we inject an "Add to Learning Space" button into
-- the hold dialog. This lets users organize books without
-- having to navigate into Cozy Home first.
--
-- Uses KOReader's official plugin API:
--   FileManager:addFileDialogButtons(row_id, row_func)
-- The row_func receives (file, is_file, book_props) and
-- returns a button row table, or nil to skip.

function CozyHome:registerFileManagerHold()
    -- Only applies in file manager context (not reader)
    if self.ui.document then return end

    local fm = self.ui
    -- addFileDialogButtons is the official KOReader API for this
    if not fm or not fm.addFileDialogButtons then
        logger.dbg("CozyHome: FileManager:addFileDialogButtons not available, skipping")
        return
    end

    local cozyhome = self

    fm:addFileDialogButtons("cozyhome_add_to_ls", function(file, is_file, book_props)
        -- Only show for files, not directories
        if not is_file then return nil end
        return {
            {
                text = _("Add to Learning Space"),
                callback = function()
                    -- Close the file dialog first
                    local fc = fm.file_chooser
                    if fc and fc.file_dialog then
                        UIManager:close(fc.file_dialog)
                    end
                    cozyhome:showAddToLearningSpaceDialog(file)
                end,
            },
        }
    end)

    logger.dbg("CozyHome: File manager hold button registered")
end

--- Show a dialog to pick which learning space to add the book to.
-- Lists existing classes and offers a "Create New" option.
-- @param file string: full path to the book file
function CozyHome:showAddToLearningSpaceDialog(file)
    local Database = lazyRequire("lib/database")
    if not Database then
        UIManager:show(InfoMessage:new{
            text = _("Database not available."),
            timeout = 3,
        })
        return
    end

    Database:open()
    local classes = Database:getClasses()

    -- Extract book metadata
    local book_title = file:match("([^/]+)$") or "Unknown"
    book_title = book_title:gsub("%.%w+$", "")  -- strip extension
    local book_author = ""

    -- Try to get proper metadata from DocSettings
    local DocSettings = require("docsettings")
    local ok_ds, ds = pcall(DocSettings.open, DocSettings, file)
    if ok_ds and ds then
        local doc_props = ds:readSetting("doc_props")
        if doc_props then
            if doc_props.title and doc_props.title ~= "" then
                book_title = doc_props.title
            end
            if doc_props.authors and doc_props.authors ~= "" then
                book_author = doc_props.authors
            end
        end
    end

    local ButtonDialog = require("ui/widget/buttondialog")
    local button_rows = {}

    -- One button per existing class
    -- NOTE: Do NOT use _ as loop variable here — it would shadow
    -- the gettext _() function, causing crashes in the callbacks below.
    for _i, cls in ipairs(classes) do
        local class_id = cls.id
        local class_name = cls.name
        local icon = cls.icon or cls.name:sub(1, 1):upper()

        -- Check if book is already in this class
        local already_in = Database:isBookInClass(class_id, file)
        local label = already_in
            and (icon .. " " .. class_name .. " ✓")
            or (icon .. " " .. class_name)

        table.insert(button_rows, {{
            text = label,
            callback = function()
                UIManager:close(self._ls_picker_dialog)
                self._ls_picker_dialog = nil
                if already_in then
                    -- Already added — offer to remove instead
                    Database:removeBookFromClass(class_id, file)
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("Removed from '%s'"), class_name),
                        timeout = 2,
                    })
                else
                    Database:addBookToClass(class_id, file, book_title, book_author)
                    UIManager:show(InfoMessage:new{
                        text = string.format(_("Added to '%s'"), class_name),
                        timeout = 2,
                    })
                end
            end,
        }})
    end

    -- "+ Create New" button
    table.insert(button_rows, {{
        text = _("+ Create New Learning Space"),
        callback = function()
            UIManager:close(self._ls_picker_dialog)
            self._ls_picker_dialog = nil
            self:showCreateAndAddDialog(file, book_title, book_author)
        end,
    }})

    -- Cancel
    table.insert(button_rows, {{
        text = _("Cancel"),
        callback = function()
            UIManager:close(self._ls_picker_dialog)
            self._ls_picker_dialog = nil
        end,
    }})

    -- Title shows truncated book name
    local display_title = book_title
    if #display_title > 35 then
        display_title = display_title:sub(1, 32) .. "..."
    end

    self._ls_picker_dialog = ButtonDialog:new{
        title = _("Add to Learning Space") .. "\n" .. display_title,
        buttons = button_rows,
    }
    UIManager:show(self._ls_picker_dialog)
end

--- Create a new learning space and immediately add the book to it.
function CozyHome:showCreateAndAddDialog(file, book_title, book_author)
    local Database = lazyRequire("lib/database")
    local CozyUI = lazyRequire("lib/cozyui")
    if not Database then return end

    local InputDialog = require("ui/widget/inputdialog")
    local cozyhome = self
    local dialog
    dialog = InputDialog:new{
        title = _("✦ New Learning Space ✦"),
        input = "",
        input_hint = _("Class or topic name"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Create & Add"),
                    is_enter_default = true,
                    callback = function()
                        local raw_name = dialog:getInputText()
                        UIManager:close(dialog)
                        local name = raw_name
                        if CozyUI and CozyUI.sanitizeInput then
                            name = CozyUI.sanitizeInput(raw_name, 100)
                        end
                        if name ~= "" then
                            local icon = name:sub(1, 1):upper()
                            local class_id = Database:createClass(name, icon, nil)
                            if class_id then
                                Database:addBookToClass(class_id, file, book_title, book_author)
                                UIManager:show(InfoMessage:new{
                                    text = string.format(_("Created '%s' and added book"), name),
                                    timeout = 2,
                                })
                            else
                                UIManager:show(InfoMessage:new{
                                    text = _("Failed to create learning space."),
                                    timeout = 3,
                                })
                            end
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================
-- HOME SCREEN
-- ============================================

function CozyHome:showHomeScreen()
    local Home = lazyRequire("home")
    if not Home then
        UIManager:show(InfoMessage:new{
            text = _("Cozy Home not available."),
            timeout = 5,
        })
        return
    end
    Home.show(self.ui)
end

-- ============================================
-- ACTIONS REGISTRATION
-- ============================================

function CozyHome:registerActions()
    Dispatcher:registerAction("cozyhome_show", {
        category = "none",
        event = "ShowCozyHome",
        title = _("Cozy Home"),
        description = _("Open Cozy Home welcome screen"),
    })
    Dispatcher:registerAction("cozyhome_create_card_from_highlight", {
        category = "none",
        event = "CreateCardFromHighlight",
        title = _("Create Flashcard"),
        description = _("Create a flashcard from highlighted text"),
    })
    Dispatcher:registerAction("cozyhome_browse_highlights", {
        category = "none",
        event = "BrowseHighlights",
        title = _("Browse Highlights"),
        description = _("Browse highlights for the current book"),
    })
    Dispatcher:registerAction("cozyhome_browse_all_highlights", {
        category = "none",
        event = "BrowseAllHighlights",
        title = _("Browse All Highlights"),
        description = _("Browse highlights across all books"),
    })
    Dispatcher:registerAction("cozyhome_focus_mode", {
        category = "none",
        event = "ShowFocusMode",
        title = _("Focus Mode"),
        description = _("Open the Pomodoro focus timer"),
    })
    Dispatcher:registerAction("cozyhome_start_focus", {
        category = "none",
        event = "StartFocusSession",
        title = _("Start Focus Session"),
        description = _("Start a Pomodoro focus session immediately"),
    })
end

-- ============================================
-- ACTION HANDLERS
-- ============================================

function CozyHome:onShowCozyHome()
    self:showHomeScreen()
    return true
end

function CozyHome:onBrowseHighlights()
    local HighlightsScreen = lazyRequire("highlights")
    if not HighlightsScreen then
        UIManager:show(InfoMessage:new{
            text = _("Highlights module not available."),
            timeout = 5,
        })
        return true
    end
    HighlightsScreen.showForCurrentBook(self.ui)
    return true
end

function CozyHome:onBrowseAllHighlights()
    local HighlightsScreen = lazyRequire("highlights")
    if not HighlightsScreen then
        UIManager:show(InfoMessage:new{
            text = _("Highlights module not available."),
            timeout = 5,
        })
        return true
    end
    HighlightsScreen.showForAllBooks(self.ui)
    return true
end

function CozyHome:onShowFocusMode()
    local FocusMode = lazyRequire("focusmode")
    if not FocusMode then
        UIManager:show(InfoMessage:new{
            text = _("Focus Mode not available."),
            timeout = 5,
        })
        return true
    end
    FocusMode.show(self.ui)
    return true
end

function CozyHome:onStartFocusSession()
    local FocusMode = lazyRequire("focusmode")
    if not FocusMode then
        UIManager:show(InfoMessage:new{
            text = _("Focus Mode not available."),
            timeout = 3,
        })
        return true
    end
    FocusMode.startWork()
    return true
end

function CozyHome:onCreateCardFromHighlight(highlight_data)
    local HighlightBridge = lazyRequire("highlight_bridge")
    if HighlightBridge then
        HighlightBridge.createCardFromHighlight(highlight_data)
    else
        UIManager:show(InfoMessage:new{
            text = _("Highlight bridge not available."),
            timeout = 3,
        })
    end
    return true
end

-- ============================================
-- MENU DEFINITION
-- ============================================

function CozyHome:addToMainMenu(menu_items)
    local cozyhome = self
    menu_items.cozyhome = {
        text_func = function()
            -- Only check focus timer state if FocusMode is already loaded
            local FocusMode = _module_cache["focusmode"]
            if FocusMode and FocusMode.isActive and FocusMode.isActive() then
                local ts = FocusMode.getTimerState()
                local m = math.floor(ts.time_remaining / 60)
                local s = ts.time_remaining % 60
                return string.format("Cozy Home  ◷ %02d:%02d", m, s)
            end
            return _("Cozy Home")
        end,
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Open Cozy Home"),
                keep_menu_open = false,
                callback = function()
                    cozyhome:showHomeScreen()
                end,
            },
            {
                text = _("Browse Highlights (This Book)"),
                keep_menu_open = false,
                enabled_func = function()
                    return cozyhome.ui and cozyhome.ui.document ~= nil
                end,
                callback = function()
                    cozyhome:onBrowseHighlights()
                end,
            },
            {
                text = _("Browse All Highlights"),
                keep_menu_open = false,
                callback = function()
                    cozyhome:onBrowseAllHighlights()
                end,
            },
            {
                text_func = function()
                    local FocusMode = _module_cache["focusmode"]
                    if FocusMode and FocusMode.isActive and FocusMode.isActive() then
                        local ts = FocusMode.getTimerState()
                        local label = ts.is_break and "Break" or "Focus"
                        local m = math.floor(ts.time_remaining / 60)
                        local s = ts.time_remaining % 60
                        return string.format("(%s) %s %02d:%02d", label, "Focus Mode", m, s)
                    end
                    return _("Focus Mode")
                end,
                keep_menu_open = false,
                callback = function()
                    cozyhome:onShowFocusMode()
                end,
                separator = true,
            },
            {
                text = _("Open on startup"),
                checked_func = function()
                    return G_reader_settings:isTrue("cozyhome_auto_launch")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("cozyhome_auto_launch")
                end,
            },
            {
                text = _("Check for conflicts"),
                keep_menu_open = true,
                callback = function()
                    local ConflictChecker = lazyRequire("lib/conflict_checker")
                    if not ConflictChecker then
                        UIManager:show(InfoMessage:new{
                            text = _("Conflict checker not available."),
                            timeout = 3,
                        })
                        return
                    end
                    local summary = ConflictChecker.summary()
                    UIManager:show(InfoMessage:new{
                        text = summary or _("✓ No plugin conflicts detected."),
                    })
                end,
            },
            {
                text = _("About"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = Config.PLUGIN.human_name
                            .. " v" .. Config.PLUGIN.version
                            .. "\n\n" .. Config.PLUGIN.description,
                    })
                end,
            },
        },
    }
end

-- ============================================
-- CLEANUP
-- ============================================

function CozyHome:onSuspend()
    -- Delegate to FocusMode only if it's already loaded — avoids
    -- force-requiring the module just to handle a no-op suspend.
    local FocusMode = _module_cache["focusmode"]
    if FocusMode and FocusMode.onSuspend then
        FocusMode.onSuspend()
    end
end

function CozyHome:onResume()
    local FocusMode = _module_cache["focusmode"]
    if FocusMode and FocusMode.onResume then
        FocusMode.onResume()
    end
end

function CozyHome:onCloseDocument()
    -- Phase 3: Invalidate highlight cache for the closed book
    -- so new highlights made during reading appear immediately
    -- on return to Cozy Home. Uses package.loaded to avoid
    -- force-loading lib/highlights just to clear an empty cache.
    local filepath = self.ui and self.ui.document and self.ui.document.file
    if filepath then
        local HL = package.loaded["lib/highlights"]
        if HL and HL.invalidateCache then
            HL.invalidateCache(filepath)
        end
    end

    -- Mark the home screen stats cache as dirty so the next
    -- Cozy Home open recomputes (user may have added highlights)
    local Home = package.loaded["home"]
    if Home and Home.invalidateStatsCache then
        Home.invalidateStatsCache()
    end

    logger.dbg("CozyHome: Document closed")
end

-- ============================================
-- RETURN THE PLUGIN
-- ============================================

return CozyHome
