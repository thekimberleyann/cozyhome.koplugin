-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         highlight_bridge.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-23
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Bridge between KOReader's highlight menu and
--       the Cozy Flashcards database. Lets you create
--       flashcards directly from selected/highlighted
--       text in the reader.
--
--       Two creation modes:
--         1. Auto-fill — highlight pre-fills front, you edit
--            and add the back. Full highlight scrollable.
--         2. Blank — full highlight shown for reference,
--            you type both front and back from scratch.
--
--       Additional features:
--         - "Save Highlight" checkbox saves the selection
--           as a KOReader highlight/bookmark so you don't
--           have to go back and re-highlight.
--         - "Paste Highlight" button on front & back screens
--           inserts the full highlight text at cursor position.
--         - "View Highlight" / "View Front" buttons open
--           scrollable viewers for long text reference.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - cozy_flashcards.db (flashcard DB — for cards & decks)
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local HighlightBridge = {}

-- ============================================
-- HELPERS
-- ============================================

--- Open the flashcard DB directly (separate from cozyhome's DB).
-- Returns a connection or nil.
local function openFlashcardDB()
    local SQ3 = require("lua-ljsqlite3/init")
    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok or not conn then
        logger.warn("CozyHome HighlightBridge: Failed to open flashcard DB:", tostring(conn))
        return nil
    end
    return conn
end

--- Get all decks from the flashcard DB.
-- @return table: array of {id, name}
local function getDecks()
    local conn = openFlashcardDB()
    if not conn then return {} end

    local decks = {}
    local ok, err = pcall(function()
        conn:exec([[
            CREATE TABLE IF NOT EXISTS decks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                description TEXT,
                created_at TEXT DEFAULT (datetime('now', 'localtime')),
                updated_at TEXT DEFAULT (datetime('now', 'localtime')),
                sort_order INTEGER DEFAULT 0
            );
        ]])
        pcall(function()
            conn:exec("INSERT OR IGNORE INTO decks (id, name, description) VALUES (1, 'General', 'Default deck for all cards')")
        end)

        local stmt = conn:prepare(
            "SELECT id, name FROM decks ORDER BY sort_order ASC, name ASC"
        )
        if stmt then
            for row in stmt:rows() do
                table.insert(decks, {
                    id = tonumber(row[1]),
                    name = row[2] or "Unknown",
                })
            end
            stmt:close()
        end
    end)

    pcall(function() conn:close() end)

    if not ok then
        logger.warn("CozyHome HighlightBridge: getDecks failed:", err)
    end
    return decks
end

-- ============================================
-- CARD CREATION FROM HIGHLIGHT
-- ============================================

--- Open the card creation flow with highlight data pre-filled.
-- @param highlight_data table: { text, book_path, book_title, page, chapter }
-- @param reader_highlight ReaderHighlight instance (optional) — if provided,
--        allows saving the selection as a KOReader highlight/bookmark.
function HighlightBridge.createCardFromHighlight(highlight_data, reader_highlight)
    if not highlight_data or not highlight_data.text or highlight_data.text == "" then
        UIManager:show(InfoMessage:new{
            text = _("No highlight text available."),
            timeout = 2,
        })
        return
    end

    -- Check if flashcard DB is accessible
    local lfs = require("libs/libkoreader-lfs")
    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
    local attr = lfs.attributes(db_path)
    if not attr then
        UIManager:show(InfoMessage:new{
            text = _("Flashcard database not found.\n\nOpen Cozy Flashcards once to create the database."),
            timeout = 4,
        })
        return
    end

    -- Carry context through the flow
    local ctx = {
        highlight_data = highlight_data,
        reader_highlight = reader_highlight,   -- ReaderHighlight instance (may be nil)
        save_highlight = true,                 -- default: save highlight too
    }

    HighlightBridge._showModeChoice(ctx)
end

-- ============================================
-- STEP 0: MODE CHOICE (full-screen TextViewer)
-- ============================================

--- Show full highlight in a scrollable TextViewer with mode choice buttons.
function HighlightBridge._showModeChoice(ctx)
    local hd = ctx.highlight_data

    -- Build source info line
    local source_parts = {}
    if hd.book_title and hd.book_title ~= "" then
        table.insert(source_parts, hd.book_title)
    end
    if hd.page then
        table.insert(source_parts, _("p. ") .. tostring(hd.page))
    end
    if hd.chapter and hd.chapter ~= "" then
        table.insert(source_parts, hd.chapter)
    end
    local source_line = #source_parts > 0
        and ("\n\n— " .. table.concat(source_parts, " · "))
        or ""

    local viewer
    viewer = TextViewer:new{
        title = _("Create Flashcard"),
        text = hd.text .. source_line,
        text_type = "bookmark",
        buttons_table = {
            {
                {
                    text = _("Auto-fill & Edit"),
                    callback = function()
                        UIManager:close(viewer)
                        HighlightBridge._showFrontInput(ctx, true)
                    end,
                },
                {
                    text = _("Write My Own"),
                    callback = function()
                        UIManager:close(viewer)
                        HighlightBridge._showFrontInput(ctx, false)
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
            },
        },
    }

    -- Add save-highlight toggle row if ReaderHighlight is available
    if ctx.reader_highlight then
        local save_label = ctx.save_highlight
            and _("☑ Also save as highlight")
            or  _("☐ Also save as highlight")
        -- Insert before the Cancel row
        table.insert(viewer.buttons_table, #viewer.buttons_table, {
            {
                text = save_label,
                callback = function()
                    ctx.save_highlight = not ctx.save_highlight
                    -- Re-open the mode choice to reflect the toggle
                    UIManager:close(viewer)
                    HighlightBridge._showModeChoice(ctx)
                end,
            },
        })
    end

    UIManager:show(viewer)
