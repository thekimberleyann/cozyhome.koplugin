-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         learningspace.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-24
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Learning Spaces — class/topic organization.
--       Group books, flashcards, and highlights
--       by subject. Create named classes, add book
--       shortcuts, view related cards and highlights.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - lib/cozyui.lua
--       - lib/database.lua
--       - lib/bookscanner.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

-- ============================================
-- IMPORTS
-- ============================================

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DocSettings = require("docsettings")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

-- IMPORTANT: Multiple cozy plugins have config.lua files. Lua's
-- package.loaded["config"] may point to the wrong one depending on
-- plugin load order. Force-reload our own config if it's missing
-- the UI constants we need.
local Config = require("config")
if not Config.UI or not Config.UI.row_height_class_list then
    package.loaded["config"] = nil
    -- Temporarily prepend our plugin dir to package.path
    local plugin_dir = debug.getinfo(1, "S").source:match("@?(.*/)")
    if plugin_dir then
        local old_path = package.path
        package.path = plugin_dir .. "?.lua;" .. package.path
        Config = require("config")
        package.path = old_path
    end
end
local CozyUI = require("lib/cozyui")
local Database = require("lib/database")
local BookScanner = require("lib/bookscanner")

-- ============================================
-- CONSTANTS
-- ============================================

-- Items-per-page is now calculated dynamically in each screen/tab
-- based on available screen height and row size.

-- ============================================
-- ICON CHOICES for classes
-- ============================================

-- luacheck: ignore 211 (CLASS_ICONS reserved for future icon picker)
local CLASS_ICONS = { "A", "B", "C", "D", "E", "F", "G", "H",
                      "L", "M", "N", "P", "R", "S", "T", "W",
                      "*", "+", "#", "?" }

-- ============================================
-- MODULE
-- ============================================

local LearningSpace = {}
LearningSpace._list_instance = nil
LearningSpace._detail_instance = nil

-- ============================================
-- OPTIONAL PLUGIN INTEGRATION
-- ============================================

-- luacheck: ignore 211 (tryRequirePlugin reserved for future plugin integration)
local function tryRequirePlugin(plugin_path)
    local ok, module = pcall(require, plugin_path)
    if ok then return module end
    return nil
end

-- ============================================
-- CROSS-PLUGIN: FLASHCARD DATABASE ACCESS
-- ============================================
-- The cozy.koplugin stores flashcards in cozy_flashcards.db.
-- We read from it directly (read-only) to get card counts
-- filtered by book_path, which lets us show per-class stats.

local FlashcardBridge = {}

--- Open the cozy flashcards database (read-only queries).
-- Returns a connection or nil.
function FlashcardBridge.openDB()
    local DataStorage = require("datastorage")
    local SQ3 = require("lua-ljsqlite3/init")
    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
    local lfs = require("libs/libkoreader-lfs")
    local attr = lfs.attributes(db_path)
    if not attr then return nil end
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok then return nil end
    return conn
end

