-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         library.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Full-screen library browser with three modes:
--       list, list with covers, and gallery grid.
--       Supports sorting, folder hiding, and opens
--       books directly in the reader.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - lib/cozyui.lua
--       - lib/database.lua
--       - lib/bookscanner.lua
--       - lib/coverextractor.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

-- ============================================
-- IMPORTS
-- ============================================

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local Config = require("config")
local CozyUI = require("lib/cozyui")

-- ============================================
-- VIEW MODE CONSTANTS
-- ============================================

local VIEW_LIST = "list"
local VIEW_LIST_COVERS = "list_covers"
local VIEW_GALLERY = "gallery"

local SORT_TITLE = "title"
local SORT_AUTHOR = "author"
local SORT_RECENT = "recent"

-- ============================================
-- LIBRARY CONFIG (extends main Config for library-specific values)
-- ============================================

local LibConfig = {
    -- Gallery cover dimensions as fraction of screen
    gallery_cols = 3,
    gallery_cover_height_fraction = 0.22,
    gallery_spacing = 8,
    gallery_title_height = 22,

    -- List row heights (scaled) -- increased for readability
    list_row_height = 68,
    list_covers_row_height = 90,

    -- Cover aspect ratio (width:height roughly 2:3 for book covers)
    cover_aspect = 0.667,

    -- Title bar height (should match Config.UI.header_height)
    title_bar_height = 44,

    -- Nav bar height
    nav_bar_height = 40,

    -- Max books to scan
    max_scan_files = 5000,

    -- Font sizes -- increased for readability
    font_title_bar = 20,
    font_btn = 14,
    font_list_title = 18,
    font_list_detail = 14,
    font_list_series = 12,
    font_gallery_title = 11,
    font_cover_letter = nil, -- calculated from cover height
    font_cover_mini = 9,
    font_empty_state = 16,
    font_page_indicator = 14,
}

-- ============================================
-- LIBRARY SCREEN
-- ============================================

local LibraryScreen = InputContainer:extend{
    name = "cozy_library",
    ui = nil,
    on_close_callback = nil,

    -- State
    books = nil,          -- array of book info tables
    view_mode = nil,      -- current view mode
    sort_mode = nil,      -- current sort mode
    current_page = 1,     -- current page in paginated view
    items_per_page = 10,  -- depends on view mode

    -- Scanning
    scan_complete = false,
    root_dir = nil,
    hidden_folders = nil,

    -- Cover cache (keyed by filepath, holds Blitbuffer or false for "no cover")
    _cover_cache = nil,

    -- Gallery layout
    gallery_cols = nil,
    gallery_cover_h = nil,
    gallery_cover_w = nil,

    -- List layout
    list_row_h = nil,
}

local Library = {}
Library._current_instance = nil

-- ============================================
-- INITIALIZATION
-- ============================================

function LibraryScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true
    self._cover_cache = {}

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    -- Load preferences
    local Database = require("lib/database")
    local saved_view = Database:getPref("library_view_mode", VIEW_LIST)
    -- Normalize legacy values from settings screen
    if saved_view == "covers" then saved_view = VIEW_LIST_COVERS end
    self.view_mode = saved_view
    self.sort_mode = Database:getPref("library_sort_mode", SORT_TITLE)
    self.hidden_folders = Database:getHiddenFolders()

    -- Determine library root directory
    self.root_dir = G_reader_settings:readSetting("home_dir")
        or Device.home_dir
        or "/mnt/onboard"

    -- Calculate layout dimensions
    self:calcLayout()

    Library._current_instance = self

    -- Start scan, then build UI
    self:scanLibrary()
end

