-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         highlights.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-08
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Full-screen highlights browser. Browse, search,
--       filter, and navigate highlights from one book or
--       all books. Styled to match the Notecards UI.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - lib/cozyui.lua
--       - lib/highlights.lua
--       - lib/kobo.lua
--       - highlight_bridge.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
-- Public API:
--   Highlights.show(ui, on_close_callback)
--   Highlights.showForCurrentBook(ui)
--   Highlights.showForAllBooks(ui, on_close_callback)
--
-- Version: 0.12.0

local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local InputDialog = require("ui/widget/inputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Event = require("ui/event")
local logger = require("logger")
local _ = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local DocSettings = require("docsettings")
local DataStorage = require("datastorage")
local ReadHistory = require("readhistory")

-- KOReader widget imports
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Button = require("ui/widget/button")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local GestureRange = require("ui/gesturerange")

-- Our modules
local HL = require("lib/highlights")
local Config = require("config")
local CozyUI = require("lib/cozyui")

-- Kobo native DB (optional)
local Kobo = nil
local kobo_available = false
pcall(function()
    Kobo = require("lib/kobo")
    kobo_available = Kobo.isAvailable()
end)

-- Cozy Flashcards integration (optional)
local HighlightBridge = nil
local bridge_available = false
pcall(function()
    HighlightBridge = require("highlight_bridge")
    bridge_available = true
end)

-- ─── Design system shorthand ───

local BLACK      = CozyUI.BLACK
local DARK_GRAY  = CozyUI.DARK_GRAY
local GRAY       = CozyUI.GRAY
local LIGHT_GRAY = CozyUI.LIGHT_GRAY
local WHITE      = CozyUI.WHITE
local sp         = CozyUI.sp

-- ─── Constants ───

local ITEMS_PER_PAGE = nil  -- calculated dynamically in buildUI
local MAX_TEXT_LEN   = 120
local MAX_TITLE_LEN  = 30
local MAX_NOTE_LEN   = 60

local SRC_KO   = "koreader"
local SRC_KOBO = "kobo"

-- ─── Supported extensions ───

local BOOK_EXTS = {
    ".epub", ".kepub.epub", ".pdf", ".mobi",
    ".azw3", ".fb2", ".txt", ".rtf",
    ".html", ".htm", ".cbz", ".cbr",
}

local SKIP_DIRS = {
    [".kobo"] = true, [".adobe-digital-editions"] = true,
    [".sdr"] = true, [".adds"] = true, ["koreader"] = true,
}

-- ============================================
-- HELPERS
-- ============================================

local function truncate(text, max)
    if not text then return "" end
    text = text:gsub("\n", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or text
    if #text <= max then return text end
    return text:sub(1, max - 3) .. "..."
end

local function hlKey(hl)
    local t = (hl.text or ""):sub(1, 100):lower():gsub("%s+", " ")
    local p = tostring(hl.pageno or hl.progress_percent or "")
    return t .. "|" .. p
end

local function isBookFile(name)
    if not name then return false end
    local low = name:lower()
    for _, ext in ipairs(BOOK_EXTS) do
        if low:sub(-#ext) == ext then return true end
    end
    return false
end

local function scanDir(dir, results, depth, max_depth)
    depth = depth or 0
    max_depth = max_depth or 6
    if depth > max_depth then return end
    local ok, iter, obj = pcall(lfs.dir, dir)
    if not ok then return end
    for file in iter, obj do
        if file ~= "." and file ~= ".." and not file:match("^%.") then
            local path = dir .. "/" .. file
            local attr = lfs.attributes(path)
            if attr then
                if attr.mode == "directory" and not SKIP_DIRS[file] then
                    scanDir(path, results, depth + 1, max_depth)
                elseif attr.mode == "file" and isBookFile(file) then
                    local sdr = DocSettings:getSidecarDir(path)
                    local sdr_attr = lfs.attributes(sdr)
                    if sdr_attr and sdr_attr.mode == "directory" then
                        table.insert(results, { path = path, filename = file })
                    end
                end
            end
        end
    end
end

local function getScanPaths()
    local paths = {}
    local data_dir = DataStorage:getFullDataDir()
    if data_dir then table.insert(paths, data_dir) end
    table.insert(paths, "/mnt/onboard")
    table.insert(paths, "./books")
    table.insert(paths, "books")
    return paths
end

local function mergeHighlights(ko_hl, kobo_hl)
    local merged, seen = {}, {}
    for _, hl in ipairs(ko_hl or {}) do
        hl.source = SRC_KO
        local k = hlKey(hl)
        if not seen[k] then seen[k] = true; table.insert(merged, hl) end
    end
    for _, hl in ipairs(kobo_hl or {}) do
        hl.source = SRC_KOBO
        local k = hlKey(hl)
        if not seen[k] then seen[k] = true; table.insert(merged, hl) end
    end
    table.sort(merged, function(a, b)
        local pa = a.pageno or (a.progress_percent and a.progress_percent * 1000) or 0
        local pb = b.pageno or (b.progress_percent and b.progress_percent * 1000) or 0
        return pa < pb
    end)
    return merged
end

local function findAllBooksWithHighlights()
    local books, seen = {}, {}

    pcall(function()
        local hist = ReadHistory.hist or {}
        for _, entry in ipairs(hist) do
            if entry.file and not entry.dim and not seen[entry.file] then
                seen[entry.file] = true
                local hls = HL.getHighlights(entry.file) or {}
                if #hls > 0 then
                    local filename = entry.file:match("([^/]+)$") or "Unknown"
                    local title = filename:match("^(.+)%.[^%.]+$") or filename
                    title = title:gsub("%.kepub$", "")
                    table.insert(books, {
                        path = entry.file, filename = filename,
                        title = title, highlight_count = #hls, source = SRC_KO,
                    })
                end
            end
        end
    end)

    local found = {}
    local scanned = {}
    for _, sp_path in ipairs(getScanPaths()) do
        if sp_path and not scanned[sp_path] then
            scanned[sp_path] = true
            scanDir(sp_path, found)
        end
    end

    for _, bk in ipairs(found) do
        if not seen[bk.path] then
            seen[bk.path] = true
            local hls = HL.getHighlights(bk.path) or {}
            if #hls > 0 then
                local title = bk.filename:match("^(.+)%.[^%.]+$") or bk.filename
                title = title:gsub("%.kepub$", "")
                table.insert(books, {
                    path = bk.path, filename = bk.filename,
                    title = title, highlight_count = #hls, source = SRC_KO,
                })
            end
        end
    end

    if kobo_available and Kobo then
        local kobo_books = Kobo.getAllBooksWithHighlights() or {}
        for _, bk in ipairs(kobo_books) do
            if bk.path and not seen[bk.path] then
                seen[bk.path] = true
                local title = (bk.filename or ""):match("^(.+)%.[^%.]+$") or bk.filename or "Unknown"
                title = title:gsub("%.kepub$", "")
                table.insert(books, {
                    path = bk.path, filename = bk.filename,
                    title = title, highlight_count = bk.highlight_count or 0,
                    source = SRC_KOBO,
                })
            end
        end
    end

    table.sort(books, function(a, b)
        return (a.highlight_count or 0) > (b.highlight_count or 0)
    end)
    return books
end

-- ─── Status icon for highlight source ───

local function sourceIcon(hl)
    if hl.note and hl.note ~= "" then return "✦" end
    if hl.source == SRC_KOBO then return "✧" end
    return "✦"
end

-- ============================================
-- HIGHLIGHT DETAIL SCREEN (full-screen)
-- ============================================

local HighlightDetailScreen = InputContainer:extend{
    name = "cozy_highlight_detail",
    covers_fullscreen = true,
}

function HighlightDetailScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:buildUI()
end

function HighlightDetailScreen:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local hl = self.highlight
    local screen = self
    local items = {}

    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Highlight Details",
        back_callback = function() screen:onClose() end,
        exit_callback = function() screen:onClose() end,
        show_parent = self,
    }))
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 2 },
        LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
    })
    table.insert(items, sp(12))

    -- Book title
    if hl.book_title then
        table.insert(items, CozyUI.buildStatRow(sw, content_w, "Book", truncate(hl.book_title, 40)))
        table.insert(items, sp(4))
    end

    -- Source
    local source_text = hl.source == SRC_KOBO and "Kobo Native" or "KOReader"
    table.insert(items, CozyUI.buildStatRow(sw, content_w, "Source", source_text))
    table.insert(items, sp(4))

    if hl.pageno then
        table.insert(items, CozyUI.buildStatRow(sw, content_w, "Page", tostring(hl.pageno)))
        table.insert(items, sp(4))
    end
    if hl.progress_percent then
        table.insert(items, CozyUI.buildStatRow(sw, content_w, "Progress", hl.progress_percent .. "%"))
        table.insert(items, sp(4))
    end
    if hl.chapter and hl.chapter ~= "" then
        table.insert(items, CozyUI.buildStatRow(sw, content_w, "Chapter", truncate(hl.chapter, 35)))
        table.insert(items, sp(4))
    end
    if hl.datetime then
        table.insert(items, CozyUI.buildStatRow(sw, content_w, "Created", hl.datetime))
        table.insert(items, sp(4))
    end

    -- Highlight text
    table.insert(items, sp(8))
    table.insert(items, CozyUI.buildSectionDivider(sw, content_w, "Highlighted Text"))
    table.insert(items, sp(8))

    local text_display = hl.text or "[No text]"
    local text_box = TextBoxWidget:new{
        face = Font:getFace("cfont", 16),
        text = text_display,
        width = content_w - 28,
        fgcolor = BLACK,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = text_box:getSize().h + 28},
        CozyUI.buildRoundedBox(text_box),
    })

    -- Note section
    if hl.note and hl.note ~= "" then
        table.insert(items, sp(8))
        table.insert(items, CozyUI.buildSectionDivider(sw, content_w, "Your Note"))
        table.insert(items, sp(8))
        local note_box = TextBoxWidget:new{
            face = Font:getFace("cfont", 16),
            text = hl.note,
            width = content_w - 28,
            fgcolor = DARK_GRAY,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = note_box:getSize().h + 28},
            CozyUI.buildRoundedBox(note_box),
        })
    end

    table.insert(items, sp(16))
    table.insert(items, CozyUI.buildPrimaryButton(content_w, "Back to Highlights", function()
        screen:onClose()
    end, self))
    table.insert(items, sp(12))
    table.insert(items, CozyUI.buildFooter(sw, "₊ ⊹ ♡ ⋆ ☆ ⋆ ♡ ⋆ ☆ ⋆ ♡ ⊹ ₊"))

    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do table.insert(content, item) end

    local scroll_container = ScrollableContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        show_parent = self,
        content,
    }

    self[1] = FrameContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        bordersize = 0, padding = 0,
        background = WHITE,
        scroll_container,
    }