--- Get flashcard counts for a set of book paths.
-- @param book_paths table: array of book path strings
-- @return table: { total, due_today, new, learning, review }
function FlashcardBridge.getCountsForBooks(book_paths)
    local counts = { total = 0, due_today = 0, new = 0, learning = 0, review = 0 }
    if not book_paths or type(book_paths) ~= "table" or #book_paths == 0 then return counts end

    -- Validate all paths are non-empty strings before touching the DB
    for i, path in ipairs(book_paths) do
        if type(path) ~= "string" or path == "" then
            logger.warn("CozyHome: FlashcardBridge: Invalid path at index", i)
            return counts  -- Fail safe
        end
    end

    local conn = FlashcardBridge.openDB()
    if not conn then return counts end

    local ok, err = pcall(function()
        -- Build a WHERE IN clause
        local placeholders = {}
        for _ = 1, #book_paths do
            table.insert(placeholders, "?")
        end
        local in_clause = table.concat(placeholders, ",")

        -- Total cards for these books
        local stmt = conn:prepare(
            "SELECT COUNT(*) FROM flashcards WHERE suspended = 0 AND book_path IN (" .. in_clause .. ")"
        )
        if stmt then
            stmt:bind(unpack(book_paths))
            local row = stmt:step()
            if row then counts.total = tonumber(row[1]) or 0 end
            stmt:close()
        end

        -- Due today
        local stmt2 = conn:prepare(
            "SELECT COUNT(*) FROM flashcards WHERE suspended = 0 AND book_path IN (" .. in_clause .. ") "
            .. "AND (next_review IS NULL OR date(next_review) <= date('now', 'localtime'))"
        )
        if stmt2 then
            stmt2:bind(unpack(book_paths))
            local row2 = stmt2:step()
            if row2 then counts.due_today = tonumber(row2[1]) or 0 end
            stmt2:close()
        end

        -- By state
        local stmt3 = conn:prepare(
            "SELECT state, COUNT(*) FROM flashcards WHERE suspended = 0 AND book_path IN (" .. in_clause .. ") GROUP BY state"
        )
        if stmt3 then
            stmt3:bind(unpack(book_paths))
            for row3 in stmt3:rows() do
                local state = row3[1]
                local cnt = tonumber(row3[2]) or 0
                if state == "new" then counts.new = cnt
                elseif state == "learning" then counts.learning = cnt
                elseif state == "review" then counts.review = cnt
                end
            end
            stmt3:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome: FlashcardBridge error:", err)
    end

    pcall(function() conn:close() end)
    return counts
end

--- Get all flashcard IDs for a set of book paths (for category linking).
function FlashcardBridge.getCardIdsForBooks(book_paths)
    local ids = {}
    if not book_paths or type(book_paths) ~= "table" or #book_paths == 0 then return ids end

    -- Validate all paths are non-empty strings
    for i, path in ipairs(book_paths) do
        if type(path) ~= "string" or path == "" then
            logger.warn("CozyHome: FlashcardBridge.getCardIdsForBooks: Invalid path at index", i)
            return ids
        end
    end

    local conn = FlashcardBridge.openDB()
    if not conn then return ids end

    local ok, err = pcall(function()
        local placeholders = {}
        for _ = 1, #book_paths do table.insert(placeholders, "?") end
        local in_clause = table.concat(placeholders, ",")

        local stmt = conn:prepare(
            "SELECT id FROM flashcards WHERE book_path IN (" .. in_clause .. ") ORDER BY created_at DESC"
        )
        if stmt then
            stmt:bind(unpack(book_paths))
            for row in stmt:rows() do
                table.insert(ids, tonumber(row[1]))
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome: FlashcardBridge.getCardIdsForBooks error:", err)
    end

    pcall(function() conn:close() end)
    return ids
end

-- ============================================
-- CROSS-PLUGIN: HIGHLIGHTS / NOTES ACCESS
-- ============================================
-- KOReader stores highlights in sidecar .sdr directories
-- via DocSettings. We read them to count highlights per book.

local HighlightsBridge = {}

--- Count highlights for a single book.
-- @param book_path string
-- @return number: highlight count
function HighlightsBridge.countForBook(book_path)
    local count = 0
    local ok, err = pcall(function()
        local doc_settings = DocSettings:open(book_path)
        if doc_settings then
            local highlights = doc_settings:readSetting("highlights")
            if highlights then
                -- highlights is a table keyed by page number, each value is an array
                for _, page_highlights in pairs(highlights) do
                    if type(page_highlights) == "table" then
                        count = count + #page_highlights
                    end
                end
            end
        end
    end)
    if not ok then
        logger.dbg("CozyHome: HighlightsBridge error for", book_path, err)
    end
    return count
end

--- Count highlights for a set of book paths.
-- @param book_paths table: array of book path strings
-- @return number: total highlight count
function HighlightsBridge.countForBooks(book_paths)
    local total = 0
    if not book_paths then return 0 end
    for _, path in ipairs(book_paths) do
        total = total + HighlightsBridge.countForBook(path)
    end
    return total
end

-- ============================================
-- CLASS PROGRESS HELPER
-- ============================================
-- Aggregates reading progress, flashcard stats, and
-- highlight counts for a class.

local ClassProgress = {}

--- Get aggregated progress for a class.
-- @param class_id number
-- @return table: { books_total, books_finished, books_in_progress,
--                  avg_progress, card_counts, highlight_count }
function ClassProgress.get(class_id)
    local result = {
        books_total = 0,
        books_finished = 0,
        books_in_progress = 0,
        avg_progress = 0,
        card_counts = { total = 0, due_today = 0, new = 0, learning = 0, review = 0 },
        highlight_count = 0,
    }

    local books = Database:getClassBooks(class_id)
    result.books_total = #books

    -- Collect book paths and reading progress
    local book_paths = {}
    local total_progress = 0
    for _, book in ipairs(books) do
        table.insert(book_paths, book.book_path)
        local pct = 0
        local dok, ds = pcall(DocSettings.open, DocSettings, book.book_path)
        if dok and ds then
            local p = ds:readSetting("percent_finished")
            if p then pct = tonumber(p) or 0 end
        end
        total_progress = total_progress + pct
        if pct >= 1.0 then
            result.books_finished = result.books_finished + 1
        elseif pct > 0 then
            result.books_in_progress = result.books_in_progress + 1
        end
    end
    if #books > 0 then
        result.avg_progress = math.floor((total_progress / #books) * 100)
    end

    -- Flashcard counts (from books)
    result.card_counts = FlashcardBridge.getCountsForBooks(book_paths)

    -- Add extra linked card count
    local extra_ids = Database:getClassCardIds(class_id)
    if #extra_ids > 0 then
        result.card_counts.total = result.card_counts.total + #extra_ids
    end

    -- Highlight counts
    result.highlight_count = HighlightsBridge.countForBooks(book_paths)

    return result
end

-- ============================================
-- CLASS LIST SCREEN
-- ============================================

local ClassListScreen = InputContainer:extend{
    name = "cozy_class_list",
    ui = nil,
    on_close_callback = nil,
    current_page = 1,
}

function ClassListScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    LearningSpace._list_instance = self
    self:buildUI()
end

function ClassListScreen:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function ClassListScreen:onCloseWidget()
    LearningSpace._list_instance = nil
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function ClassListScreen:onClose()
    UIManager:close(self)
    if self.on_close_callback then
        UIManager:nextTick(self.on_close_callback)
    end
    return true
end

-- ============================================
-- CLASS LIST UI
-- ============================================

function ClassListScreen:buildUI()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local pad = Config.UI.content_padding
    local content_w = screen_w - pad * 2

    local items = {}
    local list_screen = self

    -- ------------------------------------------
    -- TITLE BAR: [< Back]  ☕ Learning Spaces  [✕]
    -- ------------------------------------------

    table.insert(items, CozyUI.buildScreenHeader({
        sw = screen_w,
        title = "Learning Spaces",
        back_callback = function() list_screen:onClose() end,
        exit_callback = function() list_screen:onClose() end,
        show_parent = self,
    }))

    -- Separator
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 2 },
        LineWidget:new{
            dimen = Geom:new{ w = content_w, h = 1 },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        },
    })
    table.insert(items, VerticalSpan:new{ width = 4 })

    -- "+ New" button row (always visible)
    local new_btn = Button:new{
        text = _("+ New"),
        callback = function()
            list_screen:showCreateClassDialog()
        end,
        bordersize = 1,
        radius = 8,
        text_font_size = 15,
        padding_v = 6,
        show_parent = self,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = new_btn:getSize().h + 4 },
        FrameContainer:new{
            dimen = Geom:new{ w = content_w, h = new_btn:getSize().h + 4 },
            bordersize = 0, padding = 0,
            RightContainer:new{
                dimen = Geom:new{ w = content_w, h = new_btn:getSize().h + 4 },
                new_btn,
            },
        },
    })
    table.insert(items, VerticalSpan:new{ width = 4 })

    -- ------------------------------------------
    -- CLASS LIST
    -- ------------------------------------------

    local classes = Database:getClasses()

    if #classes == 0 then
        -- Empty state
        table.insert(items, VerticalSpan:new{ width = math.floor(screen_h * 0.15) })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 30 },
            TextWidget:new{
                face = Font:getFace("cfont", 18),
                text = _("No learning spaces yet"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        })
        table.insert(items, VerticalSpan:new{ width = 12 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 24 },
            TextWidget:new{
                face = Font:getFace("cfont", 14),
                text = _("Tap '+ New' above to create one"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            },
        })
    else
        -- Paginate
        local row_h = Screen:scaleBySize(Config.UI.row_height_class_list)
        local reserved_h = Screen:scaleBySize(Config.UI.reserved_height_class_list)  -- header + separator + new button + pagination
        local available_h = screen_h - reserved_h
        local items_per_page = math.max(3, math.floor(available_h / (row_h + 1)))

        local total_pages = math.ceil(#classes / items_per_page)
        if self.current_page > total_pages then self.current_page = total_pages end
        if self.current_page < 1 then self.current_page = 1 end

        local start_idx = (self.current_page - 1) * items_per_page + 1
        local end_idx = math.min(start_idx + items_per_page - 1, #classes)

        for i = start_idx, end_idx do
            local cls = classes[i]

            -- Get book count
            local book_count = tonumber(Database:getClassBookCount(cls.id)) or 0

            -- Get progress data (cards, highlights) if there are books
            local progress = nil
            if book_count > 0 then
                progress = ClassProgress.get(cls.id)
            end

            -- Icon
            local icon_text = cls.icon or cls.name:sub(1, 1):upper()
            local icon_w = TextWidget:new{
                face = Font:getFace("tfont", 22),
                text = icon_text,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }

            local icon_frame = FrameContainer:new{
                dimen = Geom:new{ w = 40, h = 40 },
                bordersize = 1,
                radius = 10,
                padding = 2,
                background = Blitbuffer.COLOR_WHITE,
                CenterContainer:new{
                    dimen = Geom:new{ w = 36, h = 36 },
                    icon_w,
                },
            }

            -- Name
            local name_display = cls.name
            if #name_display > 30 then
                name_display = name_display:sub(1, 27) .. "..."
            end
            local name_w = TextWidget:new{
                face = Font:getFace("cfont", 18),
                text = name_display,
                fgcolor = Blitbuffer.COLOR_BLACK,
                bold = true,
            }

            -- Detail line: books, cards due, highlights
            local detail_parts = {}
            if book_count > 0 then
                table.insert(detail_parts, book_count .. " book" .. (book_count ~= 1 and "s" or ""))
            end
            if progress then
                if progress.card_counts.due_today > 0 then
                    table.insert(detail_parts, progress.card_counts.due_today .. " cards due")
                elseif progress.card_counts.total > 0 then
                    table.insert(detail_parts, progress.card_counts.total .. " cards")
                end
                if progress.highlight_count > 0 then
                    table.insert(detail_parts, progress.highlight_count .. " highlight" .. (progress.highlight_count ~= 1 and "s" or ""))
                end
            end
            local detail_str = #detail_parts > 0
                and table.concat(detail_parts, "  --  ")
                or "Empty"

            local detail_w = TextWidget:new{
                face = Font:getFace("cfont", 13),
                text = detail_str,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            }

            local text_col = VerticalGroup:new{
                align = "left",
                name_w,
                VerticalSpan:new{ width = 3 },
                detail_w,
            }

            local row_content = HorizontalGroup:new{
                align = "center",
                HorizontalSpan:new{ width = pad },
                icon_frame,
                HorizontalSpan:new{ width = 12 },
                text_col,
            }

            -- Tappable row
            local class_id = cls.id
            local TappableRow = InputContainer:extend{}
            function TappableRow:init()
                self.dimen = Geom:new{ w = content_w, h = row_h }
                self.ges_events = {
                    TapRow = {
                        GestureRange:new{
                            ges = "tap",
                            range = self.dimen,
                        },
                    },
                    HoldRow = {
                        GestureRange:new{
                            ges = "hold",
                            range = self.dimen,
                        },
                    },
                }
                self[1] = LeftContainer:new{
                    dimen = Geom:new{ w = content_w, h = row_h },
                    row_content,
                }
            end
            TappableRow.onTapRow = function()
                list_screen:openClassDetail(class_id)
                return true
            end
            TappableRow.onHoldRow = function()
                list_screen:showClassActions(class_id, cls.name)
                return true
            end

            local tappable = TappableRow:new{}

            table.insert(items, CenterContainer:new{
                dimen = Geom:new{ w = screen_w, h = row_h },
                tappable,
            })

            -- Row separator
            if i < end_idx then
                table.insert(items, CenterContainer:new{
                    dimen = Geom:new{ w = screen_w, h = 1 },
                    LineWidget:new{
                        dimen = Geom:new{ w = content_w - 20, h = 1 },
                        background = Blitbuffer.COLOR_LIGHT_GRAY,
                    },
                })
            end
        end

        -- ------------------------------------------
        -- PAGINATION
        -- ------------------------------------------

        if total_pages > 1 then
            table.insert(items, VerticalSpan:new{ width = 8 })

            local prev_btn = Button:new{
                text = _("< Prev"),
                enabled = self.current_page > 1,
                callback = function()
                    list_screen.current_page = list_screen.current_page - 1
                    list_screen:refresh()
                end,
                bordersize = 0,
                text_font_size = 14,
                show_parent = self,
            }

            local page_label = TextWidget:new{
                face = Font:getFace("cfont", 14),
                text = string.format(_("Page %d of %d"), self.current_page, total_pages),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            }

            local next_btn = Button:new{
                text = _("Next >"),
                enabled = self.current_page < total_pages,
                callback = function()
                    list_screen.current_page = list_screen.current_page + 1
                    list_screen:refresh()
                end,
                bordersize = 0,
                text_font_size = 14,
                show_parent = self,
            }

            local nav_row = HorizontalGroup:new{
                align = "center",
                prev_btn,
                HorizontalSpan:new{ width = 20 },
                page_label,
                HorizontalSpan:new{ width = 20 },
                next_btn,
            }

            table.insert(items, CenterContainer:new{
                dimen = Geom:new{ w = screen_w, h = 36 },
                nav_row,
            })
        end
    end

    -- ------------------------------------------
    -- ASSEMBLE
    -- ------------------------------------------

    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do
        table.insert(content, item)
    end

    self[1] = FrameContainer:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
end

-- ============================================
-- CLASS LIST ACTIONS
-- ============================================

function ClassListScreen:refresh()
    local ui = self.ui
    local on_close = self.on_close_callback
    local page = self.current_page
    -- Show new screen BEFORE closing old one to prevent UIManager
    -- from seeing an empty stack and exiting KOReader.
    local ok, new_screen = pcall(ClassListScreen.new, ClassListScreen, {
        ui = ui,
        on_close_callback = on_close,
        current_page = page,
    })
    if ok and new_screen then
        UIManager:show(new_screen)
        UIManager:close(self)
    else
        logger.warn("CozyHome LS: refresh() failed to create new screen:", tostring(new_screen))
        -- Don't close self — keep the old screen visible
        UIManager:show(InfoMessage:new{
            text = _("Refresh failed: ") .. tostring(new_screen),
            timeout = 5,
        })
    end
end

function ClassListScreen:showCreateClassDialog()
    local list_screen = self
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
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local raw_name = dialog:getInputText()
                        UIManager:close(dialog)
                        local name = CozyUI.sanitizeInput(raw_name, 100)
                        if name ~= "" then
                            local icon = name:sub(1, 1):upper()
                            local class_id = Database:createClass(name, icon, nil)
                            if class_id then
                                list_screen:refresh()
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

function ClassListScreen:showClassActions(class_id, class_name)
    local list_screen = self
    local dialog
    dialog = ButtonDialog:new{
        title = class_name,
        buttons = {
            {
                {
                    text = _("Open"),
                    callback = function()
                        UIManager:close(dialog)
                        list_screen:openClassDetail(class_id)
                    end,
                },
            },
            {
                {
                    text = _("Rename"),
                    callback = function()
                        UIManager:close(dialog)
                        list_screen:showRenameClassDialog(class_id, class_name)
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(dialog)
                        list_screen:confirmDeleteClass(class_id, class_name)
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function ClassListScreen:showRenameClassDialog(class_id, old_name)
    local list_screen = self
    local dialog
    dialog = InputDialog:new{
        title = _("✦ Rename Learning Space ✦"),
        input = old_name,
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
                    text = _("Rename"),
                    is_enter_default = true,
                    callback = function()
                        local raw_name = dialog:getInputText()
                        UIManager:close(dialog)
                        local new_name = CozyUI.sanitizeInput(raw_name, 100)
                        if new_name ~= "" then
                            local ok = Database:renameClass(class_id, new_name)
                            if ok then
                                list_screen:refresh()
                            else
                                UIManager:show(InfoMessage:new{
                                    text = _("Failed to rename learning space."),
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

function ClassListScreen:confirmDeleteClass(class_id, class_name)
    local list_screen = self
    UIManager:show(ConfirmBox:new{
        text = _("Delete learning space '") .. class_name .. _("'?\n\nThis will remove the class and all its book associations. Your books will not be deleted."),
        ok_text = _("Delete"),
        ok_callback = function()
            local ok = Database:deleteClass(class_id)
            if ok then
                list_screen:refresh()
            else
                UIManager:show(InfoMessage:new{
                    text = _("Failed to delete learning space."),
                    timeout = 3,
                })
            end
        end,
    })
end

function ClassListScreen:openClassDetail(class_id)
    local list_screen = self
    UIManager:close(self)
    UIManager:nextTick(function()
        local detail = ClassDetailScreen:new{
            ui = list_screen.ui,
            class_id = class_id,
            on_close_callback = function()
                LearningSpace.showList(list_screen.ui, list_screen.on_close_callback)
            end,
        }
        UIManager:show(detail)
    end)
end

function ClassListScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end


-- ============================================
-- CLASS DETAIL SCREEN
-- ============================================

ClassDetailScreen = InputContainer:extend{
    name = "cozy_class_detail",
    ui = nil,
    class_id = nil,
    on_close_callback = nil,
    current_tab = "books",  -- "books", "flashcards", or "highlights"
    books_page = 1,
    flashcards_page = 1,
    highlights_page = 1,
}

function ClassDetailScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    LearningSpace._detail_instance = self
    self:buildUI()
end

function ClassDetailScreen:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function ClassDetailScreen:onCloseWidget()
    LearningSpace._detail_instance = nil
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function ClassDetailScreen:onClose()
    UIManager:close(self)
    if self.on_close_callback then
        UIManager:nextTick(self.on_close_callback)
    end
    return true
end

-- ============================================
-- CLASS DETAIL UI
-- ============================================

function ClassDetailScreen:buildUI()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local pad = Config.UI.content_padding
    local content_w = screen_w - pad * 2

    local detail_screen = self
    local items = {}

    -- Load class info
    local cls = Database:getClass(self.class_id)
    if not cls then
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 40 },
            TextWidget:new{
                face = Font:getFace("cfont", 16),
                text = _("Class not found"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        })
        self[1] = FrameContainer:new{
            dimen = Geom:new{ w = screen_w, h = screen_h },
            bordersize = 0, padding = 0,
            background = Blitbuffer.COLOR_WHITE,
            VerticalGroup:new{ align = "center", items[1] },
        }
        return
    end

    -- ------------------------------------------
    -- TITLE BAR: [< Back]  Class Name  [✕]
    -- ------------------------------------------

    local class_name = cls.name
    if #class_name > 25 then
        class_name = class_name:sub(1, 22) .. "..."
    end

    table.insert(items, CozyUI.buildScreenHeader({
        sw = screen_w,
        title = class_name,
        no_prefix = true,
        back_callback = function() detail_screen:onClose() end,
        exit_callback = function() detail_screen:onClose() end,
        show_parent = self,
    }))

    -- Separator
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 2 },
        LineWidget:new{
            dimen = Geom:new{ w = content_w, h = 1 },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        },
    })
    table.insert(items, VerticalSpan:new{ width = 6 })

    -- ------------------------------------------
    -- TAB BAR (Books | Flashcards | Highlights)
    -- ------------------------------------------

    local function tabLabel(tab_key, label)
        if self.current_tab == tab_key then return "[" .. label .. "]" end
        return label
    end

    local books_tab_btn = Button:new{
        text = tabLabel("books", _("Books")),
        callback = function()
            detail_screen.current_tab = "books"
            detail_screen:refreshDetail()
        end,
        bordersize = 0,
        text_font_size = 15,
        text_font_bold = self.current_tab == "books",
        padding = 4,
        show_parent = self,
    }

    local cards_tab_btn = Button:new{
        text = tabLabel("flashcards", _("Flashcards")),
        callback = function()
            detail_screen.current_tab = "flashcards"
            detail_screen:refreshDetail()
        end,
        bordersize = 0,
        text_font_size = 15,
        text_font_bold = self.current_tab == "flashcards",
        padding = 4,
        show_parent = self,
    }

    local hl_tab_btn = Button:new{
        text = tabLabel("highlights", _("Highlights")),
        callback = function()
            detail_screen.current_tab = "highlights"
            detail_screen:refreshDetail()
        end,
        bordersize = 0,
        text_font_size = 15,
        text_font_bold = self.current_tab == "highlights",
        padding = 4,
        show_parent = self,
    }

    -- Right-side action button: "+ Add" on Books, "+ Link Cards" on Notecards
    local add_btn = nil
    if self.current_tab == "books" then
        add_btn = Button:new{
            text = _("+ Add"),
            callback = function()
                detail_screen:showBookPicker()
            end,
            bordersize = 0,
            text_font_size = 15,
            padding = 4,
            show_parent = self,
        }
    elseif self.current_tab == "flashcards" then
        add_btn = Button:new{
            text = _("+ Link Cards"),
            callback = function()
                detail_screen:showCardLinker()
            end,
            bordersize = 0,
            text_font_size = 15,
            padding = 4,
            show_parent = self,
        }
    end

    local tab_buttons = HorizontalGroup:new{
        align = "center",
        books_tab_btn,
        HorizontalSpan:new{ width = 12 },
        cards_tab_btn,
        HorizontalSpan:new{ width = 12 },
        hl_tab_btn,
    }

    -- Measure tabs and add button, allocate space explicitly
    local tabs_w = tab_buttons:getSize().w
    local add_w = add_btn and add_btn:getSize().w or 0
    local tab_gap = 8
    local tab_bar_content
    if add_btn then
        local spacer_w = math.max(0, content_w - tabs_w - add_w - tab_gap)
        tab_bar_content = HorizontalGroup:new{
            align = "center",
            tab_buttons,
            HorizontalSpan:new{ width = spacer_w + tab_gap },
            add_btn,
        }
    else
        tab_bar_content = tab_buttons
    end

    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 36 },
        FrameContainer:new{
            dimen = Geom:new{ w = content_w, h = 36 },
            bordersize = 0, padding = 0,
            tab_bar_content,
        },
    })

    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 2 },
        LineWidget:new{
            dimen = Geom:new{ w = content_w, h = 1 },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        },
    })
    table.insert(items, VerticalSpan:new{ width = 4 })

    -- ------------------------------------------
    -- PROGRESS SUMMARY + QUICK RESUME
    -- ------------------------------------------

    local progress = ClassProgress.get(self.class_id)
    local progress_parts = {}

    if progress.books_total > 0 then
        if progress.books_finished > 0 then
            table.insert(progress_parts, progress.books_finished .. "/" .. progress.books_total .. " finished")
        else
            table.insert(progress_parts, progress.avg_progress .. "% avg progress")
        end
    end
    if progress.card_counts.due_today > 0 then
        table.insert(progress_parts, progress.card_counts.due_today .. " cards due")
    elseif progress.card_counts.total > 0 then
        table.insert(progress_parts, progress.card_counts.total .. " cards")
    end
    if progress.highlight_count > 0 then
        table.insert(progress_parts, progress.highlight_count .. " highlights")
    end

    if #progress_parts > 0 then
        local progress_str = table.concat(progress_parts, "  --  ")
        local progress_tw = TextWidget:new{
            face = Font:getFace("cfont", 12),
            text = progress_str,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }

        -- Quick resume button (if there is a last book or any book)
        local last_book_path = Database:getClassLastBook(self.class_id)
        local resume_target = nil
        if last_book_path then
            -- Verify the book is still in this class
            if Database:isBookInClass(self.class_id, last_book_path) then
                resume_target = last_book_path
            end
        end
        if not resume_target then
            -- Fall back to first book in class
            local class_books = Database:getClassBooks(self.class_id)
            if #class_books > 0 then
                resume_target = class_books[1].book_path
            end
        end

        -- Measure progress text and optional resume button, allocate space explicitly
        local progress_row
        if resume_target then
            local resume_btn = Button:new{
                text = _("Resume >>"),
                callback = function()
                    Database:setClassLastBook(detail_screen.class_id, resume_target)
                    detail_screen:closeAndOpenBook(resume_target)
                end,
                bordersize = 0,
                text_font_size = 12,
                padding = 2,
                show_parent = self,
            }
            local resume_w = resume_btn:getSize().w
            local prog_gap = 8
            local prog_max_w = math.max(0, content_w - resume_w - prog_gap)
            progress_tw.max_width = prog_max_w
            local spacer_w = math.max(0, content_w - progress_tw:getSize().w - resume_w - prog_gap)
            progress_row = HorizontalGroup:new{
                align = "center",
                progress_tw,
                HorizontalSpan:new{ width = spacer_w + prog_gap },
                resume_btn,
            }
        else
            progress_tw.max_width = content_w
            progress_row = progress_tw
        end

        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 22 },
            FrameContainer:new{
                dimen = Geom:new{ w = content_w, h = 22 },
                bordersize = 0, padding = 0,
                progress_row,
            },
        })
        table.insert(items, VerticalSpan:new{ width = 4 })
    end

    -- ------------------------------------------
    -- TAB CONTENT
    -- ------------------------------------------

    if self.current_tab == "books" then
        self:buildBooksTab(items, screen_w, screen_h, content_w, pad)
    elseif self.current_tab == "flashcards" then
        self:buildFlashcardsTab(items, screen_w, screen_h, content_w, pad)
    elseif self.current_tab == "highlights" then
        self:buildHighlightsTab(items, screen_w, screen_h, content_w, pad)
    end

    -- ------------------------------------------
    -- ASSEMBLE
    -- ------------------------------------------

    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do
        table.insert(content, item)
    end

    self[1] = FrameContainer:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