function LibraryScreen:calcLayout()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local usable_h = screen_h
        - Screen:scaleBySize(LibConfig.title_bar_height)
        - Screen:scaleBySize(LibConfig.nav_bar_height)
        - 4 -- separators

    if self.view_mode == VIEW_GALLERY then
        self.gallery_cols = LibConfig.gallery_cols
        self.gallery_cover_h = math.floor(screen_h * LibConfig.gallery_cover_height_fraction)
        local content_w = screen_w - Config.UI.content_padding * 2
        self.gallery_cover_w = math.floor(content_w / self.gallery_cols) - LibConfig.gallery_spacing
        local tile_h = self.gallery_cover_h + LibConfig.gallery_title_height + LibConfig.gallery_spacing
        local rows = math.floor(usable_h / tile_h)
        self.items_per_page = math.max(1, rows * self.gallery_cols)

    elseif self.view_mode == VIEW_LIST_COVERS then
        self.list_row_h = Screen:scaleBySize(LibConfig.list_covers_row_height)
        self.items_per_page = math.max(1, math.floor(usable_h / self.list_row_h))

    else -- VIEW_LIST
        self.list_row_h = Screen:scaleBySize(LibConfig.list_row_height)
        self.items_per_page = math.max(1, math.floor(usable_h / self.list_row_h))
    end
end

-- ============================================
-- SCANNING
-- ============================================

function LibraryScreen:scanLibrary()
    local BookScanner = require("lib/bookscanner")

    -- Scan filesystem for book files
    self.books = BookScanner.scan(self.root_dir, self.hidden_folders, LibConfig.max_scan_files)

    -- Enrich all books with metadata (title, author, progress from DocSettings/BookInfoManager)
    BookScanner.enrichMetadata(self.books)

    -- Sort
    self:sortBooks()

    self.scan_complete = true
    self.current_page = 1
    self:buildUI()
end

function LibraryScreen:sortBooks()
    local BookScanner = require("lib/bookscanner")

    if self.sort_mode == SORT_AUTHOR then
        BookScanner.sortByAuthor(self.books)
    elseif self.sort_mode == SORT_RECENT then
        BookScanner.sortByRecent(self.books)
    else
        BookScanner.sortByTitle(self.books)
    end
end

-- ============================================
-- EVENTS
-- ============================================

function LibraryScreen:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function LibraryScreen:onCloseWidget()
    -- Free any cached cover blitbuffers
    self:freeCoverCache()
    Library._current_instance = nil
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function LibraryScreen:onClose()
    UIManager:close(self)
    if self.on_close_callback then
        UIManager:nextTick(self.on_close_callback)
    end
    return true
end

function LibraryScreen:freeCoverCache()
    if self._cover_cache then
        for path, bb in pairs(self._cover_cache) do
            if bb and bb.free then
                bb:free()
            end
        end
        self._cover_cache = {}
    end
end

-- ============================================
-- COVER LOADING (standalone — no plugin dependencies)
-- ============================================

--- Try to get a cover Blitbuffer for a book.
-- Extracts covers directly from book files using KOReader's
-- DocumentRegistry. Fully independent of CoverBrowser or
-- ProjectTitle. Results are cached per-page to avoid repeated
-- extraction (which involves opening the book file).
function LibraryScreen:getCoverBB(filepath)
    -- Check our per-page memory cache first
    if self._cover_cache[filepath] ~= nil then
        local cached = self._cover_cache[filepath]
        if cached == false then
            return nil -- already tried, no cover available
        end
        return cached
    end

    -- Extract cover directly from the book file
    local CoverExtractor = require("lib/coverextractor")
    local cover_bb = CoverExtractor.extract(filepath)

    -- Cache the result (false = "no cover" vs nil = "not yet checked")
    self._cover_cache[filepath] = cover_bb or false
    return cover_bb
end

-- ============================================
-- UI BUILDING
-- ============================================