end

function HighlightDetailScreen:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function HighlightDetailScreen:onCloseWidget()
    UIManager:setDirty(nil, function() return "full", self.dimen end)
end

function HighlightDetailScreen:onClose()
    UIManager:close(self)
    if self.on_close then
        local cb = self.on_close
        UIManager:nextTick(function() cb() end)
    end
    return true
end

function HighlightDetailScreen:paintTo(bb, x, y)
    self.dimen.x = x; self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end


-- ============================================
-- HIGHLIGHT ACTION SCREEN (full-screen)
-- ============================================

local HighlightActionScreen = InputContainer:extend{
    name = "cozy_highlight_action",
    covers_fullscreen = true,
}

function HighlightActionScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:buildUI()
end

function HighlightActionScreen:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local btn_w = math.floor(content_w * 0.92)
    local hl = self.highlight
    local viewer = self.viewer
    local screen = self
    local items = {}

    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Highlight",
        back_callback = function() screen:onClose() end,
        exit_callback = function() screen:onClose() end,
        show_parent = self,
    }))
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 2 },
        LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
    })
    table.insert(items, sp(12))

    -- Book title (for all-books mode)
    if viewer.all_books and hl.book_title then
        local book_label = TextWidget:new{
            face = Font:getFace("smallinfofont"),
            text = truncate(hl.book_title, 45),
            fgcolor = GRAY,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = book_label:getSize().h},
            book_label,
        })
        table.insert(items, sp(6))
    end

    -- Source and location info
    local source_text = hl.source == SRC_KOBO and "Kobo" or "KOReader"
    local loc_parts = { source_text }
    if hl.pageno then table.insert(loc_parts, "p." .. hl.pageno) end
    if hl.progress_percent then table.insert(loc_parts, hl.progress_percent .. "%") end
    if hl.chapter and hl.chapter ~= "" then
        table.insert(loc_parts, truncate(hl.chapter, 25))
    end
    local info_label = TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = table.concat(loc_parts, "  ·  "),
        fgcolor = DARK_GRAY,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = info_label:getSize().h},
        info_label,
    })
    table.insert(items, sp(10))

    -- Highlight text in a rounded box
    local text_display = hl.text or "[No text]"
    if #text_display > 500 then text_display = text_display:sub(1, 497) .. "..." end
    local text_box = TextBoxWidget:new{
        face = Font:getFace("cfont", 16),
        text = text_display,
        width = content_w - 28,
        fgcolor = BLACK,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = text_box:getSize().h + 28},
        CozyUI.buildRoundedBox(text_box),
    })

    -- Note indicator
    if hl.note and hl.note ~= "" then
        table.insert(items, sp(6))
        local note_preview = TextWidget:new{
            face = Font:getFace("smallinfofont"),
            text = "📝 Note: " .. truncate(hl.note, 50),
            fgcolor = DARK_GRAY,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = note_preview:getSize().h},
            note_preview,
        })
    end

    -- Action buttons
    table.insert(items, sp(16))
    table.insert(items, CozyUI.buildSectionDivider(sw, content_w, "Actions"))
    table.insert(items, sp(12))

    -- Jump to Location
    local jump_label = hl.source == SRC_KOBO
        and "Jump to Location (Kobo)" or "Jump to Location"
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = 48},
        Button:new{
            text = _(jump_label),
            callback = function()
                UIManager:close(screen)
                if hl.source == SRC_KOBO then viewer:jumpKobo(hl)
                else viewer:jumpKO(hl) end
            end,
            width = btn_w, bordersize = 2, radius = 8,
            text_font_bold = true, padding_v = 10, show_parent = self,
        },
    })
    table.insert(items, sp(8))

    -- View Details
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = 48},
        Button:new{
            text = _("View Details"),
            callback = function()
                screen._navigating_forward = true
                UIManager:close(screen)
                local detail = HighlightDetailScreen:new{
                    highlight = hl,
                    on_close = function() viewer:reopen() end,
                }
                UIManager:show(detail)
            end,
            width = btn_w, bordersize = 1, radius = 8, padding_v = 10, show_parent = self,
        },
    })
    table.insert(items, sp(8))

    -- Create Flashcard
    if bridge_available and HighlightBridge then
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = 48},
            Button:new{
                text = _("Create Flashcard"),
                callback = function()
                    screen._navigating_forward = true
                    UIManager:close(screen)
                    local book_info = viewer:bookInfoFor(hl)
                    HighlightBridge.createCardFromHighlight({
                        text = hl.text or "",
                        book_path = book_info and book_info.path,
                        book_title = book_info and book_info.title,
                        page = hl.pageno or hl.page,
                        chapter = hl.chapter,
                    })
                end,
                width = btn_w, bordersize = 1, radius = 8, padding_v = 10, show_parent = self,
            },
        })
        table.insert(items, sp(8))
    end

    -- View Note
    if hl.note and hl.note ~= "" then
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = 48},
            Button:new{
                text = _("View Full Note"),
                callback = function()
                    UIManager:close(screen)
                    viewer:showNote(hl)
                end,
                width = btn_w, bordersize = 1, radius = 8, padding_v = 10, show_parent = self,
            },
        })
        table.insert(items, sp(8))
    end

    table.insert(items, sp(8))
    table.insert(items, CozyUI.buildFooter(sw, "₊ ⊹ ♡ ⋆ ☆ ⋆ ♡ ⋆ ☆ ⋆ ♡ ⊹ ₊"))

    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do table.insert(content, item) end

    local scroll_container = ScrollableContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        show_parent = self,
        content,
    }

    self[1] = FrameContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        bordersize = 0, padding = 0,
        background = WHITE,
        scroll_container,
    }