end

-- ============================================
-- FRONT INPUT (fullscreen InputDialog)
-- ============================================

--- Show the front (question) input dialog.
-- @param ctx table: flow context
-- @param auto_fill boolean: true = pre-fill with highlight text
function HighlightBridge._showFrontInput(ctx, auto_fill)
    ctx.auto_fill = auto_fill
    local hd = ctx.highlight_data
    local initial_text = auto_fill and hd.text or ""
    local title = auto_fill
        and _("Front — Edit Highlight")
        or _("Front — Write Your Own")
    local hint = auto_fill
        and _("Edit the front side...")
        or _("Type the front side (question/prompt)...")

    local dialog
    dialog = InputDialog:new{
        title = title,
        description = _("📌 Use buttons below to view or paste the highlight text."),
        input = initial_text,
        input_hint = hint,
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
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
                    text = _("View Highlight"),
                    callback = function()
                        HighlightBridge._showHighlightPreview(hd)
                    end,
                },
                {
                    text = _("Paste Highlight"),
                    callback = function()
                        dialog:addTextToInput(hd.text)
                    end,
                },
                {
                    text = _("Next →"),
                    is_enter_default = true,
                    callback = function()
                        local front = dialog:getInputText()
                        if auto_fill then
                            if not front or front == "" then
                                front = hd.text
                            end
                        else
                            if not front or front == "" then
                                UIManager:show(InfoMessage:new{
                                    text = _("Front side cannot be empty."),
                                    timeout = 2,
                                })
                                return
                            end
                        end
                        UIManager:close(dialog)
                        HighlightBridge._showBackInput(ctx, front)
                    end,
                },
            },
        },
    }

    -- Add save-highlight checkbox if ReaderHighlight is available
    if ctx.reader_highlight then
        local check_save = CheckButton:new{
            text = _("Also save as highlight"),
            checked = ctx.save_highlight,
            parent = dialog,
            callback = function()
                ctx.save_highlight = not ctx.save_highlight
            end,
        }
        dialog:addWidget(check_save)
    end

    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================
-- BACK INPUT (fullscreen InputDialog)
-- ============================================

--- Show the back (answer) input dialog.
function HighlightBridge._showBackInput(ctx, front_text)
    local hd = ctx.highlight_data

    local dialog
    dialog = InputDialog:new{
        title = _("Back — Answer"),
        description = _("📌 Use buttons to view highlight, view front, or paste the highlight."),
        input = "",
        input_hint = _("Type the answer..."),
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        buttons = {
            {
                {
                    text = _("← Back"),
                    callback = function()
                        UIManager:close(dialog)
                        HighlightBridge._showFrontInput(ctx, ctx.auto_fill)
                    end,
                },
                {
                    text = _("View Highlight"),
                    callback = function()
                        HighlightBridge._showHighlightPreview(hd)
                    end,
                },
                {
                    text = _("View Front"),
                    callback = function()
                        HighlightBridge._showTextPreview(_("Front Side"), front_text)
                    end,
                },
            },
            {
                {
                    text = _("Paste Highlight"),
                    callback = function()
                        dialog:addTextToInput(hd.text)
                    end,
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local back = dialog:getInputText()
                        if not back or back == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("Back (answer) cannot be empty."),
                                timeout = 2,
                            })
                            return
                        end
                        UIManager:close(dialog)
                        HighlightBridge._showDeckPickerAndSave(ctx, front_text, back)
                    end,
                },
            },
        },
    }

    -- Add save-highlight checkbox if ReaderHighlight is available
    if ctx.reader_highlight then
        local check_save = CheckButton:new{
            text = _("Also save as highlight"),
            checked = ctx.save_highlight,
            parent = dialog,
            callback = function()
                ctx.save_highlight = not ctx.save_highlight
            end,
        }
        dialog:addWidget(check_save)
    end

    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================
-- PREVIEW VIEWERS (pop-over, non-destructive)
-- ============================================