function LibraryScreen:buildUI()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local pad = Config.UI.content_padding

    local items = {}

    -- Title bar with view/sort/back controls
    table.insert(items, self:buildTitleBar(screen_w))

    -- Thin separator
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 2 },
        LineWidget:new{
            dimen = Geom:new{ w = screen_w - pad * 2, h = 1 },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        },
    })

    -- Book list or empty state
    if not self.scan_complete or not self.books or #self.books == 0 then
        local msg = self.scan_complete
            and _("No books found.\n\nCheck that your home directory contains supported book files.")
            or _("Scanning library...")
        table.insert(items, VerticalSpan:new{ width = 40 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 40 },
            TextWidget:new{
                face = Font:getFace("cfont", LibConfig.font_empty_state),
                text = msg,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        })
    else
        local book_content = self:buildBookList(screen_w, screen_h)
        if book_content then
            table.insert(items, book_content)
        end
    end

    -- Bottom nav bar (page controls)
    local nav_bar = self:buildNavBar(screen_w)

    -- Assemble with nav bar pinned at bottom
    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do
        table.insert(content, item)
    end

    self[1] = FrameContainer:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        bordersize = 0,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = Geom:new{ w = screen_w, h = screen_h },
            content,
            BottomContainer:new{
                dimen = Geom:new{ w = screen_w, h = screen_h },
                nav_bar,
            },
        },
    }
end

-- ============================================
-- TITLE BAR
-- ============================================

function LibraryScreen:buildTitleBar(screen_w)
    local lib_screen = self
    local pad = Config.UI.content_padding
    local bar_h = Screen:scaleBySize(LibConfig.title_bar_height)

    local face_title = Font:getFace("tfont", LibConfig.font_title_bar)

    -- Back button (left)
    local back_btn = Button:new{
        text = _("< Back"),
        callback = function()
            lib_screen:onClose()
        end,
        bordersize = 0,
        text_font_size = 16,
        padding = 8,
        padding_h = 12,
        show_parent = self,
    }

    -- Title + count
    local count_str = ""
    if self.books and #self.books > 0 then
        count_str = " (" .. #self.books .. ")"
    end
    local title_w = TextWidget:new{
        face = face_title,
        text = _("☕ Books") .. count_str,
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
    }

    -- Sort button (opens a picker dialog)
    local sort_btn = Button:new{
        text = _("[Sort]"),
        callback = function()
            lib_screen:showSortModePicker()
        end,
        bordersize = 0,
        text_font_size = LibConfig.font_btn,
        padding = 4,
        show_parent = self,
    }

    -- View mode button (opens a picker dialog)
    local view_btn = Button:new{
        text = _("[View]"),
        callback = function()
            lib_screen:showViewModePicker()
        end,
        bordersize = 0,
        text_font_size = LibConfig.font_btn,
        padding = 4,
        show_parent = self,
    }

    -- Exit button (sized for e-ink tap accuracy)
    local exit_btn = Button:new{
        text = _("✕"),
        callback = function()
            lib_screen:onClose()
        end,
        bordersize = 0,
        text_font_size = 22,
        padding = 10,
        padding_h = 16,
        show_parent = self,
    }

    local right_group = HorizontalGroup:new{
        align = "center",
        sort_btn,
        HorizontalSpan:new{ width = 6 },
        view_btn,
        HorizontalSpan:new{ width = 6 },
        exit_btn,
    }

    local bar_content = OverlapGroup:new{
        dimen = Geom:new{ w = screen_w - pad * 2, h = bar_h },
        LeftContainer:new{
            dimen = Geom:new{ w = screen_w - pad * 2, h = bar_h },
            back_btn,
        },
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w - pad * 2, h = bar_h },
            title_w,
        },
        RightContainer:new{
            dimen = Geom:new{ w = screen_w - pad * 2, h = bar_h },
            right_group,
        },
    }

    return FrameContainer:new{
        dimen = Geom:new{ w = screen_w, h = bar_h },
        bordersize = 0,
        padding = 0,
        padding_left = pad,
        padding_right = pad,
        background = Blitbuffer.COLOR_WHITE,
        bar_content,
    }
end

-- ============================================
-- BOOK LIST DISPATCH (routes to the active view mode)
-- ============================================