end

function HighlightActionScreen:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function HighlightActionScreen:onCloseWidget()
    UIManager:setDirty(nil, function() return "full", self.dimen end)
end

function HighlightActionScreen:onClose()
    UIManager:close(self)
    if not self._navigating_forward and self.on_close then
        local cb = self.on_close
        UIManager:nextTick(function() cb() end)
    end
    self._navigating_forward = false
    return true
end

function HighlightActionScreen:paintTo(bb, x, y)
    self.dimen.x = x; self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end


-- ============================================
-- HIGHLIGHTS HUB SCREEN (full-screen)
-- ============================================
-- Replaces the old Menu-based viewer with a full-screen
-- InputContainer styled like the Notecards hub.

local HighlightsHub = InputContainer:extend{
    name = "cozy_highlights_hub",
    covers_fullscreen = true,
    -- Data
    ui = nil,
    on_close_callback = nil,
    all_books = true,
    book_path = nil,
    highlights = {},
    books = {},
    ko_count = 0,
    kobo_count = 0,
    filtered = {},
    -- Filters
    filter = nil,          -- chapter (single book) or book_path (all books)
    filter_label = nil,
    source_filter = nil,
    search = nil,
    -- Pagination
    current_page = 1,
}

function HighlightsHub:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self:buildUI()
end

