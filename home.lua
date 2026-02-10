-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         home.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-05
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Welcome dashboard screen. Shows continue-reading
--       card, navigation tiles, stats bar, and greeting.
--       Styled to Cozy Design System.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - lib/cozyui.lua
--       - statusbar.lua
--       - history.lua
--       - library.lua
--       - notebooks.lua
--       - learningspace.lua
--       - notecards.lua
--       - highlights.lua
--       - settings.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")

local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local InfoMessage = require("ui/widget/infomessage")

local DocSettings = require("docsettings")
local ReadHistory = require("readhistory")
local Screen = Device.screen
local _ = require("gettext")
local logger = require("logger")

local Config = require("config")
local CozyUI = require("lib/cozyui")
local StatusBar = require("statusbar")
local Database = require("lib/database")
local History = require("history")
local Library = require("library")
local Notebooks = require("notebooks")
local LearningSpace = require("learningspace")
local Notecards = require("notecards")
local Settings = require("settings")
local HighlightsScreen = require("highlights")
local FocusMode = require("focusmode")

local BLACK      = CozyUI.BLACK
local DARK_GRAY  = CozyUI.DARK_GRAY
local GRAY       = CozyUI.GRAY
local LIGHT_GRAY = CozyUI.LIGHT_GRAY
local WHITE      = CozyUI.WHITE
local sp         = CozyUI.sp

-- ─────────────────────────────────────────
-- CozyHomeScreen
-- ─────────────────────────────────────────

local CozyHomeScreen = InputContainer:extend{
    name = "cozy_home_screen",
    ui = nil,
    on_close_callback = nil,
    _cached_book_info = nil,
    _cached_stats_text = nil,
    _cover_bb = nil,  -- cached cover blitbuffer for continue-reading book
}

local Home = {}
Home._current_instance = nil

function CozyHomeScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    Database:open()
    self._cached_book_info = self:getLastBookInfo()
    self._cached_stats_text = self:computeStatsText()
    Home._current_instance = self
    self:checkFirstRun()
    self:buildUI()
end

function CozyHomeScreen:checkFirstRun()
    local first_run_done = Database:getPref("first_run_complete", nil)
    if first_run_done then return end
    Database:setPref("first_run_complete", "true")
    UIManager:nextTick(function()
        UIManager:show(InfoMessage:new{
            text = _("☕ Welcome to Cozy Home!\n\n"
                .. "Your customizable KOReader dashboard.\n\n"
                .. "· Books — browse your library\n"
                .. "· Notebooks — stylus drawing\n"
                .. "· Learn Space — group by subject\n"
                .. "· Notecards — flashcard review\n"
                .. "· Settings — customize everything\n\n"
                .. "Tap any tile to get started.\n"
                .. "You can hide or rearrange tiles in Settings."),
        })
    end)
end

function CozyHomeScreen:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function CozyHomeScreen:onCloseWidget()
    -- Free the cached cover blitbuffer to avoid memory leaks
    if self._cover_bb and self._cover_bb.free then
        self._cover_bb:free()
        self._cover_bb = nil
    end
    Home._current_instance = nil
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function CozyHomeScreen:onClose()
    UIManager:close(self)
    return true
end

-- ─── Continue Reading Data ───

function CozyHomeScreen:getLastBookInfo()
    local result = {
        has_book = false, title = "", path = "",
        progress_text = "", author = "",
    }
    local hist = ReadHistory.hist
    if not hist or #hist == 0 then return result end

    local entry = nil
    for _, h in ipairs(hist) do
        if not h.dim then entry = h; break end
    end
    if not entry then return result end

    result.has_book = true
    result.path = entry.file
    local filename = entry.file:match("([^/]+)$") or "Unknown"
    result.title = filename:gsub("%.%w+$", "")

    local ok, doc_settings = pcall(DocSettings.open, DocSettings, entry.file)
    if ok and doc_settings then
        local doc_props = doc_settings:readSetting("doc_props")
        if doc_props then
            if doc_props.title and doc_props.title ~= "" then
                result.title = doc_props.title
            end
            if doc_props.authors and doc_props.authors ~= "" then
                result.author = doc_props.authors
            end
        end
        local percent_finished = doc_settings:readSetting("percent_finished")
        if percent_finished then
            result.progress_text = math.floor(percent_finished * 100) .. "%"
        end
        if result.progress_text == "" then
            local page = doc_settings:readSetting("last_page")
            local pages = doc_settings:readSetting("doc_pages")
            if page and pages and pages > 0 then
                result.progress_text = math.floor(page / pages * 100) .. "%"
            end
        end
    end
    if result.progress_text == "" then result.progress_text = "..." end
    return result