function LibraryScreen:buildBookList(screen_w, screen_h)
    -- Calculate page bounds
    local total = #self.books
    local total_pages = math.ceil(total / self.items_per_page)
    if self.current_page > total_pages then self.current_page = total_pages end
    if self.current_page < 1 then self.current_page = 1 end

    local start_idx = (self.current_page - 1) * self.items_per_page + 1
    local end_idx = math.min(start_idx + self.items_per_page - 1, total)

    if self.view_mode == VIEW_GALLERY then
        return self:buildGalleryView(screen_w, screen_h, start_idx, end_idx)
    elseif self.view_mode == VIEW_LIST_COVERS then
        return self:buildListCoversView(screen_w, screen_h, start_idx, end_idx)
    else
        return self:buildListView(screen_w, screen_h, start_idx, end_idx)
    end
end

-- ============================================
-- VIEW: Plain List
-- ============================================

function LibraryScreen:buildListView(screen_w, screen_h, start_idx, end_idx)
    local pad = Config.UI.content_padding
    local content_w = screen_w - pad * 2
    local row_h = self.list_row_h
    local lib_screen = self

    local rows = VerticalGroup:new{ align = "left" }

    -- If sorting by author, optionally insert author group headers
    local last_author_key = nil

    for i = start_idx, end_idx do
        local book = self.books[i]
        if not book then break end

        -- Author group header when sorting by author
        if self.sort_mode == SORT_AUTHOR then
            local author_key = (book.authors and book.authors ~= "")
                and book.authors:sub(1, 1):upper()
                or "?"
            if author_key ~= last_author_key then
                last_author_key = author_key
                local header = self:buildAuthorHeader(author_key, screen_w, content_w)
                table.insert(rows, header)
            end
        end

        local row = self:buildListRow(book, content_w, row_h)
        table.insert(rows, LeftContainer:new{
            dimen = Geom:new{ w = screen_w, h = row_h },
            row,
        })

        -- Separator
        if i < end_idx then
            table.insert(rows, LeftContainer:new{
                dimen = Geom:new{ w = screen_w, h = 1 },
                LineWidget:new{
                    dimen = Geom:new{ w = content_w, h = 1 },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                },
            })
        end
    end

    return rows
end

function LibraryScreen:buildAuthorHeader(letter, screen_w, content_w)
    local header_h = Screen:scaleBySize(28)
    local face = Font:getFace("tfont", 14)

    local label = TextWidget:new{
        face = face,
        text = letter,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        bold = true,
    }

    return FrameContainer:new{
        dimen = Geom:new{ w = screen_w, h = header_h },
        bordersize = 0,
        padding = 0,
        padding_left = Config.UI.content_padding,
        padding_top = 6,
        padding_bottom = 2,
        background = Blitbuffer.COLOR_WHITE,
        LeftContainer:new{
            dimen = Geom:new{ w = content_w, h = header_h - 8 },
            label,
        },
    }
end

function LibraryScreen:buildListRow(book, width, height)
    local lib_screen = self
    local left_pad = 12
    local face_title = Font:getFace("cfont", LibConfig.font_list_title)
    local face_detail = Font:getFace("smallinfofont", LibConfig.font_list_detail)

    -- Title (truncated)
    local title = book.title or ""
    if #title > 50 then
        title = title:sub(1, 47) .. "..."
    end

    local title_w = TextWidget:new{
        face = face_title,
        text = title,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = width - left_pad - 10,
    }

    -- Author + progress
    local detail_parts = {}
    if book.authors and book.authors ~= "" then
        local author = book.authors
        if #author > 40 then
            author = author:sub(1, 37) .. "..."
        end
        table.insert(detail_parts, author)
    end
    if book.percent_finished then
        table.insert(detail_parts, math.floor(book.percent_finished * 100) .. "%")
    end
    local detail_str = table.concat(detail_parts, "  --  ")

    local detail_w = TextWidget:new{
        face = face_detail,
        text = detail_str,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - left_pad - 10,
    }

    local text_group = VerticalGroup:new{
        align = "left",
        title_w,
        VerticalSpan:new{ width = 6 },
        detail_w,
    }

    -- Left-align text horizontally, vertically centered in the row
    local row_content = FrameContainer:new{
        dimen = Geom:new{ w = width, h = height },
        bordersize = 0,
        padding = 0,
        padding_left = left_pad,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = width - left_pad, h = height },
            LeftContainer:new{
                dimen = Geom:new{ w = width - left_pad, h = height },
                text_group,
            },
        },
    }

    -- Make tappable
    local TappableRow = InputContainer:extend{}
    function TappableRow:init()
        self.dimen = Geom:new{ w = width, h = height }
        self.ges_events = {
            TapRow = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
        }
        self[1] = row_content
    end
    function TappableRow:onTapRow()
        lib_screen:openBook(book.path)
        return true
    end

    return TappableRow:new{}