end

-- ============================================
-- BOOKS TAB
-- ============================================

function ClassDetailScreen:buildBooksTab(items, screen_w, screen_h, content_w, pad)
    local detail_screen = self
    local books = Database:getClassBooks(self.class_id)

    if #books == 0 then
        table.insert(items, VerticalSpan:new{ width = math.floor(screen_h * 0.1) })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 30 },
            TextWidget:new{
                face = Font:getFace("cfont", 16),
                text = _("No books in this class yet"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        })
        table.insert(items, VerticalSpan:new{ width = 8 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 24 },
            TextWidget:new{
                face = Font:getFace("cfont", 13),
                text = _("Tap '+ Add' to add books from your library"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            },
        })
        return
    end

    -- Paginate
    local row_h = Screen:scaleBySize(Config.UI.row_height_class_detail)
    local reserved_h = Screen:scaleBySize(Config.UI.reserved_height_class_detail)  -- header + tabs + progress + pagination
    local available_h = screen_h - reserved_h
    local items_per_page = math.max(3, math.floor(available_h / (row_h + 1)))

    local total_pages = math.ceil(#books / items_per_page)
    if self.books_page > total_pages then self.books_page = total_pages end
    if self.books_page < 1 then self.books_page = 1 end

    local start_idx = (self.books_page - 1) * items_per_page + 1
    local end_idx = math.min(start_idx + items_per_page - 1, #books)

    for i = start_idx, end_idx do
        local book = books[i]

        -- Get reading progress
        local progress_text = ""
        local ok, doc_settings = pcall(DocSettings.open, DocSettings, book.book_path)
        if ok and doc_settings then
            local pct = doc_settings:readSetting("percent_finished")
            if pct then
                progress_text = math.floor(pct * 100) .. "%"
            end
        end

        -- Detect file format for indicator tag
        local is_pdf = book.book_path:lower():match("%.pdf$") ~= nil

        -- Title — use max_width to span the full line, TextWidget handles truncation
        local title_display = book.book_title or book.book_path:match("([^/]+)$") or "Unknown"

        local title_tw = TextWidget:new{
            face = Font:getFace("cfont", 16),
            text = title_display,
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = content_w - pad * 2,
        }

        -- Detail line: format tag + author + progress
        local detail_parts = {}
        if is_pdf then
            table.insert(detail_parts, "[PDF]")
        end
        if book.book_author and book.book_author ~= "" then
            local author = book.book_author
            if #author > 25 then author = author:sub(1, 22) .. "..." end
            table.insert(detail_parts, author)
        end
        if progress_text ~= "" then
            table.insert(detail_parts, progress_text)
        end
        local detail_str = table.concat(detail_parts, "  --  ")

        local detail_tw = TextWidget:new{
            face = Font:getFace("cfont", 13),
            text = detail_str,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = content_w - pad * 2,
        }

        local text_col = VerticalGroup:new{
            align = "left",
            title_tw,
            VerticalSpan:new{ width = 2 },
            detail_tw,
        }

        local row_content = HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            text_col,
        }

        -- Tappable row: tap opens book, hold shows actions
        local book_path = book.book_path
        local TappableRow = InputContainer:extend{}
        function TappableRow:init()
            self.dimen = Geom:new{ w = content_w, h = row_h }
            self.ges_events = {
                TapRow = {
                    GestureRange:new{
                        ges = "tap",
                        range = self.dimen,
                    },
                },
                HoldRow = {
                    GestureRange:new{
                        ges = "hold",
                        range = self.dimen,
                    },
                },
            }
            self[1] = LeftContainer:new{
                dimen = Geom:new{ w = content_w, h = row_h },
                row_content,
            }
        end
        TappableRow.onTapRow = function()
            -- Open book in reader
            detail_screen:closeAndOpenBook(book_path)
            return true
        end
        TappableRow.onHoldRow = function()
            detail_screen:showBookActions(book_path, title_display)
            return true
        end

        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = row_h },
            TappableRow:new{},
        })

        if i < end_idx then
            table.insert(items, CenterContainer:new{
                dimen = Geom:new{ w = screen_w, h = 1 },
                LineWidget:new{
                    dimen = Geom:new{ w = content_w - 20, h = 1 },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                },
            })
        end
    end

    -- Pagination
    if total_pages > 1 then
        table.insert(items, VerticalSpan:new{ width = 8 })

        local prev_btn = Button:new{
            text = _("< Prev"),
            enabled = self.books_page > 1,
            callback = function()
                detail_screen.books_page = detail_screen.books_page - 1
                detail_screen:refreshDetail()
            end,
            bordersize = 0,
            text_font_size = 14,
            show_parent = self,
        }

        local page_label = TextWidget:new{
            face = Font:getFace("cfont", 14),
            text = string.format(_("Page %d of %d"), self.books_page, total_pages),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }

        local next_btn = Button:new{
            text = _("Next >"),
            enabled = self.books_page < total_pages,
            callback = function()
                detail_screen.books_page = detail_screen.books_page + 1
                detail_screen:refreshDetail()
            end,
            bordersize = 0,
            text_font_size = 14,
            show_parent = self,
        }

        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 36 },
            HorizontalGroup:new{
                align = "center",
                prev_btn,
                HorizontalSpan:new{ width = 20 },
                page_label,
                HorizontalSpan:new{ width = 20 },
                next_btn,
            },
        })
    end