function HighlightsHub:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function HighlightsHub:onCloseWidget()
    UIManager:setDirty(nil, function() return "full", self.dimen end)
end

function HighlightsHub:onClose()
    UIManager:close(self)
    if self.on_close_callback then
        UIManager:nextTick(self.on_close_callback)
    end
    return true
end

function HighlightsHub:paintTo(bb, x, y)
    self.dimen.x = x; self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end

-- ─── Data loading ───

function HighlightsHub:loadSingle()
    local ko = HL.getHighlights(self.book_path) or {}
    self.ko_count = #ko
    local kobo = {}
    if kobo_available and Kobo then
        kobo = Kobo.getBookHighlights(self.book_path) or {}
        self.kobo_count = #kobo
    end
    self.highlights = mergeHighlights(ko, kobo)
    self.filtered = self.highlights
end

function HighlightsHub:loadAll()
    self.books = findAllBooksWithHighlights()
    self.highlights = {}
    self.ko_count = 0
    self.kobo_count = 0

    for _, bk in ipairs(self.books) do
        local ko = HL.getHighlights(bk.path) or {}
        for _, hl in ipairs(ko) do
            hl.book_path = bk.path
            hl.book_title = bk.title
            hl.source = SRC_KO
            table.insert(self.highlights, hl)
        end
        self.ko_count = self.ko_count + #ko

        if kobo_available and Kobo then
            local kobo = Kobo.getBookHighlights(bk.path) or {}
            local seen = {}
            for _, existing in ipairs(self.highlights) do
                if existing.book_path == bk.path then
                    seen[hlKey(existing)] = true
                end
            end
            for _, hl in ipairs(kobo) do
                if not seen[hlKey(hl)] then
                    hl.book_path = bk.path
                    hl.book_title = bk.title
                    hl.source = SRC_KOBO
                    table.insert(self.highlights, hl)
                    self.kobo_count = self.kobo_count + 1
                end
            end
        end
    end
    self.filtered = self.highlights
end

-- ─── Filtering ───

function HighlightsHub:applyFilters()
    local result = self.highlights

    if self.source_filter then
        local f = {}
        for _, hl in ipairs(result) do
            if hl.source == self.source_filter then table.insert(f, hl) end
        end
        result = f
    end

    if self.filter then
        local f = {}
        for _, hl in ipairs(result) do
            if self.all_books then
                if hl.book_path == self.filter then table.insert(f, hl) end
            else
                if hl.chapter == self.filter then table.insert(f, hl) end
            end
        end
        result = f
    end

    if self.search and self.search ~= "" then
        local q = self.search:lower()
        local f = {}
        for _, hl in ipairs(result) do
            local match = false
            if hl.text and hl.text:lower():find(q, 1, true) then match = true end
            if hl.note and hl.note:lower():find(q, 1, true) then match = true end
            if self.all_books and hl.book_title and hl.book_title:lower():find(q, 1, true) then match = true end
            if match then table.insert(f, hl) end
        end
        result = f
    end

    self.filtered = result
    self.current_page = 1
end

-- ─── Build UI ───