end

-- ============================================
-- VIEW: List with Covers
-- ============================================

function LibraryScreen:buildListCoversView(screen_w, screen_h, start_idx, end_idx)
    local pad = Config.UI.content_padding
    local content_w = screen_w - pad * 2
    local row_h = self.list_row_h
    local cover_w = math.floor(row_h * LibConfig.cover_aspect)

    local rows = VerticalGroup:new{ align = "left" }

    for i = start_idx, end_idx do
        local book = self.books[i]
        if not book then break end

        local row = self:buildListCoverRow(book, content_w, row_h, cover_w)
        table.insert(rows, LeftContainer:new{
            dimen = Geom:new{ w = screen_w, h = row_h },
            row,
        })
        if i < end_idx then
            table.insert(rows, LeftContainer:new{
                dimen = Geom:new{ w = screen_w, h = 1 },
                LineWidget:new{
                    dimen = Geom:new{ w = content_w, h = 1 },
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                },
            })
        end
    end

    return rows
end

function LibraryScreen:buildListCoverRow(book, width, height, cover_w)
    local lib_screen = self
    local face_title = Font:getFace("cfont", LibConfig.font_list_title)
    local face_detail = Font:getFace("smallinfofont", LibConfig.font_list_detail)
    local text_w = width - cover_w - 16

    -- Cover
    local cover_widget = self:buildCoverWidget(book, cover_w, height - 10)

    -- Title
    local title = book.title or ""
    if #title > 45 then
        title = title:sub(1, 42) .. "..."
    end

    local title_w = TextWidget:new{
        face = face_title,
        text = title,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = text_w,
    }

    -- Author + progress
    local detail_parts = {}
    if book.authors and book.authors ~= "" then
        local author = book.authors
        if #author > 35 then
            author = author:sub(1, 32) .. "..."
        end
        table.insert(detail_parts, author)
    end
    if book.percent_finished then
        table.insert(detail_parts, math.floor(book.percent_finished * 100) .. "%")
    end

    local detail_w = TextWidget:new{
        face = face_detail,
        text = table.concat(detail_parts, "  --  "),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = text_w,
    }

    -- Series info
    local text_items = {
        title_w,
        VerticalSpan:new{ width = 5 },
        detail_w,
    }

    if book.series and book.series ~= "" then
        local series_text = book.series
        if book.series_index then
            series_text = series_text .. " #" .. book.series_index
        end
        table.insert(text_items, VerticalSpan:new{ width = 4 })
        table.insert(text_items, TextWidget:new{
            face = Font:getFace("smallinfofont", LibConfig.font_list_series),
            text = series_text,
            fgcolor = Blitbuffer.COLOR_GRAY,
            max_width = text_w,
        })
    end

    local text_group = VerticalGroup:new{ align = "left" }
    for _, item in ipairs(text_items) do
        table.insert(text_group, item)
    end

    local row_content = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = cover_w, h = height },
            cover_widget,
        },
        HorizontalSpan:new{ width = 12 },
        CenterContainer:new{
            dimen = Geom:new{ w = text_w, h = height },
            LeftContainer:new{
                dimen = Geom:new{ w = text_w, h = height },
                text_group,
            },
        },
    }

    -- Make tappable
    local TappableRow = InputContainer:extend{}
    function TappableRow:init()
        self.dimen = Geom:new{ w = width, h = height }
        self.ges_events = {
            TapRow = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
        }
        self[1] = row_content
    end
    function TappableRow:onTapRow()
        lib_screen:openBook(book.path)
        return true
    end

    return TappableRow:new{}