end

-- ─── Cover Loading ───

--- Try to get a cover Blitbuffer for a book path.
-- Strategy:
--   1. Try BookInfoManager (works with CoverBrowser OR ProjectTitle — instant, from SQLite cache)
--   2. Fall back to DocumentRegistry:openDocument → getCoverPageImage (slower, parses the file)
-- Returns a Blitbuffer on success, or nil if no cover found.
function CozyHomeScreen:getCoverBB(filepath)
    -- Return cached result if we already looked this up
    if self._cover_bb ~= nil then
        if self._cover_bb == false then return nil end
        return self._cover_bb
    end

    local cover_bb = nil

    -- Tier 1: Try BookInfoManager cache (fast — works with ProjectTitle or CoverBrowser)
    local bim_ok, BookInfoManager = pcall(require, "bookinfomanager")
    if bim_ok and BookInfoManager then
        if not BookInfoManager.db_created and BookInfoManager.init then
            pcall(BookInfoManager.init, BookInfoManager)
        end
        local info_ok, bookinfo = pcall(
            BookInfoManager.getBookInfo, BookInfoManager, filepath, true -- true = get_cover
        )
        if info_ok and bookinfo and bookinfo.cover_bb then
            cover_bb = bookinfo.cover_bb
        end
    end

    -- Tier 2: Open the document directly and extract cover (slower fallback)
    if not cover_bb then
        local DocumentRegistry = require("document/documentregistry")
        if DocumentRegistry:hasProvider(filepath) then
            local ok, doc = pcall(DocumentRegistry.openDocument, DocumentRegistry, filepath)
            if ok and doc then
                local cover_ok, bb = pcall(doc.getCoverPageImage, doc)
                if cover_ok and bb then
                    cover_bb = bb
                end
                doc:close()
            end
        end
    end

    -- Cache: false means "no cover" vs nil meaning "not yet looked up"
    self._cover_bb = cover_bb or false
    return cover_bb
end

-- ─── UI Building ───

function CozyHomeScreen:getVisibleTiles()
    local visible = {}
    for _, tile in ipairs(Config.TILES) do
        local pref_val = Database:getPref("tile_visible_" .. tile.key, "true")
        local is_visible = (pref_val ~= "false")
        if tile.key == "notebooks" and is_visible then
            local has_stylus = Device.hasStylus and Device:hasStylus()
            if not has_stylus then
                local override = Database:getPref("notebooks_force_show", "false")
                if override ~= "true" then is_visible = false end
            end
        end
        if is_visible then table.insert(visible, tile) end
    end
    return visible
end

function CozyHomeScreen:calcGridLayout(tile_count)
    if tile_count <= 0 then return 1, 1 end
    if tile_count <= 2 then return tile_count, 1 end
    if tile_count <= 4 then return 2, 2 end
    if tile_count <= 6 then return 3, 2 end
    if tile_count <= 9 then return 3, 3 end
    return 3, math.ceil(tile_count / 3)
end