end

-- ============================================
-- FLASHCARDS TAB
-- ============================================

function ClassDetailScreen:buildFlashcardsTab(items, screen_w, screen_h, content_w, pad)
    local detail_screen = self

    -- Get book paths for this class
    local books = Database:getClassBooks(self.class_id)
    local book_paths = {}
    for _, b in ipairs(books) do
        table.insert(book_paths, b.book_path)
    end

    -- Get extra linked card IDs from cozyhome DB
    local extra_card_ids = Database:getClassCardIds(self.class_id)

    -- No books AND no extra cards = show empty + link button
    if #book_paths == 0 and #extra_card_ids == 0 then
        table.insert(items, VerticalSpan:new{ width = math.floor(screen_h * 0.08) })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 30 },
            TextWidget:new{
                face = Font:getFace("cfont", 16),
                text = _("No flashcards in this space yet"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        })
        table.insert(items, VerticalSpan:new{ width = 6 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 24 },
            TextWidget:new{
                face = Font:getFace("cfont", 13),
                text = _("Use + Link Cards above to add cards"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            },
        })
        return
    end

    -- Get flashcards for these books + extra linked cards
    local cards = {}
    local seen_ids = {}
    local conn = FlashcardBridge.openDB()
    if conn then
        pcall(function()
            -- Cards from class books
            if #book_paths > 0 then
                local placeholders = {}
                for _ = 1, #book_paths do table.insert(placeholders, "?") end
                local in_clause = table.concat(placeholders, ",")
                local stmt = conn:prepare(
                    "SELECT id, front, back, state, book_title, book_path, "
                    .. "next_review, review_count, suspended "
                    .. "FROM flashcards WHERE book_path IN (" .. in_clause .. ") "
                    .. "ORDER BY created_at DESC"
                )
                if stmt then
                    stmt:bind(unpack(book_paths))
                    for row in stmt:rows() do
                        local card_id = tonumber(row[1])
                        seen_ids[card_id] = true
                        table.insert(cards, {
                            id = card_id,
                            front = row[2] or "",
                            back = row[3] or "",
                            state = row[4] or "new",
                            book_title = row[5] or "",
                            book_path = row[6] or "",
                            next_review = row[7],
                            review_count = tonumber(row[8]) or 0,
                            suspended = tonumber(row[9]) or 0,
                            linked = false,
                        })
                    end
                    stmt:close()
                end
            end

            -- Extra linked cards (by ID)
            for _, cid in ipairs(extra_card_ids) do
                if not seen_ids[cid] then
                    local stmt2 = conn:prepare(
                        "SELECT id, front, back, state, book_title, book_path, "
                        .. "next_review, review_count, suspended "
                        .. "FROM flashcards WHERE id = ?"
                    )
                    if stmt2 then
                        stmt2:bind(cid)
                        local row = stmt2:step()
                        if row then
                            seen_ids[cid] = true
                            table.insert(cards, {
                                id = tonumber(row[1]),
                                front = row[2] or "",
                                back = row[3] or "",
                                state = row[4] or "new",
                                book_title = row[5] or "",
                                book_path = row[6] or "",
                                next_review = row[7],
                                review_count = tonumber(row[8]) or 0,
                                suspended = tonumber(row[9]) or 0,
                                linked = true,
                            })
                        end
                        stmt2:close()
                    end
                end
            end
        end)
        pcall(function() conn:close() end)
    end

    -- Summary
    local active_cards = {}
    local due_count = 0
    local today = os.date("%Y-%m-%d")
    for _, c in ipairs(cards) do
        if c.suspended == 0 then
            table.insert(active_cards, c)
            if not c.next_review or c.next_review <= today then
                due_count = due_count + 1
            end
        end
    end

    local summary_text = #active_cards .. " cards"
    if due_count > 0 then
        summary_text = summary_text .. "  ·  " .. due_count .. " due today"
    end
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 22 },
        TextWidget:new{
            face = Font:getFace("smallinfofont"),
            text = summary_text,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        },
    })
    table.insert(items, VerticalSpan:new{ width = 4 })

    if #active_cards == 0 then
        table.insert(items, VerticalSpan:new{ width = math.floor(screen_h * 0.06) })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 30 },
            TextWidget:new{
                face = Font:getFace("cfont", 15),
                text = _("No flashcards for these books yet"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            },
        })
        table.insert(items, VerticalSpan:new{ width = 6 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 24 },
            TextWidget:new{
                face = Font:getFace("cfont", 13),
                text = _("Create cards in Cozy Flashcards"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            },
        })
        return
    end

    -- Paginate
    local row_h = Screen:scaleBySize(Config.UI.row_height_class_flashcards)
    local reserved_h = Screen:scaleBySize(Config.UI.reserved_height_class_flashcards)  -- header + tabs + progress + pagination
    local available_h = screen_h - reserved_h
    local items_per_page = math.max(3, math.floor(available_h / (row_h + 1)))

    local total_pages = math.ceil(#active_cards / items_per_page)
    if self.flashcards_page > total_pages then self.flashcards_page = total_pages end
    if self.flashcards_page < 1 then self.flashcards_page = 1 end
    local start_idx = (self.flashcards_page - 1) * items_per_page + 1
    local end_idx = math.min(start_idx + items_per_page - 1, #active_cards)

    for i = start_idx, end_idx do
        local card = active_cards[i]

        -- Status icon
        local icon = "✧"  -- new
        if card.state == "learning" then icon = "✦"
        elseif card.state == "review" then icon = "✦" end

        -- Front text preview
        local front_display = card.front or ""
        front_display = front_display:gsub("\n", " "):gsub("%s+", " ")
        if #front_display > 55 then front_display = front_display:sub(1, 52) .. "..." end

        local title_tw = TextWidget:new{
            face = Font:getFace("cfont", 16),
            text = icon .. " " .. front_display,
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = content_w - pad,
        }

        -- Detail: state, book, review count
        local detail_parts = {}
        table.insert(detail_parts, card.state)
        if card.book_title and card.book_title ~= "" then
            local bt = card.book_title
            if #bt > 22 then bt = bt:sub(1, 19) .. "..." end
            table.insert(detail_parts, bt)
        end
        if card.review_count > 0 then
            table.insert(detail_parts, card.review_count .. "× reviewed")
        end

        local detail_tw = TextWidget:new{
            face = Font:getFace("cfont", 13),
            text = table.concat(detail_parts, "  ·  "),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = content_w - pad,
        }

        local text_col = VerticalGroup:new{
            align = "left",
            title_tw,
            VerticalSpan:new{ width = 3 },
            detail_tw,
        }

        local row_content = HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            text_col,
        }

        -- Tappable row — tap shows front/back preview
        local card_ref = card
        local TappableRow = InputContainer:extend{}
        function TappableRow:init()
            self.dimen = Geom:new{ w = content_w, h = row_h }
            self.ges_events = {
                TapRow = {
                    GestureRange:new{
                        ges = "tap",
                        range = self.dimen,
                    },
                },
            }
            self[1] = LeftContainer:new{
                dimen = Geom:new{ w = content_w, h = row_h },
                row_content,
            }
        end
        TappableRow.onTapRow = function()
            local back_preview = card_ref.back or ""
            if #back_preview > 300 then back_preview = back_preview:sub(1, 297) .. "..." end
            UIManager:show(InfoMessage:new{
                text = "Front:\n" .. (card_ref.front or "") .. "\n\n"
                    .. string.rep("─", 30) .. "\n\n"
                    .. "Back:\n" .. back_preview,
                width = screen_w * 0.85,
            })
            return true
        end

        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = row_h },
            TappableRow:new{},
        })

        if i < end_idx then
            table.insert(items, CenterContainer:new{
                dimen = Geom:new{ w = screen_w, h = 1 },
                LineWidget:new{
                    dimen = Geom:new{ w = content_w - 20, h = 1 },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                },
            })
        end
    end

    -- Pagination
    if total_pages > 1 then
        table.insert(items, VerticalSpan:new{ width = 8 })
        local prev_btn = Button:new{
            text = _("< Prev"),
            enabled = self.flashcards_page > 1,
            callback = function()
                detail_screen.flashcards_page = detail_screen.flashcards_page - 1
                detail_screen:refreshDetail()
            end,
            bordersize = 0, text_font_size = 14, show_parent = self,
        }
        local page_label = TextWidget:new{
            face = Font:getFace("cfont", 14),
            text = string.format(_("Page %d of %d"), self.flashcards_page, total_pages),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
        local next_btn = Button:new{
            text = _("Next >"),
            enabled = self.flashcards_page < total_pages,
            callback = function()
                detail_screen.flashcards_page = detail_screen.flashcards_page + 1
                detail_screen:refreshDetail()
            end,
            bordersize = 0, text_font_size = 14, show_parent = self,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 36 },
            HorizontalGroup:new{
                align = "center",
                prev_btn,
                HorizontalSpan:new{ width = 20 },
                page_label,
                HorizontalSpan:new{ width = 20 },
                next_btn,
            },
        })
    end