end

-- ============================================
-- VIEW: Gallery Grid
-- ============================================

function LibraryScreen:buildGalleryView(screen_w, screen_h, start_idx, end_idx)
    local pad = Config.UI.content_padding
    local cols = self.gallery_cols
    local cover_h = self.gallery_cover_h
    local cover_w = self.gallery_cover_w
    local spacing = LibConfig.gallery_spacing
    local tile_h = cover_h + LibConfig.gallery_title_height

    local grid = VerticalGroup:new{ align = "center" }
    local current_row = HorizontalGroup:new{ align = "top" }
    local col_count = 0

    for i = start_idx, end_idx do
        local book = self.books[i]
        if not book then break end

        local tile = self:buildGalleryTile(book, cover_w, cover_h)

        if col_count > 0 then
            table.insert(current_row, HorizontalSpan:new{ width = spacing })
        end
        table.insert(current_row, tile)
        col_count = col_count + 1

        if col_count >= cols then
            table.insert(grid, CenterContainer:new{
                dimen = Geom:new{ w = screen_w, h = tile_h },
                current_row,
            })
            table.insert(grid, VerticalSpan:new{ width = spacing })
            current_row = HorizontalGroup:new{ align = "top" }
            col_count = 0
        end
    end

    -- Partial row at the end
    if col_count > 0 then
        table.insert(grid, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = tile_h },
            current_row,
        })
    end

    return grid
end

function LibraryScreen:buildGalleryTile(book, width, cover_height)
    local lib_screen = self
    local total_h = cover_height + LibConfig.gallery_title_height

    -- Cover
    local cover = self:buildCoverWidget(book, width, cover_height)

    -- Title (short, truncated)
    local title = book.title or ""
    if #title > 20 then
        title = title:sub(1, 17) .. "..."
    end

    local title_w = TextWidget:new{
        face = Font:getFace("smallinfofont", LibConfig.font_gallery_title),
        text = title,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = width,
    }

    local tile_content = VerticalGroup:new{
        align = "center",
        cover,
        VerticalSpan:new{ width = 3 },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = 18 },
            title_w,
        },
    }

    -- Make tappable
    local TappableTile = InputContainer:extend{}
    function TappableTile:init()
        self.dimen = Geom:new{ w = width, h = total_h }
        self.ges_events = {
            TapTile = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
        }
        self[1] = tile_content
    end
    function TappableTile:onTapTile()
        lib_screen:openBook(book.path)
        return true
    end

    return TappableTile:new{}
end

-- ============================================
-- COVER WIDGET (shared by list-covers and gallery)
-- ============================================