--- Show the full original highlight in a scrollable TextViewer overlay.
function HighlightBridge._showHighlightPreview(highlight_data)
    local source_parts = {}
    if highlight_data.book_title and highlight_data.book_title ~= "" then
        table.insert(source_parts, highlight_data.book_title)
    end
    if highlight_data.page then
        table.insert(source_parts, _("p. ") .. tostring(highlight_data.page))
    end
    local source_line = #source_parts > 0
        and ("\n\n— " .. table.concat(source_parts, " · "))
        or ""

    local viewer
    viewer = TextViewer:new{
        title = _("Original Highlight"),
        text = highlight_data.text .. source_line,
        text_type = "bookmark",
        buttons_table = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

--- Show arbitrary text in a scrollable TextViewer overlay.
function HighlightBridge._showTextPreview(title, text)
    local viewer
    viewer = TextViewer:new{
        title = title,
        text = text,
        text_type = "bookmark",
        buttons_table = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

-- ============================================
-- DECK PICKER + SAVE
-- ============================================

--- Show deck picker, then save.
function HighlightBridge._showDeckPickerAndSave(ctx, front_text, back_text)
    local decks = getDecks()

    if #decks <= 1 then
        HighlightBridge._saveCard(ctx, front_text, back_text, 1)
        return
    end

    local button_rows = {}
    for _, deck in ipairs(decks) do
        local did = deck.id
        table.insert(button_rows, {
            {
                text = deck.name,
                callback = function()
                    UIManager:close(HighlightBridge._deck_pick_dialog)
                    HighlightBridge._saveCard(ctx, front_text, back_text, did)
                end,
            },
        })
    end

    table.insert(button_rows, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(HighlightBridge._deck_pick_dialog)
            end,
        },
    })

    HighlightBridge._deck_pick_dialog = ButtonDialog:new{
        title = _("Assign to Deck"),
        buttons = button_rows,
    }
    UIManager:show(HighlightBridge._deck_pick_dialog)
end

-- ============================================
-- SAVE CARD (+ optionally save highlight)
-- ============================================

--- Save the flashcard to cozy_flashcards.db.
-- Also saves the KOReader highlight if ctx.save_highlight is true
-- and ctx.reader_highlight is available.
function HighlightBridge._saveCard(ctx, front_text, back_text, deck_id)
    local hd = ctx.highlight_data

    -- 1. Save the KOReader highlight/bookmark if requested
    if ctx.save_highlight and ctx.reader_highlight then
        local rh = ctx.reader_highlight
        -- saveHighlight needs hold_pos and selected_text to be set.
        -- If they're still available (they should be since we deferred
        -- onClose), save the highlight.
        local save_ok, save_err = pcall(function()
            if rh.selected_text or rh.hold_pos then
                rh:saveHighlight(true)  -- true = extend to sentence
                logger.dbg("CozyHome HighlightBridge: KOReader highlight saved")
            else
                logger.dbg("CozyHome HighlightBridge: No selected_text/hold_pos, skipping highlight save")
            end
        end)
        if not save_ok then
            logger.warn("CozyHome HighlightBridge: Failed to save KOReader highlight:", save_err)
        end
    end

    -- 2. Save the flashcard
    local conn = openFlashcardDB()
    if not conn then
        UIManager:show(InfoMessage:new{
            text = _("Failed to open flashcard database."),
            timeout = 3,
        })
        return
    end

    deck_id = deck_id or 1
    local card_id = nil
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT INTO flashcards (front, back, source_text, source_page, "
            .. "source_chapter, book_path, book_title, state, card_type, deck_id) "
            .. "VALUES (?, ?, ?, ?, ?, ?, ?, 'new', 'text', ?)"
        )
        if stmt then
            stmt:bind(
                front_text,
                back_text,
                hd.text,
                hd.page,
                hd.chapter,
                hd.book_path,
                hd.book_title,
                deck_id
            )
            stmt:step()
            stmt:close()

            local id_stmt = conn:prepare("SELECT last_insert_rowid()")
            if id_stmt then
                local row = id_stmt:step()
                if row then card_id = tonumber(row[1]) end
                id_stmt:close()
            end
        end
    end)

    pcall(function() conn:close() end)

    if ok and card_id then
        -- Invalidate highlight cache
        local HL = package.loaded["lib/highlights"]
        if HL and hd.book_path then
            HL.invalidateCache(hd.book_path)
            logger.dbg("CozyHome HighlightBridge: Invalidated highlight cache for", hd.book_path)
        end

        local msg = _("Flashcard created! ✨")
        if ctx.save_highlight and ctx.reader_highlight then
            msg = _("Flashcard created & highlight saved! ✨")
        end
        UIManager:show(InfoMessage:new{
            text = msg,
            timeout = 2,
        })
    else
        logger.warn("CozyHome HighlightBridge: failed to save card:", err)
        UIManager:show(InfoMessage:new{
            text = _("Failed to create flashcard."),
            timeout = 3,
        })
    end

    -- Clean up the highlight selection now that we're done
    if ctx.reader_highlight then
        pcall(function() ctx.reader_highlight:clear() end)
    end
end

return HighlightBridge