function HighlightsHub:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local pad = Config.UI.content_padding
    local content_w = sw - pad * 2
    local hub = self
    local items = {}

    -- ── HEADER ──
    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Highlights",
        back_callback = function() hub:onClose() end,
        exit_callback = function() hub:onClose() end,
        show_parent = self,
    }))
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 2 },
        LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
    })
    table.insert(items, sp(6))

    -- ── SUMMARY LINE (small, subtle) ──
    local summary_parts = {}
    table.insert(summary_parts, #self.filtered .. " highlights")
    if self.all_books and #self.books > 0 then
        table.insert(summary_parts, #self.books .. " books")
    end
    if self.ko_count > 0 and self.kobo_count > 0 then
        table.insert(summary_parts, "KO:" .. self.ko_count .. " Kobo:" .. self.kobo_count)
    end
    local summary_w = TextWidget:new{
        face = Font:getFace("smallinfofont", 12),
        text = table.concat(summary_parts, "  ·  "),
        fgcolor = GRAY,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = summary_w:getSize().h + 2},
        summary_w,
    })
    table.insert(items, sp(2))

    -- ── FILTER/SEARCH BAR ──
    local filter_label_text = "All"
    if self.filter_label then filter_label_text = self.filter_label end
    if self.source_filter then
        filter_label_text = filter_label_text .. " · " .. self.source_filter
    end
    if #filter_label_text > 18 then filter_label_text = filter_label_text:sub(1, 15) .. "..." end

    local filter_btn = Button:new{
        text = _("Filter: ") .. filter_label_text,
        callback = function() hub:showFilterMenu() end,
        bordersize = 0, text_font_size = 14, padding = 4, show_parent = self,
    }
    local search_btn = Button:new{
        text = self.search and _("Search ✓") or _("Search"),
        callback = function() hub:showSearchDialog() end,
        bordersize = 0, text_font_size = 14, padding = 4, show_parent = self,
    }

    -- Build the toolbar row: Filter, Search, and optionally Batch Flashcards
    local toolbar_children = {
        filter_btn,
        HorizontalSpan:new{ width = 12 },
        search_btn,
    }
    if bridge_available and HighlightBridge and #self.filtered > 0 then
        local batch_btn = Button:new{
            text = _("+ Cards"),
            callback = function() hub:showBatchCreate() end,
            bordersize = 0, text_font_size = 14, padding = 4, show_parent = self,
        }
        table.insert(toolbar_children, HorizontalSpan:new{ width = 12 })
        table.insert(toolbar_children, batch_btn)
    end

    local filter_row = HorizontalGroup:new{ align = "center" }
    for _, child in ipairs(toolbar_children) do
        table.insert(filter_row, child)
    end

    table.insert(items, FrameContainer:new{
        dimen = Geom:new{ w = sw, h = 36 },
        bordersize = 0, padding = 0, padding_left = pad,
        background = WHITE,
        LeftContainer:new{
            dimen = Geom:new{ w = content_w, h = 36 },
            filter_row,
        },
    })
    table.insert(items, sp(2))
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 2 },
        LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
    })
    table.insert(items, sp(4))

    -- ── EMPTY STATE ──
    if #self.filtered == 0 then
        table.insert(items, sp(math.floor(sh * 0.08)))
        local empty_msg = self.all_books
            and _("No highlights found on this device.\n\nHighlight text while reading to see it here.")
            or _("No highlights in this book.\n\nHighlight text while reading to see it here.")
        if self.search then
            empty_msg = _("No highlights match your search.")
        end
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = sw, h = 30 },
            TextWidget:new{
                face = Font:getFace("cfont", 18),
                text = empty_msg,
                fgcolor = DARK_GRAY,
            },
        })
        self:assembleUI(items, sw, sh)
        return
    end

    -- ── HIGHLIGHT ROWS ──
    local row_h = Screen:scaleBySize(72)

    -- Dynamically calculate how many rows fit on screen.
    -- Reserve space for: header (~50), summary (~16), filter bar (~40),
    -- dividers (~10), pagination (~44), footer (~30),
    -- plus padding (~40). Total reserved ≈ 230px.
    local reserved_h = Screen:scaleBySize(230)
    local available_h = sh - reserved_h
    local items_per_page = math.max(3, math.floor(available_h / (row_h + 1)))  -- +1 for separator

    local total_count = #self.filtered
    local total_pages = math.ceil(total_count / items_per_page)
    if self.current_page > total_pages then self.current_page = total_pages end
    if self.current_page < 1 then self.current_page = 1 end

    local start_idx = (self.current_page - 1) * items_per_page + 1
    local end_idx = math.min(start_idx + items_per_page - 1, total_count)
    local text_area_w = content_w - pad

    for idx = start_idx, end_idx do
        local hl = self.filtered[idx]
        if not hl then break end

        local icon = sourceIcon(hl)
        local text_preview = truncate(hl.text or "[Bookmark]", 70)

        local title_tw = TextWidget:new{
            face = Font:getFace("cfont", 18),
            text = icon .. " " .. text_preview,
            fgcolor = BLACK,
            max_width = text_area_w,
        }

        -- Detail line
        local detail_parts = {}
        if self.all_books and hl.book_title then
            table.insert(detail_parts, truncate(hl.book_title, 22))
        end
        table.insert(detail_parts, hl.source == SRC_KOBO and "Kobo" or "KO")
        if hl.pageno then table.insert(detail_parts, "p." .. hl.pageno) end
        if hl.note and hl.note ~= "" then table.insert(detail_parts, "📝") end
        if not self.all_books and hl.chapter and hl.chapter ~= "" then
            table.insert(detail_parts, truncate(hl.chapter, 20))
        end

        local detail_tw = TextWidget:new{
            face = Font:getFace("smallinfofont", 14),
            text = table.concat(detail_parts, "  ·  "),
            fgcolor = DARK_GRAY,
            max_width = text_area_w,
        }

        local text_col = VerticalGroup:new{
            align = "left",
            title_tw,
            VerticalSpan:new{ width = 4 },
            detail_tw,
        }

        local hl_ref = hl
        local TappableRow = InputContainer:extend{}
        function TappableRow:init()
            self.dimen = Geom:new{ w = sw, h = row_h }
            self.ges_events = {
                TapRow = { GestureRange:new{ ges = "tap", range = self.dimen } },
            }
            self[1] = FrameContainer:new{
                dimen = Geom:new{ w = sw, h = row_h },
                bordersize = 0, padding = 0, padding_left = pad,
                background = WHITE,
                CenterContainer:new{
                    dimen = Geom:new{ w = content_w, h = row_h },
                    LeftContainer:new{
                        dimen = Geom:new{ w = content_w, h = row_h },
                        text_col,
                    },
                },
            }
        end
        TappableRow.onTapRow = function()
            hub:onSelectHighlight(hl_ref)
            return true
        end

        table.insert(items, TappableRow:new{})

        -- Row separator
        if idx < end_idx then
            table.insert(items, FrameContainer:new{
                dimen = Geom:new{ w = sw, h = 1 },
                bordersize = 0, padding = 0, padding_left = pad,
                background = WHITE,
                LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
            })
        end
    end

    -- ── PAGINATION ──
    if total_pages > 1 then
        table.insert(items, sp(8))
        local prev_btn = Button:new{
            text = _("< Prev"), enabled = self.current_page > 1,
            callback = function() hub.current_page = hub.current_page - 1; hub:refresh() end,
            bordersize = 0, text_font_size = 14, padding = 4, show_parent = self,
        }
        local page_label = TextWidget:new{
            face = Font:getFace("cfont", 14),
            text = string.format(_("Page %d of %d"), self.current_page, total_pages),
            fgcolor = DARK_GRAY,
        }
        local next_btn = Button:new{
            text = _("Next >"), enabled = self.current_page < total_pages,
            callback = function() hub.current_page = hub.current_page + 1; hub:refresh() end,
            bordersize = 0, text_font_size = 14, padding = 4, show_parent = self,
        }
        local nav_group = OverlapGroup:new{
            dimen = Geom:new{ w = content_w, h = 36 },
            LeftContainer:new{ dimen = Geom:new{ w = content_w, h = 36 }, prev_btn },
            CenterContainer:new{ dimen = Geom:new{ w = content_w, h = 36 }, page_label },
            RightContainer:new{ dimen = Geom:new{ w = content_w, h = 36 }, next_btn },
        }
        table.insert(items, FrameContainer:new{
            dimen = Geom:new{ w = sw, h = 36 },
            bordersize = 0, padding = 0, padding_left = pad, padding_right = pad,
            background = WHITE,
            nav_group,
        })
    end

    -- ── FOOTER ──
    table.insert(items, sp(6))
    table.insert(items, CozyUI.buildFooter(sw, "₊ ⊹ ♡ ⋆ ☆ ⋆ ♡ ⋆ ☆ ⋆ ♡ ⊹ ₊"))

    self:assembleUI(items, sw, sh)