--- Build a visual cover widget for a book.
-- Extracts the real cover from the book file via CoverExtractor.
-- Falls back to a styled placeholder with first letter + title.
function LibraryScreen:buildCoverWidget(book, width, height)
    local title = book.title or "?"
    local first_letter = title:sub(1, 1):upper()

    -- Try to get real cover from BookInfoManager
    local cover_bb = self:getCoverBB(book.path)

    if cover_bb then
        local img = ImageWidget:new{
            image = cover_bb,
            width = width - 4,
            height = height - 4,
            scale_factor = 0,
            autostretch = true,
        }
        return FrameContainer:new{
            dimen = Geom:new{ w = width, h = height },
            bordersize = 1,
            padding = 1,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = width - 4, h = height - 4 },
                img,
            },
        }
    end

    -- Fallback: styled placeholder
    local letter_size = math.max(14, math.floor(height * 0.28))
    local letter_w = TextWidget:new{
        face = Font:getFace("tfont", letter_size),
        text = first_letter,
        fgcolor = Blitbuffer.COLOR_WHITE,
    }

    -- Short title snippet
    local short_title = title
    if #short_title > 22 then
        short_title = short_title:sub(1, 19) .. "..."
    end
    local mini_title = TextWidget:new{
        face = Font:getFace("smallinfofont", LibConfig.font_cover_mini),
        text = short_title,
        fgcolor = Blitbuffer.COLOR_WHITE,
        max_width = width - 10,
    }

    local cover_content = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = math.floor(height * 0.18) },
        letter_w,
        VerticalSpan:new{ width = 6 },
        mini_title,
    }

    return FrameContainer:new{
        dimen = Geom:new{ w = width, h = height },
        bordersize = 1,
        padding = 2,
        background = Blitbuffer.COLOR_DARK_GRAY,
        CenterContainer:new{
            dimen = Geom:new{ w = width - 6, h = height - 6 },
            cover_content,
        },
    }
end

-- ============================================
-- BOTTOM NAV BAR (page controls)
-- ============================================

function LibraryScreen:buildNavBar(screen_w)
    local lib_screen = self
    local pad = Config.UI.content_padding
    local bar_h = Screen:scaleBySize(LibConfig.nav_bar_height)

    local total = self.books and #self.books or 0
    local total_pages = math.max(1, math.ceil(total / self.items_per_page))

    local page_text = self.current_page .. " / " .. total_pages

    local prev_btn = Button:new{
        text = _("< Prev"),
        callback = function()
            if lib_screen.current_page > 1 then
                lib_screen.current_page = lib_screen.current_page - 1
                lib_screen:rebuildUI()
            end
        end,
        bordersize = 0,
        text_font_size = LibConfig.font_btn,
        padding = 4,
        enabled = self.current_page > 1,
        show_parent = self,
    }

    local next_btn = Button:new{
        text = _("Next >"),
        callback = function()
            if lib_screen.current_page < total_pages then
                lib_screen.current_page = lib_screen.current_page + 1
                lib_screen:rebuildUI()
            end
        end,
        bordersize = 0,
        text_font_size = LibConfig.font_btn,
        padding = 4,
        enabled = self.current_page < total_pages,
        show_parent = self,
    }

    local page_w = TextWidget:new{
        face = Font:getFace("cfont", LibConfig.font_page_indicator),
        text = page_text,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }

    local sep = LineWidget:new{
        dimen = Geom:new{ w = screen_w - pad * 2, h = 1 },
        background = Blitbuffer.COLOR_LIGHT_GRAY,
    }

    local buttons = OverlapGroup:new{
        dimen = Geom:new{ w = screen_w - pad * 2, h = bar_h - 2 },
        LeftContainer:new{
            dimen = Geom:new{ w = screen_w - pad * 2, h = bar_h - 2 },
            prev_btn,
        },
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w - pad * 2, h = bar_h - 2 },
            page_w,
        },
        RightContainer:new{
            dimen = Geom:new{ w = screen_w - pad * 2, h = bar_h - 2 },
            next_btn,
        },
    }

    local bar_content = VerticalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 2 },
            sep,
        },
        buttons,
    }

    return FrameContainer:new{
        dimen = Geom:new{ w = screen_w, h = bar_h },
        bordersize = 0,
        padding = 0,
        padding_left = pad,
        padding_right = pad,
        background = Blitbuffer.COLOR_WHITE,
        bar_content,
    }
end

-- ============================================
-- VIEW MODE PICKER (dialog with explicit choices)
-- ============================================

