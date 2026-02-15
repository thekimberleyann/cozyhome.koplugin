-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         highlight_bridge.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Bridge between KOReader's highlight menu and
--       the Cozy Flashcards database. Lets you create
--       flashcards directly from selected/highlighted
--       text in the reader.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - lib/database.lua
--       - config.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local Database = require("lib/database")

local HighlightBridge = {}

-- ============================================
-- CARD CREATION FROM HIGHLIGHT
-- ============================================

--- Open the card creation flow with highlight data pre-filled.
-- @param highlight_data table: { text, book_path, book_title, page, chapter }
function HighlightBridge.createCardFromHighlight(highlight_data)
    if not highlight_data or not highlight_data.text or highlight_data.text == "" then
        UIManager:show(InfoMessage:new{
            text = _("No highlight text available."),
            timeout = 2,
        })
        return
    end

    -- Check if flashcard DB is accessible
    local SQ3 = require("lua-ljsqlite3/init")
    local lfs = require("libs/libkoreader-lfs")
    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
    local attr = lfs.attributes(db_path)
    if not attr then
        UIManager:show(InfoMessage:new{
            text = _("Flashcard database not found.\n\nInstall cozy.koplugin to enable flashcard creation."),
            timeout = 4,
        })
        return
    end

    HighlightBridge._showFrontDialog(highlight_data)
end

--- Step 1: Show front (question) input with highlight text as context.
function HighlightBridge._showFrontDialog(highlight_data)
    -- Truncate highlight for display if too long
    local display_text = highlight_data.text
    if #display_text > 200 then
        display_text = display_text:sub(1, 197) .. "..."
    end

    local dialog
    dialog = InputDialog:new{
        title = _("Create Flashcard - Front"),
        description = _("Highlight: ") .. display_text,
        input = "",
        input_hint = _("Question / prompt (or leave blank to use highlight)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Next >"),
                    is_enter_default = true,
                    callback = function()
                        local front = dialog:getInputText()
                        UIManager:close(dialog)
                        -- If front is empty, use highlight text as front
                        if not front or front == "" then
                            front = highlight_data.text
                        end
                        HighlightBridge._showBackDialog(highlight_data, front)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Step 2: Show back (answer) input.
function HighlightBridge._showBackDialog(highlight_data, front_text)
    -- Show the highlight and front text as context
    local display_text = highlight_data.text
    if #display_text > 150 then
        display_text = display_text:sub(1, 147) .. "..."
    end
    local desc = _("Highlight: ") .. display_text .. "\n\n" .. _("Front: ") .. front_text

    local dialog
    dialog = InputDialog:new{
        title = _("Create Flashcard - Back"),
        description = desc,
        input = "",
        input_hint = _("Answer"),
        buttons = {
            {
                {
                    text = _("< Back"),
                    callback = function()
                        UIManager:close(dialog)
                        HighlightBridge._showFrontDialog(highlight_data)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local back = dialog:getInputText()
                        UIManager:close(dialog)
                        if back and back ~= "" then
                            HighlightBridge._showCategoryPickerAndSave(
                                highlight_data, front_text, back
                            )
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Back (answer) cannot be empty."),
                                timeout = 2,
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Step 3 (optional): Show category picker, then save.
function HighlightBridge._showCategoryPickerAndSave(highlight_data, front_text, back_text)
    Database:open()
    local categories = Database:getCategories()

    if #categories == 0 then
        -- No categories, save directly
        HighlightBridge._saveCard(highlight_data, front_text, back_text, nil)
        return
    end

    -- Show category picker
    local button_rows = {}
    table.insert(button_rows, {
        {
            text = _("No category"),
            callback = function()
                UIManager:close(HighlightBridge._cat_pick_dialog)
                HighlightBridge._saveCard(highlight_data, front_text, back_text, nil)
            end,
        },
    })

    for _, cat in ipairs(categories) do
        local cid = cat.id
        table.insert(button_rows, {
            {
                text = cat.name,
                callback = function()
                    UIManager:close(HighlightBridge._cat_pick_dialog)
                    HighlightBridge._saveCard(highlight_data, front_text, back_text, cid)
                end,
            },
        })
    end

    table.insert(button_rows, {
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(HighlightBridge._cat_pick_dialog)
            end,
        },
    })

    HighlightBridge._cat_pick_dialog = ButtonDialog:new{
        title = _("Assign to Category (optional)"),
        buttons = button_rows,
    }
    UIManager:show(HighlightBridge._cat_pick_dialog)
end

--- Save the flashcard to cozy_flashcards.db.
function HighlightBridge._saveCard(highlight_data, front_text, back_text, category_id)
    local SQ3 = require("lua-ljsqlite3/init")
    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"

    local card_id = nil
    local ok, err = pcall(function()
        local conn = SQ3.open(db_path)
        if not conn then return end

        local stmt = conn:prepare(
            "INSERT INTO flashcards (front, back, source_text, source_page, "
            .. "source_chapter, book_path, book_title, state, card_type) "
            .. "VALUES (?, ?, ?, ?, ?, ?, ?, 'new', 'text')"
        )
        if stmt then
            stmt:bind(
                front_text,
                back_text,
                highlight_data.text,
                highlight_data.page,
                highlight_data.chapter,
                highlight_data.book_path,
                highlight_data.book_title
            )
            stmt:step()
            stmt:close()

            -- Get the new card ID
            local id_stmt = conn:prepare("SELECT last_insert_rowid()")
            if id_stmt then
                local row = id_stmt:step()
                if row then card_id = tonumber(row[1]) end
                id_stmt:close()
            end
        end

        conn:close()
    end)

    if ok and card_id then
        -- Assign to category if selected
        if category_id then
            Database:open()
            Database:addCardToCategory(card_id, category_id)
        end

        -- Invalidate highlight cache for this book (belt-and-suspenders).
        -- Only if lib/highlights is already loaded — don't force-load it.
        local HL = package.loaded["lib/highlights"]
        if HL and highlight_data.book_path then
            HL.invalidateCache(highlight_data.book_path)
            logger.dbg("CozyHome HighlightBridge: Invalidated highlight cache for", highlight_data.book_path)
        end

        UIManager:show(InfoMessage:new{
            text = _("Flashcard created."),
            timeout = 2,
        })
    else
        logger.warn("CozyHome HighlightBridge: failed to save card:", err)
        UIManager:show(InfoMessage:new{
            text = _("Failed to create flashcard."),
            timeout = 3,
        })
    end
end

return HighlightBridge