end

-- ============================================
-- CARD LINKER (pick cards to add to class)
-- ============================================

function ClassDetailScreen:showCardLinker()
    local detail_screen = self

    -- Fetch all cards from flashcard DB
    local all_cards = {}
    local conn = FlashcardBridge.openDB()
    if not conn then
        UIManager:show(InfoMessage:new{
            text = _("Cozy Flashcards database not found.\n\nCreate flashcards first."),
            timeout = 3,
        })
        return
    end

    pcall(function()
        local stmt = conn:prepare(
            "SELECT id, front, state, book_title, suspended "
            .. "FROM flashcards ORDER BY created_at DESC LIMIT 200"
        )
        if stmt then
            for row in stmt:rows() do
                table.insert(all_cards, {
                    id = tonumber(row[1]),
                    front = row[2] or "",
                    state = row[3] or "new",
                    book_title = row[4] or "",
                    suspended = tonumber(row[5]) or 0,
                })
            end
            stmt:close()
        end
    end)
    pcall(function() conn:close() end)

    if #all_cards == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No flashcards found. Create some in Cozy Flashcards first."),
            timeout = 3,
        })
        return
    end

    -- Get book paths so we can tell which cards are already included via books
    local books = Database:getClassBooks(self.class_id)
    local book_path_set = {}
    for _, b in ipairs(books) do
        book_path_set[b.book_path] = true
    end

    -- Build button rows — show card front + toggle linked status
    local button_rows = {}
    local shown = 0
    for _, card in ipairs(all_cards) do
        if shown >= 30 then break end  -- keep dialog manageable
        if card.suspended == 0 then
            -- Skip cards already covered by class books
            local from_class_book = card.book_title ~= "" and book_path_set[card.book_title]
            -- Actually check by book_path not title — but we don't have book_path here.
            -- So we check if this card is already linked directly
            local is_linked = Database:isCardInClass(self.class_id, card.id)

            local front_preview = card.front:gsub("\n", " "):gsub("%s+", " ")
            if #front_preview > 40 then front_preview = front_preview:sub(1, 37) .. "..." end

            local marker = is_linked and "[✦] " or "[  ] "
            local label = marker .. front_preview

            local card_id = card.id
            table.insert(button_rows, {{
                text = label,
                callback = function()
                    if Database:isCardInClass(detail_screen.class_id, card_id) then
                        Database:removeCardFromClass(detail_screen.class_id, card_id)
                    else
                        Database:addCardToClass(detail_screen.class_id, card_id)
                    end
                    UIManager:close(detail_screen._card_linker_dialog)
                    detail_screen:showCardLinker()
                end,
            }})
            shown = shown + 1
        end
    end

    table.insert(button_rows, {{
        text = _("Done"),
        callback = function()
            UIManager:close(detail_screen._card_linker_dialog)
            detail_screen:refreshDetail()
        end,
    }})

    detail_screen._card_linker_dialog = ButtonDialog:new{
        title = _("✦ Link Cards to Class ✦"),
        buttons = button_rows,
    }
    UIManager:show(detail_screen._card_linker_dialog)