function CozyHomeScreen:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local home_screen = self
    local items = {}

    -- ── Status bar ──
    local show_wifi = Database:getPref("statusbar_show_wifi", "false") == "true"
    local show_bt = Database:getPref("statusbar_show_bluetooth", "false") == "true"
    table.insert(items, StatusBar:new{
        width = sw, show_wifi = show_wifi, show_bluetooth = show_bt,
    })

    -- ── Header ──
    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Cozy Home",
        back_callback = function() home_screen:onClose() end,
        exit_callback = function() home_screen:onClose() end,
        show_parent = self,
    }))
    table.insert(items, CozyUI.buildDottedDivider(sw, content_w))
    table.insert(items, sp(8))

    -- ── Continue Reading Card (with cover) ──
    local book_info = self._cached_book_info or self:getLastBookInfo()

    if book_info.has_book then
        local cover_h = math.floor(sh * 0.16)  -- cover thumbnail height
        local cover_w = math.floor(cover_h * 0.667)  -- ~2:3 book aspect ratio
        local text_w = content_w - cover_w - 14 - 28  -- 14 gap + card padding

        -- Try to load the real cover image
        local cover_bb = self:getCoverBB(book_info.path)
        local cover_widget

        if cover_bb then
            -- Real cover image
            local img = ImageWidget:new{
                image = cover_bb,
                width = cover_w - 4,
                height = cover_h - 4,
                scale_factor = 0,
                autostretch = true,
            }
            cover_widget = FrameContainer:new{
                dimen = Geom:new{w = cover_w, h = cover_h},
                bordersize = 1,
                padding = 1,
                color = GRAY,
                background = WHITE,
                CenterContainer:new{
                    dimen = Geom:new{w = cover_w - 4, h = cover_h - 4},
                    img,
                },
            }
        else
            -- Fallback: styled placeholder with first letter
            local first_letter = (book_info.title:sub(1, 1) or "?"):upper()
            local letter_size = math.max(14, math.floor(cover_h * 0.3))
            cover_widget = FrameContainer:new{
                dimen = Geom:new{w = cover_w, h = cover_h},
                bordersize = 1,
                padding = 2,
                color = GRAY,
                background = DARK_GRAY,
                CenterContainer:new{
                    dimen = Geom:new{w = cover_w - 6, h = cover_h - 6},
                    TextWidget:new{
                        face = Font:getFace("tfont", letter_size),
                        text = first_letter,
                        fgcolor = WHITE,
                    },
                },
            }
        end

        -- Text column: label, title, author, progress
        local title_display = CozyUI.truncateText(book_info.title, 36)
        local detail_parts = {}
        if book_info.author ~= "" then
            table.insert(detail_parts, CozyUI.truncateText(book_info.author, 28))
        end
        table.insert(detail_parts, book_info.progress_text)

        local text_column = VerticalGroup:new{
            align = "left",
            TextWidget:new{
                face = Font:getFace("smallinfofont"),
                text = _("Continue Reading"),
                fgcolor = GRAY,
            },
            sp(6),
            TextWidget:new{
                face = Font:getFace("tfont", 18),
                text = title_display,
                fgcolor = BLACK,
                max_width = text_w,
            },
            sp(4),
            TextWidget:new{
                face = Font:getFace("cfont", 14),
                text = table.concat(detail_parts, "  ·  "),
                fgcolor = DARK_GRAY,
                max_width = text_w,
            },
        }

        -- Horizontal layout: cover | gap | text
        local card_inner = HorizontalGroup:new{
            align = "center",
            cover_widget,
            HorizontalSpan:new{width = 14},
            CenterContainer:new{
                dimen = Geom:new{w = text_w, h = cover_h},
                LeftContainer:new{
                    dimen = Geom:new{w = text_w, h = cover_h},
                    text_column,
                },
            },
        }

        local card = CozyUI.buildRoundedBox(card_inner)
        local GestureRange = require("ui/gesturerange")

        local TappableCard = InputContainer:extend{}
        function TappableCard:init()
            self.dimen = Geom:new{w = content_w, h = card:getSize().h}
            self.ges_events = {
                TapContinue = {
                    GestureRange:new{ ges = "tap", range = self.dimen },
                },
            }
            self[1] = card
        end
        function TappableCard:onTapContinue()
            home_screen:closeAndRun(function()
                local ReaderUI = require("apps/reader/readerui")
                ReaderUI:showReader(book_info.path)
            end)
            return true
        end

        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = card:getSize().h},
            TappableCard:new{},
        })
    else
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = 40},
            TextWidget:new{
                face = Font:getFace("cfont", 14),
                text = _("No recent book · open one to get started"),
                fgcolor = GRAY,
            },
        })
    end

    -- ── History shortcut ──
    table.insert(items, sp(4))
    local history_btn = Button:new{
        text = _("History ▸"),
        callback = function()
            home_screen:closeAndRun(function()
                History.show(home_screen.ui, function()
                    Home.show(home_screen.ui, home_screen.on_close_callback)
                end)
            end)
        end,
        bordersize = 0, text_font_size = 14, padding = 4,
        show_parent = self,
    }
    table.insert(items, RightContainer:new{
        dimen = Geom:new{w = sw - math.floor((sw - content_w) / 2), h = history_btn:getSize().h},
        history_btn,
    })

    -- ── Tile section divider ──
    table.insert(items, sp(8))
    table.insert(items, CozyUI.buildSectionDivider(sw, content_w, "Navigate"))
    table.insert(items, sp(8))

    -- ── Navigation Tiles ──
    local visible_tiles = self:getVisibleTiles()
    local grid_cols, grid_rows = self:calcGridLayout(#visible_tiles)
    local tile_margin = Config.UI.tile_margin
    local tile_w = math.floor(content_w / grid_cols) - tile_margin * 2
    local tile_h = math.floor(sh * Config.UI.tile_height_fraction)

    local tile_callbacks = self:getTileCallbacks()
    local GestureRange = require("ui/gesturerange")
    local tile_idx = 1

    for row = 1, grid_rows do
        local row_group = HorizontalGroup:new{ align = "center" }
        local cols_this_row = math.min(grid_cols, #visible_tiles - tile_idx + 1)

        for col = 1, cols_this_row do
            if tile_idx > #visible_tiles then break end
            local tile = visible_tiles[tile_idx]
            tile_idx = tile_idx + 1

            local tile_content = VerticalGroup:new{
                align = "center",
                sp(8),
                TextWidget:new{
                    face = Font:getFace("tfont", Config.UI.font_size_tile_icon),
                    text = tile.icon_text, fgcolor = BLACK,
                },
                sp(4),
                TextWidget:new{
                    face = Font:getFace("cfont", Config.UI.font_size_tile_label),
                    text = tile.label, fgcolor = BLACK,
                },
                sp(8),
            }

            local tile_frame = FrameContainer:new{
                dimen = Geom:new{w = tile_w, h = tile_h},
                bordersize = 1,
                radius = 10,
                padding = 4,
                color = GRAY,
                background = WHITE,
                CenterContainer:new{
                    dimen = Geom:new{w = tile_w - 10, h = tile_h - 10},
                    tile_content,
                },
            }

            local tile_key = tile.key
            local TappableTile = InputContainer:extend{}
            function TappableTile:init()
                self.dimen = Geom:new{w = tile_w, h = tile_h}
                self.ges_events = {
                    TapTile = {
                        GestureRange:new{ ges = "tap", range = self.dimen },
                    },
                }
                self[1] = tile_frame
            end
            local cb = tile_callbacks[tile_key]
            TappableTile.onTapTile = function()
                if cb then cb() end
                return true
            end

            if col > 1 then
                table.insert(row_group, HorizontalSpan:new{width = tile_margin * 2})
            end
            table.insert(row_group, TappableTile:new{})
        end

        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = tile_h},
            row_group,
        })
        if row < grid_rows then
            table.insert(items, sp(tile_margin * 2))
        end
    end

    table.insert(items, sp(12))

    -- ── Stats bar ──
    local show_stats = Database:getPref("home_show_stats_bar", "true") == "true"
    if show_stats then
        local stats_text = self._cached_stats_text or self:computeStatsText()
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = 18},
            TextWidget:new{
                face = Font:getFace("smallinfofont", 12),
                text = stats_text,
                fgcolor = GRAY,
            },
        })
        table.insert(items, sp(4))
    end

    table.insert(items, sp(2))
    table.insert(items, CozyUI.buildFooter(sw, "₊ ⊹ ♡ ⋆ ☆ ⋆ ♡ ⋆ ☆ ⋆ ♡ ⊹ ₊"))

    -- ── Assemble ──
    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do
        table.insert(content, item)
    end

    -- Wrap in ScrollableContainer so content is never clipped
    -- on smaller screens or when many tiles are visible
    local scrollable = ScrollableContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        show_parent = self,
        content,
    }

    self[1] = FrameContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        bordersize = 0, padding = 0,
        background = WHITE,
        scrollable,
    }