function LibraryScreen:showViewModePicker()
    local lib_screen = self
    local current = self.view_mode

    local function makeLabel(mode, label)
        if mode == current then
            return "> " .. label
        end
        return "  " .. label
    end

    local dialog
    dialog = ButtonDialog:new{
        title = _("✦ View Mode ✦"),
        buttons = {
            {{
                text = makeLabel(VIEW_LIST, _("List")),
                callback = function()
                    UIManager:close(dialog)
                    lib_screen:setViewMode(VIEW_LIST)
                end,
            }},
            {{
                text = makeLabel(VIEW_LIST_COVERS, _("List with Covers")),
                callback = function()
                    UIManager:close(dialog)
                    lib_screen:setViewMode(VIEW_LIST_COVERS)
                end,
            }},
            {{
                text = makeLabel(VIEW_GALLERY, _("Cover Gallery")),
                callback = function()
                    UIManager:close(dialog)
                    lib_screen:setViewMode(VIEW_GALLERY)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

function LibraryScreen:setViewMode(mode)
    if mode == self.view_mode then return end

    local Database = require("lib/database")
    self.view_mode = mode
    Database:setPref("library_view_mode", mode)
    self:freeCoverCache()
    self.current_page = 1
    self:calcLayout()
    self:rebuildUI()
end

-- ============================================
-- SORT MODE PICKER
-- ============================================

function LibraryScreen:showSortModePicker()
    local lib_screen = self
    local current = self.sort_mode

    local function makeLabel(mode, label)
        if mode == current then
            return "> " .. label
        end
        return "  " .. label
    end

    local dialog
    dialog = ButtonDialog:new{
        title = _("✦ Sort By ✦"),
        buttons = {
            {{
                text = makeLabel(SORT_TITLE, _("Title (A-Z)")),
                callback = function()
                    UIManager:close(dialog)
                    lib_screen:setSortMode(SORT_TITLE)
                end,
            }},
            {{
                text = makeLabel(SORT_AUTHOR, _("Author")),
                callback = function()
                    UIManager:close(dialog)
                    lib_screen:setSortMode(SORT_AUTHOR)
                end,
            }},
            {{
                text = makeLabel(SORT_RECENT, _("Recently Read")),
                callback = function()
                    UIManager:close(dialog)
                    lib_screen:setSortMode(SORT_RECENT)
                end,
            }},
            {{
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            }},
        },
    }
    UIManager:show(dialog)
end

function LibraryScreen:setSortMode(mode)
    if mode == self.sort_mode then return end

    local Database = require("lib/database")
    self.sort_mode = mode
    Database:setPref("library_sort_mode", mode)
    self:sortBooks()
    self.current_page = 1
    self:rebuildUI()
end

-- ============================================
-- ACTIONS
-- ============================================

function LibraryScreen:openBook(filepath)
    if not filepath then return end

    -- Verify file exists
    local attr = lfs.attributes(filepath)
    if not attr then
        UIManager:show(InfoMessage:new{
            text = _("File not found:\n") .. filepath,
            timeout = 3,
        })
        return
    end

    -- Clear the on_close_callback so closing the library does NOT reopen the home screen.
    -- We are intentionally navigating away to the reader.
    self.on_close_callback = nil

    -- Close library and open the book in the reader
    UIManager:close(self)
    UIManager:nextTick(function()
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(filepath)
    end)
end

function LibraryScreen:rebuildUI()
    -- Free old covers before rebuilding (they may no longer be on the current page)
    self:freeCoverCache()
    self:buildUI()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
end

function LibraryScreen:paintTo(bb, x, y)
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

--- Shows the library browser screen.
-- @param ui: ReaderUI or FileManager instance
-- @param on_close_callback: called when user closes the library
function Library.show(ui, on_close_callback)
    if Library._current_instance then
        UIManager:close(Library._current_instance)
        Library._current_instance = nil
    end

    local screen = LibraryScreen:new{
        ui = ui,
        on_close_callback = on_close_callback,
    }
    UIManager:show(screen)
end

function Library.isOpen()
    return Library._current_instance ~= nil
end

function Library.close()
    if Library._current_instance then
        UIManager:close(Library._current_instance)
        Library._current_instance = nil
    end
end

return Library