end

-- ============================================
-- HIGHLIGHTS TAB
-- ============================================

function ClassDetailScreen:buildHighlightsTab(items, screen_w, screen_h, content_w, pad)
    local detail_screen = self

    -- Get book paths for this class
    local books = Database:getClassBooks(self.class_id)
    local book_paths = {}
    local book_titles = {}  -- path → title lookup
    for _, b in ipairs(books) do
        table.insert(book_paths, b.book_path)
        book_titles[b.book_path] = b.book_title or b.book_path:match("([^/]+)$") or "Unknown"
    end

    if #book_paths == 0 then
        table.insert(items, VerticalSpan:new{ width = math.floor(screen_h * 0.1) })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 30 },
            TextWidget:new{
                face = Font:getFace("cfont", 16),
                text = _("Add books first to see their highlights"),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        })
        return
    end

    -- Collect highlights from all class books
    local all_hl = {}
    local HL_mod = nil
    pcall(function() HL_mod = require("lib/highlights") end)

    for _, path in ipairs(book_paths) do
        local hls = {}
        if HL_mod then
            hls = HL_mod.getHighlights(path) or {}
        end
        local title = book_titles[path] or "Unknown"
        for _, hl in ipairs(hls) do
            hl.book_path = path
            hl.book_title = title
            table.insert(all_hl, hl)
        end
    end

    -- Sort by book then page
    table.sort(all_hl, function(a, b)
        local pa = a.pageno or (a.progress_percent and a.progress_percent * 1000) or 0
        local pb = b.pageno or (b.progress_percent and b.progress_percent * 1000) or 0
        if a.book_path ~= b.book_path then
            return (a.book_title or "") < (b.book_title or "")
        end
        return pa < pb
    end)

    -- Summary
    local summary_text = #all_hl .. " highlights across " .. #book_paths .. " book" .. (#book_paths ~= 1 and "s" or "")
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 22 },
        TextWidget:new{
            face = Font:getFace("smallinfofont"),
            text = summary_text,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        },
    })
    table.insert(items, VerticalSpan:new{ width = 4 })

    if #all_hl == 0 then
        table.insert(items, VerticalSpan:new{ width = math.floor(screen_h * 0.06) })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 30 },
            TextWidget:new{
                face = Font:getFace("cfont", 15),
                text = _("No highlights in these books yet"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            },
        })
        table.insert(items, VerticalSpan:new{ width = 6 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 24 },
            TextWidget:new{
                face = Font:getFace("cfont", 13),
                text = _("Highlight text while reading to see it here"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            },
        })
        return
    end

    -- Paginate
    local row_h = Screen:scaleBySize(Config.UI.row_height_class_highlights)
    local reserved_h = Screen:scaleBySize(Config.UI.reserved_height_class_highlights)  -- header + tabs + progress + pagination
    local available_h = screen_h - reserved_h
    local items_per_page = math.max(3, math.floor(available_h / (row_h + 1)))

    local total_pages = math.ceil(#all_hl / items_per_page)
    if self.highlights_page > total_pages then self.highlights_page = total_pages end
    if self.highlights_page < 1 then self.highlights_page = 1 end
    local start_idx = (self.highlights_page - 1) * items_per_page + 1
    local end_idx = math.min(start_idx + items_per_page - 1, #all_hl)

    for i = start_idx, end_idx do
        local hl = all_hl[i]

        -- Icon
        local icon = "✦"
        if hl.note and hl.note ~= "" then icon = "✦" end

        -- Text preview
        local text_preview = (hl.text or "[Bookmark]"):gsub("\n", " "):gsub("%s+", " ")
        if #text_preview > 65 then text_preview = text_preview:sub(1, 62) .. "..." end

        local title_tw = TextWidget:new{
            face = Font:getFace("cfont", 16),
            text = icon .. " " .. text_preview,
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = content_w - pad,
        }

        -- Detail: book title, page, note indicator
        local detail_parts = {}
        local bt = hl.book_title or ""
        if #bt > 22 then bt = bt:sub(1, 19) .. "..." end
        if bt ~= "" then table.insert(detail_parts, bt) end
        if hl.pageno then table.insert(detail_parts, "p." .. hl.pageno) end
        if hl.note and hl.note ~= "" then table.insert(detail_parts, "📝") end
        if hl.chapter and hl.chapter ~= "" then
            local ch = hl.chapter
            if #ch > 20 then ch = ch:sub(1, 17) .. "..." end
            table.insert(detail_parts, ch)
        end

        local detail_tw = TextWidget:new{
            face = Font:getFace("cfont", 13),
            text = table.concat(detail_parts, "  ·  "),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = content_w - pad,
        }

        local text_col = VerticalGroup:new{
            align = "left",
            title_tw,
            VerticalSpan:new{ width = 3 },
            detail_tw,
        }

        local row_content = HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            text_col,
        }

        -- Tappable row — tap shows full highlight text + note
        local hl_ref = hl
        local TappableRow = InputContainer:extend{}
        function TappableRow:init()
            self.dimen = Geom:new{ w = content_w, h = row_h }
            self.ges_events = {
                TapRow = {
                    GestureRange:new{
                        ges = "tap",
                        range = self.dimen,
                    },
                },
            }
            self[1] = LeftContainer:new{
                dimen = Geom:new{ w = content_w, h = row_h },
                row_content,
            }
        end
        TappableRow.onTapRow = function()
            local msg = hl_ref.text or "[No text]"
            if hl_ref.note and hl_ref.note ~= "" then
                msg = msg .. "\n\n" .. string.rep("─", 30) .. "\n\n📝 " .. hl_ref.note
            end
            if hl_ref.book_title then
                msg = msg .. "\n\n— " .. hl_ref.book_title
                if hl_ref.pageno then msg = msg .. ", p." .. hl_ref.pageno end
            end
            UIManager:show(InfoMessage:new{
                text = msg,
                width = screen_w * 0.85,
            })
            return true
        end

        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = row_h },
            TappableRow:new{},
        })

        if i < end_idx then
            table.insert(items, CenterContainer:new{
                dimen = Geom:new{ w = screen_w, h = 1 },
                LineWidget:new{
                    dimen = Geom:new{ w = content_w - 20, h = 1 },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                },
            })
        end
    end

    -- Pagination
    if total_pages > 1 then
        table.insert(items, VerticalSpan:new{ width = 8 })
        local prev_btn = Button:new{
            text = _("< Prev"),
            enabled = self.highlights_page > 1,
            callback = function()
                detail_screen.highlights_page = detail_screen.highlights_page - 1
                detail_screen:refreshDetail()
            end,
            bordersize = 0, text_font_size = 14, show_parent = self,
        }
        local page_label = TextWidget:new{
            face = Font:getFace("cfont", 14),
            text = string.format(_("Page %d of %d"), self.highlights_page, total_pages),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
        local next_btn = Button:new{
            text = _("Next >"),
            enabled = self.highlights_page < total_pages,
            callback = function()
                detail_screen.highlights_page = detail_screen.highlights_page + 1
                detail_screen:refreshDetail()
            end,
            bordersize = 0, text_font_size = 14, show_parent = self,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 36 },
            HorizontalGroup:new{
                align = "center",
                prev_btn,
                HorizontalSpan:new{ width = 20 },
                page_label,
                HorizontalSpan:new{ width = 20 },
                next_btn,
            },
        })
    end