end

function HighlightsHub:assembleUI(items, sw, sh)
    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do table.insert(content, item) end

    self[1] = FrameContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        bordersize = 0, padding = 0,
        background = WHITE,
        content,
    }
end

-- ─── Refresh (close + reopen with preserved state) ───

function HighlightsHub:refresh()
    local state = {
        ui = self.ui,
        on_close_callback = self.on_close_callback,
        all_books = self.all_books,
        book_path = self.book_path,
        highlights = self.highlights,
        books = self.books,
        ko_count = self.ko_count,
        kobo_count = self.kobo_count,
        filtered = self.filtered,
        filter = self.filter,
        filter_label = self.filter_label,
        source_filter = self.source_filter,
        search = self.search,
        current_page = self.current_page,
    }

    UIManager:close(self)
    UIManager:nextTick(function()
        local new_hub = HighlightsHub:new(state)
        UIManager:show(new_hub)
    end)
end

-- ─── Reopen (for returning from sub-screens) ───

function HighlightsHub:reopen()
    self:refresh()
end

-- ─── Highlight selection (opens action screen) ───

function HighlightsHub:onSelectHighlight(hl)
    local hub = self

    UIManager:close(self)
    UIManager:nextTick(function()
        local action_screen = HighlightActionScreen:new{
            highlight = hl,
            viewer = hub,
            on_close = function()
                hub:reopen()
            end,
        }
        UIManager:show(action_screen)
    end)
end

-- ─── Book info helper ───

function HighlightsHub:bookInfoFor(hl)
    if hl.book_path then
        return { path = hl.book_path, title = hl.book_title or "Unknown" }
    elseif self.book_path then
        local title = "Unknown"
        if self.ui and self.ui.document then
            local props = self.ui.document:getProps()
            title = props.title or self.ui.document.file:match("([^/]+)%..+$") or "Unknown"
        end
        return { path = self.book_path, title = title }
    end
    return nil
end

-- ─── Jump to location ───

function HighlightsHub:jumpKO(hl)
    if self.all_books then
        local current = self.ui and self.ui.document and self.ui.document.file
        if current ~= hl.book_path then
            UIManager:show(InfoMessage:new{
                text = _("Open this book first to jump to the highlight:\n\n")
                    .. truncate(hl.book_title or hl.book_path, 50),
                timeout = 5,
            })
            return
        end
    end

    local page = hl.page
    if not page then
        UIManager:show(InfoMessage:new{
            text = _("No location info for this highlight."), timeout = 3,
        })
        return
    end

    if self.ui.rolling then
        if type(page) == "string" then
            self.ui:handleEvent(Event:new("GotoXPointer", page, hl.pos0 or page))
        else
            self.ui:handleEvent(Event:new("GotoPage", page))
        end
    elseif self.ui.paging then
        local pn = type(page) == "number" and page or (hl.pageno or 1)
        self.ui:handleEvent(Event:new("GotoPage", pn))
    else
        if type(page) == "string" then
            self.ui:handleEvent(Event:new("GotoXPointer", page, hl.pos0 or page))
        elseif type(page) == "number" then
            self.ui:handleEvent(Event:new("GotoPage", page))
        end
    end
end

function HighlightsHub:jumpKobo(hl)
    if self.all_books then
        local current = self.ui and self.ui.document and self.ui.document.file
        if current ~= hl.book_path then
            UIManager:show(InfoMessage:new{
                text = _("Open this book first to jump to the highlight:\n\n")
                    .. truncate(hl.book_title or hl.book_path, 50),
                timeout = 5,
            })
            return
        end
    end

    local progress = hl.progress_percent or (hl.progress and hl.progress * 100)
    if not progress then
        UIManager:show(InfoMessage:new{
            text = _("No progress data for this Kobo highlight."), timeout = 3,
        })
        return
    end

    local total = self.ui.document:getPageCount()
    if not total or total <= 0 then
        UIManager:show(InfoMessage:new{
            text = _("Cannot determine book length."), timeout = 3,
        })
        return
    end

    local approx = math.max(1, math.min(math.floor((progress / 100) * total), total))
    UIManager:show(InfoMessage:new{
        text = string.format(
            _("Jumping to ~page %d (%d%% progress)\n\nKobo highlights have approximate locations."),
            approx, math.floor(progress)),
        timeout = 3,
    })
    UIManager:scheduleIn(0.5, function()
        if self.ui.rolling then
            self.ui:handleEvent(Event:new("GotoPercent", progress))
        else
            self.ui:handleEvent(Event:new("GotoPage", approx))
        end
    end)
end

-- ─── Show note ───

function HighlightsHub:showNote(hl)
    if not hl.note or hl.note == "" then
        UIManager:show(InfoMessage:new{ text = _("No note."), timeout = 2 })
        return
    end
    local text = "Your Note\n" .. string.rep("─", 30) .. "\n\n" .. hl.note
    if hl.pageno then text = text .. "\n\n" .. string.rep("─", 30) .. "\nPage " .. hl.pageno end
    UIManager:show(InfoMessage:new{ text = text, width = Screen:getWidth() * 0.85 })
end

-- ─── Filter menu ───