end

-- ─── Tile callbacks ───

function CozyHomeScreen:getTileCallbacks()
    local home_screen = self
    local function nav(module, reopen)
        return function()
            home_screen:closeAndRun(function()
                module.show(home_screen.ui, function()
                    Home.show(home_screen.ui, home_screen.on_close_callback)
                end)
            end)
        end
    end
    return {
        books      = nav(Library),
        highlights = nav(HighlightsScreen),
        notebooks  = nav(Notebooks),
        learnspace = nav(LearningSpace),
        notecards  = nav(Notecards),
        focus      = nav(FocusMode),
        settings   = nav(Settings),
        koreader_settings = function()
            -- Close Cozy Home, then open KOReader's built-in menu
            home_screen:closeAndRun(function()
                -- Trigger the same menu that tapping the top of screen opens
                if home_screen.ui and home_screen.ui.menu then
                    home_screen.ui.menu:onTapShowMenu()
                end
            end)
        end,
    }
end

-- ─── Stats ───

function CozyHomeScreen:computeStatsText()
    local books_in_progress = 0
    pcall(function() ReadHistory:ensureRecent() end)
    local hist = ReadHistory.hist or {}
    local counted = 0
    for _, entry in ipairs(hist) do
        if not entry.dim and counted < 20 then
            counted = counted + 1
            local ok, ds = pcall(DocSettings.open, DocSettings, entry.file)
            if ok and ds then
                local pct = ds:readSetting("percent_finished")
                if pct and pct < 1.0 and pct > 0 then
                    books_in_progress = books_in_progress + 1
                end
            end
        end
    end

    -- Count highlights from recent books
    local highlight_count = 0
    pcall(function()
        local HLLib = require("lib/highlights")
        local counted_hl = 0
        for _, entry in ipairs(hist) do
            if not entry.dim and counted_hl < 10 then
                counted_hl = counted_hl + 1
                local c = HLLib.getHighlightCount(entry.file)
                highlight_count = highlight_count + c
            end
        end
    end)

    local parts = {}
    if books_in_progress > 0 then
        table.insert(parts, books_in_progress .. " books in progress")
    end
    if highlight_count > 0 then
        table.insert(parts, highlight_count .. " highlights")
    end

    local fc_due = 0
    pcall(function()
        local fc_ok, CozyFlashcards = pcall(require, "cozyflashcards/main")
        if fc_ok and CozyFlashcards and CozyFlashcards.getDueCounts then
            local counts = CozyFlashcards:getDueCounts()
            if counts and counts.due_today then fc_due = counts.due_today end
        end
    end)
    if fc_due > 0 then
        table.insert(parts, fc_due .. " cards due")
    end

    -- Focus mode status
    pcall(function()
        local focus_stat = FocusMode.getStatsForHome()
        if focus_stat then
            table.insert(parts, focus_stat)
        end
    end)

    if #parts == 0 then return _("Welcome to Cozy Home") end
    return table.concat(parts, "  ·  ")
end

-- ─── Helpers ───

function CozyHomeScreen:closeAndRun(callback)
    UIManager:close(self)
    if callback then UIManager:nextTick(callback) end
end

function CozyHomeScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end

-- ─── Public API ───

function Home.show(ui, on_close_callback)
    if Home._current_instance then
        UIManager:close(Home._current_instance)
        Home._current_instance = nil
    end
    local screen = CozyHomeScreen:new{
        ui = ui, on_close_callback = on_close_callback,
    }
    UIManager:show(screen)
end

function Home.isOpen() return Home._current_instance ~= nil end

function Home.close()
    if Home._current_instance then
        UIManager:close(Home._current_instance)
        Home._current_instance = nil
    end
end

return Home