end

-- ============================================
-- BOOK PICKER (from library scan)
-- ============================================

function ClassDetailScreen:showBookPicker()
    local detail_screen = self

    -- Show loading message
    local loading = InfoMessage:new{
        text = _("Scanning library..."),
        timeout = 30,
    }
    UIManager:show(loading)
    UIManager:forceRePaint()

    -- Schedule the scan so the loading message actually displays
    UIManager:nextTick(function()
        UIManager:close(loading)

        -- Scan books
        local scan_root = G_reader_settings:readSetting("home_dir")
            or Device.home_dir
            or "/mnt/onboard"
        local hidden_folders = Database:getHiddenFolders()
        local all_books = BookScanner.scan(scan_root, hidden_folders)

        if #all_books == 0 then
            UIManager:show(InfoMessage:new{
                text = _("No books found on device."),
                timeout = 3,
            })
            return
        end

        -- Fast metadata enrichment (single bulk query)
        BookScanner.enrichMetadataFast(all_books)

        -- Sort by title
        table.sort(all_books, function(a, b)
            return (a.title or ""):lower() < (b.title or ""):lower()
        end)

        -- Build a picker using ButtonDialog with scrollable list
        -- For simplicity, show a paginated picker screen
        detail_screen:showBookPickerScreen(all_books)
    end)
end

-- ============================================
-- BOOK PICKER SCREEN (paginated list)
-- ============================================

local BookPickerScreen = InputContainer:extend{
    name = "cozy_book_picker",
    ui = nil,
    class_id = nil,
    books = nil,
    on_done_callback = nil,
    current_page = 1,
}

function BookPickerScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self:buildUI()
end

function BookPickerScreen:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function BookPickerScreen:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function BookPickerScreen:onClose()
    UIManager:close(self)
    if self.on_done_callback then
        UIManager:nextTick(self.on_done_callback)
    end
    return true
end