function HighlightsHub:showFilterMenu()
    local buttons = {}
    local hub = self

    table.insert(buttons, {{
        text = _("Show All") .. " (" .. #self.highlights .. ")",
        callback = function()
            UIManager:close(hub._filter_dialog)
            hub.filter = nil; hub.filter_label = nil; hub.source_filter = nil
            hub:applyFilters(); hub:refresh()
        end,
    }})

    if self.ko_count > 0 and self.kobo_count > 0 then
        table.insert(buttons, {{
            text = string.format(_("KOReader only (%d)"), self.ko_count),
            callback = function()
                UIManager:close(hub._filter_dialog)
                hub.source_filter = SRC_KO; hub.filter = nil; hub.filter_label = nil
                hub:applyFilters(); hub:refresh()
            end,
        }})
        table.insert(buttons, {{
            text = string.format(_("Kobo only (%d)"), self.kobo_count),
            callback = function()
                UIManager:close(hub._filter_dialog)
                hub.source_filter = SRC_KOBO; hub.filter = nil; hub.filter_label = nil
                hub:applyFilters(); hub:refresh()
            end,
        }})
    end

    if self.all_books then
        for i, bk in ipairs(self.books) do
            if i > 10 then break end
            table.insert(buttons, {{
                text = truncate(bk.title, 30) .. " (" .. (bk.highlight_count or 0) .. ")",
                callback = function()
                    UIManager:close(hub._filter_dialog)
                    hub.filter = bk.path; hub.filter_label = truncate(bk.title, 15)
                    hub.source_filter = nil
                    hub:applyFilters(); hub:refresh()
                end,
            }})
        end
    else
        local chapters, ch_count = {}, {}
        for _, hl in ipairs(self.highlights) do
            local ch = hl.chapter or "(No Chapter)"
            if not ch_count[ch] then ch_count[ch] = 0; table.insert(chapters, ch) end
            ch_count[ch] = ch_count[ch] + 1
        end
        for i, ch in ipairs(chapters) do
            if i > 8 then break end
            table.insert(buttons, {{
                text = truncate(ch, 30) .. " (" .. ch_count[ch] .. ")",
                callback = function()
                    UIManager:close(hub._filter_dialog)
                    hub.filter = ch; hub.filter_label = truncate(ch, 15)
                    hub.source_filter = nil
                    hub:applyFilters(); hub:refresh()
                end,
            }})
        end
    end

    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function() UIManager:close(hub._filter_dialog) end,
    }})

    hub._filter_dialog = ButtonDialog:new{
        title = _("✦ Filter Highlights ✦"),
        buttons = buttons,
    }
    UIManager:show(hub._filter_dialog)
end

-- ─── Search ───