function BookPickerScreen:buildUI()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local pad = Config.UI.content_padding
    local content_w = screen_w - pad * 2

    local picker = self
    local items = {}

    -- Title bar: [< Done]  ☕ Add Books  [✕]
    table.insert(items, CozyUI.buildScreenHeader({
        sw = screen_w,
        title = "Add Books",
        back_callback = function() picker:onClose() end,
        exit_callback = function() picker:onClose() end,
        show_parent = self,
    }))

    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 2 },
        LineWidget:new{
            dimen = Geom:new{ w = content_w, h = 1 },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        },
    })
    table.insert(items, VerticalSpan:new{ width = 4 })

    -- Hint
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 22 },
        TextWidget:new{
            face = Font:getFace("cfont", 12),
            text = _("Tap a book to add/remove it from this class"),
            fgcolor = Blitbuffer.COLOR_GRAY,
        },
    })
    table.insert(items, VerticalSpan:new{ width = 4 })

    -- Book list (paginated)
    local books = self.books or {}
    local row_h = Screen:scaleBySize(Config.UI.row_height_book_picker)
    local reserved_h = Screen:scaleBySize(Config.UI.reserved_height_book_picker)  -- header + hint + pagination
    local available_h = screen_h - reserved_h
    local items_per_page = math.max(3, math.floor(available_h / (row_h + 1)))

    local total_pages = math.max(1, math.ceil(#books / items_per_page))
    if self.current_page > total_pages then self.current_page = total_pages end
    if self.current_page < 1 then self.current_page = 1 end

    local start_idx = (self.current_page - 1) * items_per_page + 1
    local end_idx = math.min(start_idx + items_per_page - 1, #books)

    for i = start_idx, end_idx do
        local book = books[i]

        -- Check if already in class
        local in_class = Database:isBookInClass(self.class_id, book.path)

        local marker = in_class and "[x] " or "[ ] "
        local title_display = book.title or book.path:match("([^/]+)$") or "Unknown"
        if #title_display > 35 then
            title_display = title_display:sub(1, 32) .. "..."
        end

        -- Add format tag for PDFs so user knows before adding
        local is_pdf = book.path:lower():match("%.pdf$") ~= nil
        local row_text = marker .. title_display
        local title_tw = TextWidget:new{
            face = Font:getFace("cfont", 15),
            text = row_text,
            fgcolor = in_class and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        }

        -- Author subtitle + format tag
        local author_parts = {}
        if is_pdf then
            table.insert(author_parts, "[PDF]")
        end
        if book.author and book.author ~= "" then
            local author_str = book.author
            if #author_str > 35 then author_str = author_str:sub(1, 32) .. "..." end
            table.insert(author_parts, author_str)
        end
        local author_str = table.concat(author_parts, "  ")
        local author_tw = TextWidget:new{
            face = Font:getFace("cfont", 12),
            text = author_str,
            fgcolor = Blitbuffer.COLOR_GRAY,
        }

        local text_col = VerticalGroup:new{
            align = "left",
            title_tw,
            VerticalSpan:new{ width = 2 },
            author_tw,
        }

        local row_content = HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = pad },
            text_col,
        }

        local book_path = book.path
        local book_title = book.title
        local book_author = book.author
        local TappableRow = InputContainer:extend{}
        function TappableRow:init()
            self.dimen = Geom:new{ w = content_w, h = row_h }
            self.ges_events = {
                TapRow = {
                    GestureRange:new{
                        ges = "tap",
                        range = self.dimen,
                    },
                },
            }
            self[1] = LeftContainer:new{
                dimen = Geom:new{ w = content_w, h = row_h },
                row_content,
            }
        end
        TappableRow.onTapRow = function()
            if Database:isBookInClass(picker.class_id, book_path) then
                Database:removeBookFromClass(picker.class_id, book_path)
            else
                Database:addBookToClass(picker.class_id, book_path, book_title, book_author)
            end
            picker:refreshPicker()
            return true
        end

        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = row_h },
            TappableRow:new{},
        })

        if i < end_idx then
            table.insert(items, CenterContainer:new{
                dimen = Geom:new{ w = screen_w, h = 1 },
                LineWidget:new{
                    dimen = Geom:new{ w = content_w - 20, h = 1 },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                },
            })
        end
    end

    -- Pagination
    if total_pages > 1 then
        table.insert(items, VerticalSpan:new{ width = 6 })

        local prev_btn = Button:new{
            text = _("< Prev"),
            enabled = self.current_page > 1,
            callback = function()
                picker.current_page = picker.current_page - 1
                picker:refreshPicker()
            end,
            bordersize = 0,
            text_font_size = 14,
            show_parent = self,
        }

        local page_label = TextWidget:new{
            face = Font:getFace("cfont", 14),
            text = string.format(_("Page %d of %d"), self.current_page, total_pages),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }

        local next_btn = Button:new{
            text = _("Next >"),
            enabled = self.current_page < total_pages,
            callback = function()
                picker.current_page = picker.current_page + 1
                picker:refreshPicker()
            end,
            bordersize = 0,
            text_font_size = 14,
            show_parent = self,
        }

        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 36 },
            HorizontalGroup:new{
                align = "center",
                prev_btn,
                HorizontalSpan:new{ width = 20 },
                page_label,
                HorizontalSpan:new{ width = 20 },
                next_btn,
            },
        })
    end

    -- Assemble
    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do
        table.insert(content, item)
    end

    self[1] = FrameContainer:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
end

function BookPickerScreen:refreshPicker()
    -- Show new screen BEFORE closing old one to prevent UIManager
    -- from seeing an empty stack and exiting KOReader.
    local new_picker = BookPickerScreen:new{
        ui = self.ui,
        class_id = self.class_id,
        books = self.books,
        on_done_callback = self.on_done_callback,
        current_page = self.current_page,
    }
    UIManager:show(new_picker)
    UIManager:close(self)
end

function BookPickerScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

-- ============================================
-- CLASS DETAIL HELPERS
-- ============================================

function ClassDetailScreen:showBookPickerScreen(all_books)
    local detail_screen = self
    UIManager:close(self)
    UIManager:nextTick(function()
        local picker = BookPickerScreen:new{
            ui = detail_screen.ui,
            class_id = detail_screen.class_id,
            books = all_books,
            on_done_callback = function()
                -- Return to class detail
                local new_detail = ClassDetailScreen:new{
                    ui = detail_screen.ui,
                    class_id = detail_screen.class_id,
                    current_tab = "books",
                    on_close_callback = detail_screen.on_close_callback,
                }
                UIManager:show(new_detail)
            end,
        }
        UIManager:show(picker)
    end)
end


function ClassDetailScreen:showBookActions(book_path, title)
    local detail_screen = self
    local dialog
    dialog = ButtonDialog:new{
        title = title,
        buttons = {
            {
                {
                    text = _("Open Book"),
                    callback = function()
                        UIManager:close(dialog)
                        detail_screen:closeAndOpenBook(book_path)
                    end,
                },
            },
            {
                {
                    text = _("Remove from Class"),
                    callback = function()
                        UIManager:close(dialog)
                        Database:removeBookFromClass(detail_screen.class_id, book_path)
                        detail_screen:refreshDetail()
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end


function ClassDetailScreen:closeAndOpenBook(book_path)
    -- Record this as the last-opened book for quick resume
    Database:setClassLastBook(self.class_id, book_path)

    -- Show a one-time tip for PDF books about highlight limitations.
    -- Scanned PDFs without a text layer can't be highlighted and will
    -- freeze if the user tries to long-press select text. We warn once
    -- per book so the user knows before they hit the issue.
    local is_pdf = book_path:lower():match("%.pdf$") ~= nil
    local tip_shown = false
    if is_pdf then
        local tip_key = "cozyhome_pdf_tip_shown:" .. book_path
        if not G_reader_settings:isTrue(tip_key) then
            G_reader_settings:saveSetting(tip_key, true)
            tip_shown = true
        end
    end

    UIManager:close(self)
    UIManager:nextTick(function()
        if tip_shown then
            UIManager:show(InfoMessage:new{
                text = _("Note: This is a PDF file.\n\nIf it's a scanned document (images only), text selection and highlighting won't work. You may need Tesseract OCR data for text extraction.\n\nNative-text PDFs work fine."),
                timeout = 8,
            })
        end
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(book_path)
    end)
end

function ClassDetailScreen:refreshDetail()
    local class_id = self.class_id
    local current_tab = self.current_tab
    local on_close = self.on_close_callback
    local ui = self.ui
    local bp = self.books_page
    local fcp = self.flashcards_page
    local hlp = self.highlights_page

    -- Show new screen BEFORE closing old one to prevent UIManager
    -- from seeing an empty stack and exiting KOReader.
    local new_detail = ClassDetailScreen:new{
        ui = ui,
        class_id = class_id,
        current_tab = current_tab,
        on_close_callback = on_close,
        books_page = bp,
        flashcards_page = fcp,
        highlights_page = hlp,
    }
    UIManager:show(new_detail)
    UIManager:close(self)
end

function ClassDetailScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end


-- ============================================
-- PUBLIC API
-- ============================================

--- Show the class list screen.
function LearningSpace.show(ui, on_close_callback)
    LearningSpace.showList(ui, on_close_callback)
end

--- Show the class list screen.
function LearningSpace.showList(ui, on_close_callback)
    if LearningSpace._list_instance then
        UIManager:close(LearningSpace._list_instance)
        LearningSpace._list_instance = nil
    end

    local screen = ClassListScreen:new{
        ui = ui,
        on_close_callback = on_close_callback,
    }
    UIManager:show(screen)
end

--- Open a specific class detail screen.
function LearningSpace.openClass(ui, class_id, on_close_callback)
    local detail = ClassDetailScreen:new{
        ui = ui,
        class_id = class_id,
        on_close_callback = on_close_callback,
    }
    UIManager:show(detail)
end

return LearningSpace