function HighlightsHub:showSearchDialog()
    local hub = self
    local dlg
    dlg = InputDialog:new{
        title = _("✦ Search Highlights ✦"),
        input = self.search or "",
        input_hint = _("Enter search text..."),
        buttons = {{
            {
                text = _("Clear"),
                callback = function()
                    UIManager:close(dlg)
                    hub.search = nil
                    hub:applyFilters(); hub:refresh()
                end,
            },
            {
                text = _("Cancel"),
                callback = function() UIManager:close(dlg) end,
            },
            {
                text = _("Search"),
                is_enter_default = true,
                callback = function()
                    local q = dlg:getInputText()
                    UIManager:close(dlg)
                    -- Limit search query length to prevent performance issues
                    if q and #q > 200 then q = q:sub(1, 200) end
                    hub.search = q
                    hub:applyFilters(); hub:refresh()
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

-- ─── Batch flashcard creation ───

function HighlightsHub:showBatchCreate()
    if #self.filtered == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No highlights to create flashcards from."), timeout = 2,
        })
        return
    end

    local hub = self
    UIManager:show(ConfirmBox:new{
        text = string.format(
            _("Create %d flashcards from visible highlights?\n\nHighlight text becomes the card front. Edit later in Cozy Flashcards."),
            #self.filtered),
        ok_text = string.format(_("Create %d"), #self.filtered),
        cancel_text = _("Cancel"),
        ok_callback = function()
            local created, failed = 0, 0
            -- Open DB once for the whole batch (not per card)
            local SQ3 = require("lua-ljsqlite3/init")
            local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
            local conn_ok, conn = pcall(SQ3.open, db_path)
            if not conn_ok or not conn then
                UIManager:show(InfoMessage:new{
                    text = _("Could not open flashcard database."), timeout = 3,
                })
                return
            end
            -- Ensure table exists
            pcall(function()
                conn:exec([[
                    CREATE TABLE IF NOT EXISTS flashcards (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        front TEXT NOT NULL, back TEXT NOT NULL,
                        source_text TEXT, source_page INTEGER,
                        source_chapter TEXT, book_path TEXT,
                        book_title TEXT, state TEXT DEFAULT 'new',
                        card_type TEXT DEFAULT 'text',
                        interval_days INTEGER DEFAULT 0,
                        ease_factor REAL DEFAULT 2.5,
                        review_count INTEGER DEFAULT 0,
                        correct_count INTEGER DEFAULT 0,
                        suspended INTEGER DEFAULT 0,
                        next_review TEXT, last_reviewed TEXT,
                        created_at TEXT DEFAULT (datetime('now', 'localtime')),
                        tags TEXT, deck_id INTEGER DEFAULT 1
                    );
                ]])
            end)
            local stmt = conn:prepare(
                "INSERT INTO flashcards (front, back, source_text, source_page, "
                .. "source_chapter, book_path, book_title, state, card_type) "
                .. "VALUES (?, ?, ?, ?, ?, ?, ?, 'new', 'text')"
            )
            for _, hl in ipairs(hub.filtered) do
                local text = (hl.text or ""):sub(1, 5000)
                if text == "" then failed = failed + 1
                else
                    local front, back = text, ""
                    local sentence_end = text:match("^(.-%.)%s")
                    if sentence_end and #sentence_end < #text then
                        front = sentence_end
                        back = (text:sub(#sentence_end + 1):match("^%s*(.*)") or "")
                    end
                    if back == "" then
                        front = "Define: " .. text:sub(1, 50) .. (#text > 50 and "..." or "")
                        back = text
                    end
                    front = (front or ""):match("^%s*(.-)%s*$") or ""
                    back = (back or ""):match("^%s*(.-)%s*$") or ""
                    if #front > 5000 then front = front:sub(1, 5000) end
                    if #back > 5000 then back = back:sub(1, 5000) end

                    if front == "" or back == "" then
                        failed = failed + 1
                    else
                        local book_info = hub:bookInfoFor(hl)
                        local insert_ok = pcall(function()
                            if stmt then
                                stmt:bind(front, back, text,
                                    hl.pageno or hl.page, hl.chapter,
                                    book_info and book_info.path,
                                    book_info and book_info.title)
                                stmt:step()
                                stmt:clearbind():reset()
                            end
                        end)
                        if insert_ok then created = created + 1
                        else failed = failed + 1 end
                    end
                end
            end
            if stmt then stmt:close() end
            pcall(function() conn:close() end)
            local msg = string.format(_("Created %d flashcards!"), created)
            if failed > 0 then msg = msg .. string.format(_("\n%d skipped."), failed) end
            msg = msg .. _("\n\nReview in Cozy Flashcards.")
            UIManager:show(InfoMessage:new{ text = msg, timeout = 5 })
        end,
    })
end


-- ============================================
-- DIAGNOSTIC FUNCTION
-- ============================================

local function showDiagnostic(ui)
    local lines = {}
    table.insert(lines, "=== Cozy Home Highlight Diagnostic ===")
    table.insert(lines, "")

    local hl_module = package.loaded["lib/highlights"]
    if hl_module then
        table.insert(lines, "lib/highlights cached: YES")
        if hl_module == HL then
            table.insert(lines, "  Same module as our HL: YES")
        else
            table.insert(lines, "  Same module as our HL: NO ← WRONG MODULE!")
        end
    else
        table.insert(lines, "lib/highlights cached: NO (not in package.loaded)")
    end

    table.insert(lines, "")
    table.insert(lines, "HL.getHighlights exists: " .. tostring(HL.getHighlights ~= nil))

    table.insert(lines, "")
    table.insert(lines, "--- Scan Paths ---")
    local paths = getScanPaths()
    for i, p in ipairs(paths) do
        local exists = lfs.attributes(p) ~= nil
        table.insert(lines, i .. ". " .. p .. (exists and " ✓" or " ✗ NOT FOUND"))
    end

    table.insert(lines, "")
    table.insert(lines, "--- Book Scan ---")
    local found = {}
    local scanned_paths = {}
    for _, sp_path in ipairs(paths) do
        if sp_path and not scanned_paths[sp_path] then
            scanned_paths[sp_path] = true
            local before = #found
            scanDir(sp_path, found)
            table.insert(lines, sp_path .. ": +" .. (#found - before) .. " books with sidecars")
        end
    end
    table.insert(lines, "Total books with sidecars: " .. #found)

    table.insert(lines, "")
    table.insert(lines, "--- Highlight Check (first 5 books) ---")
    local checked = 0
    for _, bk in ipairs(found) do
        if checked >= 5 then break end
        checked = checked + 1
        local hls = HL.getHighlights(bk.path) or {}
        table.insert(lines, bk.filename:sub(1, 30) .. ": " .. #hls .. " highlights")

        if #hls == 0 then
            local ok2, ds = pcall(DocSettings.open, DocSettings, bk.path)
            if ok2 and ds and ds.data then
                local ann = ds.data.annotations and #ds.data.annotations or 0
                local bkm = ds.data.bookmarks and #ds.data.bookmarks or 0
                table.insert(lines, "  DocSettings direct: ann=" .. ann .. " bkm=" .. bkm)
            else
                table.insert(lines, "  DocSettings direct: FAILED")
            end
        end
    end

    table.insert(lines, "")
    if ui and ui.document then
        local path = ui.document.file
        table.insert(lines, "--- Current Book ---")
        table.insert(lines, "Path: " .. (path or "nil"))
        local hls = HL.getHighlights(path) or {}
        table.insert(lines, "Highlights via HL: " .. #hls)

        local ok3, ds = pcall(DocSettings.open, DocSettings, path)
        if ok3 and ds and ds.data then
            local ann = ds.data.annotations and #ds.data.annotations or 0
            local bkm = ds.data.bookmarks and #ds.data.bookmarks or 0
            table.insert(lines, "DocSettings direct: ann=" .. ann .. " bkm=" .. bkm)
            table.insert(lines, "Sidecar: " .. tostring(DocSettings:getSidecarDir(path)))
        else
            table.insert(lines, "DocSettings: FAILED")
        end
    else
        table.insert(lines, "No book currently open")
    end

    table.insert(lines, "")
    table.insert(lines, "Kobo DB available: " .. tostring(kobo_available))

    table.insert(lines, "")
    table.insert(lines, "--- ReadHistory ---")
    pcall(function()
        local hist = ReadHistory.hist or {}
        table.insert(lines, "History entries: " .. #hist)
        local counted = 0
        for _, entry in ipairs(hist) do
            if not entry.dim and counted < 3 then
                counted = counted + 1
                table.insert(lines, "  " .. (entry.file or "?"):match("([^/]+)$") or "?")
            end
        end
    end)

    UIManager:show(InfoMessage:new{
        text = table.concat(lines, "\n"),
        width = Screen:getWidth() * 0.9,
    })
end


-- ============================================
-- PUBLIC MODULE API
-- ============================================

local Highlights = {}

function Highlights.show(ui, on_close_callback)
    local loading = InfoMessage:new{
        text = _("Scanning for highlights…"), timeout = 1,
    }
    UIManager:show(loading)
    UIManager:scheduleIn(0.1, function()
        UIManager:close(loading)
        local hub = HighlightsHub:new{
            ui = ui,
            on_close_callback = on_close_callback,
            all_books = true,
        }
        hub:loadAll()
        hub:buildUI()
        UIManager:show(hub)
    end)
end

function Highlights.showForCurrentBook(ui)
    if not ui or not ui.document then
        UIManager:show(InfoMessage:new{
            text = _("No book is currently open."),
        })
        return
    end
    local hub = HighlightsHub:new{
        ui = ui,
        on_close_callback = nil,
        all_books = false,
        book_path = ui.document.file,
    }
    hub:loadSingle()
    hub:buildUI()
    UIManager:show(hub)
end

function Highlights.showForAllBooks(ui, on_close_callback)
    Highlights.show(ui, on_close_callback)
end

function Highlights.showDiagnostic(ui)
    showDiagnostic(ui)
end

return Highlights
