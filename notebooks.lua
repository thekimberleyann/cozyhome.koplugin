-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         notebooks.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-03-05
--   ⊹  Modified:     2026-03-10
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Notebooks manager. Creates and organizes blank
--       template PDFs that the user draws on with the
--       pencil plugin. All drawing/stylus/undo is handled
--       by pencil.koplugin — this module only manages
--       notebook files (create, list, rename, duplicate,
--       delete, open).
--
--   🎀 License:      MIT
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

-- ============================================
-- IMPORTS
-- ============================================

local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")

local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local InfoMessage = require("ui/widget/infomessage")

local Screen = Device.screen
local _ = require("gettext")
local logger = require("logger")

local lfs = require("libs/libkoreader-lfs")

local Config = require("config")
local CozyUI = require("lib/cozyui")

local BLACK     = CozyUI.BLACK
local GRAY      = CozyUI.GRAY
local WHITE     = CozyUI.WHITE
local sp        = CozyUI.sp

-- Notebook icon — U+270E (lower right pencil).
-- Using raw UTF-8 bytes because LuaJIT doesn't support \u{} escapes.
-- Change to "[N]" if your device shows a box/tofu character.
local NOTEBOOK_ICON = "\xe2\x9c\x8e"

-- ============================================
-- PDF GENERATION HELPERS
-- ============================================

local function fmt(n)
    if n == math.floor(n) then
        return tostring(math.floor(n))
    end
    return string.format("%.2f", n)
end

local function xrefEntry(offset, gen, kind)
    return string.format("%010d %05d %s \n", offset, gen, kind)
end

-- ─── Template content stream generators ───
-- Each returns a PDF content stream string that draws
-- the template pattern. Coordinates are in PDF points
-- with origin at bottom-left.

local function templateBlank()
    return ""
end

local function templateLined(w, h)
    local parts = {"0.85 G", "0.5 w"}  -- light gray, thin line
    local spacing = 24
    local top_margin = spacing * 3  -- leave space at top
    local bottom_margin = spacing
    -- Draw horizontal rules from bottom margin to top margin
    local y = bottom_margin
    while y <= h - top_margin do
        parts[#parts + 1] = "0 " .. fmt(y) .. " m " .. fmt(w) .. " " .. fmt(y) .. " l S"
        y = y + spacing
    end
    return table.concat(parts, "\n")
end

local function templateGraph(w, h)
    local parts = {"0.85 G", "0.3 w"}  -- light gray, very thin
    local spacing = 20
    -- Vertical lines
    local x = spacing
    while x < w do
        parts[#parts + 1] = fmt(x) .. " 0 m " .. fmt(x) .. " " .. fmt(h) .. " l S"
        x = x + spacing
    end
    -- Horizontal lines
    local y = spacing
    while y < h do
        parts[#parts + 1] = "0 " .. fmt(y) .. " m " .. fmt(w) .. " " .. fmt(y) .. " l S"
        y = y + spacing
    end
    return table.concat(parts, "\n")
end

local function templateDotted(w, h)
    local parts = {"0.6 G"}  -- medium gray dots
    local spacing = 20
    local r = 1.2  -- dot radius
    local x = spacing
    while x < w do
        local y = spacing
        while y < h do
            -- Draw a tiny filled circle using four bezier arcs
            parts[#parts + 1] = fmt(x - r) .. " " .. fmt(y) .. " m"
            parts[#parts + 1] = fmt(x - r) .. " " .. fmt(y + r * 0.55)
                .. " " .. fmt(x - r * 0.55) .. " " .. fmt(y + r)
                .. " " .. fmt(x) .. " " .. fmt(y + r) .. " c"
            parts[#parts + 1] = fmt(x + r * 0.55) .. " " .. fmt(y + r)
                .. " " .. fmt(x + r) .. " " .. fmt(y + r * 0.55)
                .. " " .. fmt(x + r) .. " " .. fmt(y) .. " c"
            parts[#parts + 1] = fmt(x + r) .. " " .. fmt(y - r * 0.55)
                .. " " .. fmt(x + r * 0.55) .. " " .. fmt(y - r)
                .. " " .. fmt(x) .. " " .. fmt(y - r) .. " c"
            parts[#parts + 1] = fmt(x - r * 0.55) .. " " .. fmt(y - r)
                .. " " .. fmt(x - r) .. " " .. fmt(y - r * 0.55)
                .. " " .. fmt(x - r) .. " " .. fmt(y) .. " c f"
            y = y + spacing
        end
        x = x + spacing
    end
    return table.concat(parts, "\n")
end

--- Map template name to generator function.
local TEMPLATE_GENERATORS = {
    blank  = templateBlank,
    lined  = templateLined,
    graph  = templateGraph,
    dotted = templateDotted,
}

-- ─── PDF assembly ───

--- Generate a multi-page template PDF.
-- @param filepath   string  Path to write the PDF file
-- @param template   string  Template type: "blank", "lined", "graph", "dotted"
-- @param page_count number  Number of pages to generate
-- @return true on success, nil + error string on failure
local function generatePDF(filepath, template, page_count)
    local page_w = Config.NOTEBOOKS.page_w_pt
    local page_h = Config.NOTEBOOKS.page_h_pt

    local gen = TEMPLATE_GENERATORS[template]
    if not gen then
        return nil, "Unknown template: " .. tostring(template)
    end

    -- Generate the template content stream once (same for every page)
    local template_stream = gen(page_w, page_h)

    -- Object layout:
    --   1              = Catalog
    --   2              = Pages tree
    --   3 .. N+2       = Page objects
    --   N+3 .. 2N+2    = Content stream objects
    local page_obj_base    = 3
    local content_obj_base = 3 + page_count
    local total_objs       = 2 + page_count * 2

    local pieces    = {}
    local byte_pos  = 0
    local obj_offsets = {}

    local function emit(s)
        pieces[#pieces + 1] = s
        byte_pos = byte_pos + #s
    end
    local function beginObj(i)
        obj_offsets[i] = byte_pos
        emit(i .. " 0 obj\n")
    end
    local function endObj()
        emit("endobj\n\n")
    end

    -- Header
    emit("%PDF-1.4\n")
    emit("%\xE2\xE3\xCF\xD3\n\n")

    -- Obj 1: Catalog
    beginObj(1)
    emit("<<\n  /Type /Catalog\n  /Pages 2 0 R\n>>\n")
    endObj()

    -- Obj 2: Pages tree
    local kids = {}
    for i = 1, page_count do
        kids[#kids + 1] = (page_obj_base + i - 1) .. " 0 R"
    end
    beginObj(2)
    emit("<<\n")
    emit("  /Type /Pages\n")
    emit("  /Kids [" .. table.concat(kids, " ") .. "]\n")
    emit("  /Count " .. page_count .. "\n")
    emit(">>\n")
    endObj()

    -- Page objects
    for i = 1, page_count do
        local page_idx = page_obj_base + i - 1
        local cont_idx = content_obj_base + i - 1
        beginObj(page_idx)
        emit("<<\n")
        emit("  /Type /Page\n")
        emit("  /Parent 2 0 R\n")
        emit("  /MediaBox [0 0 " .. fmt(page_w) .. " " .. fmt(page_h) .. "]\n")
        emit("  /Contents " .. cont_idx .. " 0 R\n")
        emit("  /Resources << /ProcSet [/PDF] >>\n")
        emit(">>\n")
        endObj()
    end

    -- Content stream objects (same template stream for each page)
    for i = 1, page_count do
        local cont_idx = content_obj_base + i - 1
        beginObj(cont_idx)
        emit("<<\n  /Length " .. #template_stream .. "\n>>\n")
        emit("stream\n")
        emit(template_stream)
        emit("\nendstream\n")
        endObj()
    end

    -- Cross-reference table
    local xref_offset = byte_pos
    emit("xref\n")
    emit("0 " .. (total_objs + 1) .. "\n")
    emit(xrefEntry(0, 65535, "f"))
    for i = 1, total_objs do
        emit(xrefEntry(obj_offsets[i], 0, "n"))
    end

    -- Trailer
    emit("trailer\n")
    emit("<<\n  /Size " .. (total_objs + 1) .. "\n  /Root 1 0 R\n>>\n")
    emit("startxref\n")
    emit(tostring(xref_offset) .. "\n")
    emit("%%EOF\n")

    -- Write to file
    local pdf_data = table.concat(pieces)
    local f, err = io.open(filepath, "wb")
    if not f then
        return nil, "Cannot write file: " .. tostring(err)
    end
    f:write(pdf_data)
    f:close()

    logger.info("Notebooks: generated", page_count, "page", template, "PDF:", filepath)
    return true
end

-- ============================================
-- NOTEBOOK FOLDER HELPERS
-- ============================================

--- Get the path to the notebooks folder.
-- Creates the folder if it doesn't exist.
-- @return string path
local function getNotebooksDir()
    local home_dir = G_reader_settings:readSetting("home_dir")
        or Device.home_dir or "/mnt/onboard"
    local dir = home_dir .. "/" .. Config.NOTEBOOKS.folder_name
    -- Create if missing
    local attr = lfs.attributes(dir)
    if not attr then
        lfs.mkdir(dir)
        logger.info("Notebooks: created folder:", dir)
    end
    return dir
end

--- Scan the notebooks folder recursively for PDF files.
-- Descends into class subfolders so that the standalone
-- Notebooks screen can list all notebooks across all classes.
-- @return table array of {name, filename, path, size, modified, class_folder}
local function scanNotebooks()
    local dir = getNotebooksDir()
    local notebooks = {}

    local function scanDir(d, class_folder)
        local ok, iter, obj = pcall(lfs.dir, d)
        if not ok then return end

        for file in iter, obj do
            if file ~= "." and file ~= ".." then
                local filepath = d .. "/" .. file
                local attr = lfs.attributes(filepath)
                if attr then
                    if attr.mode == "directory" then
                        -- Recurse into class subfolders
                        scanDir(filepath, file)
                    elseif attr.mode == "file" and file:lower():match("%.pdf$") then
                        table.insert(notebooks, {
                            name = file:gsub("%.pdf$", ""):gsub("%.PDF$", ""),
                            filename = file,
                            path = filepath,
                            size = attr.size or 0,
                            modified = attr.modification or 0,
                            class_folder = class_folder,
                        })
                    end
                end
            end
        end
    end

    scanDir(dir, nil)

    -- Sort by most recently modified first
    table.sort(notebooks, function(a, b)
        return a.modified > b.modified
    end)

    return notebooks
end

--- Format file size for display.
local function formatSize(bytes)
    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
end

-- ============================================
-- NOTEBOOKS SCREEN
-- ============================================

local NotebooksScreen = InputContainer:extend{
    name = "cozy_notebooks_screen",
    ui = nil,
    on_back_callback = nil,
}

function NotebooksScreen:init()
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

function NotebooksScreen:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local screen = self
    local items = {}

    -- Header (no "+" button — creating notebooks requires a class context)
    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Notebooks",
        back_callback = function() screen:onClose() end,
        show_parent = self,
    }))
    table.insert(items, CozyUI.buildDottedDivider(sw, content_w))
    table.insert(items, sp(20))

    -- Info: notebooks live inside Learning Spaces
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = math.floor(sh * 0.3) },
        TextWidget:new{
            face = Font:getFace("cfont", 16),
            text = _("Notebooks live inside Learning Spaces.\nOpen a class to create and manage notebooks."),
            fgcolor = GRAY,
        },
    })

    -- List all notebooks across all classes (recursive scan)
    local all_notebooks = scanNotebooks()
    if #all_notebooks > 0 then
        table.insert(items, CozyUI.buildSectionDivider(sw, content_w, "All Notebooks"))
        table.insert(items, sp(8))
        -- Show up to 10 recent notebooks as quick-open shortcuts
        local max_show = math.min(#all_notebooks, 10)
        for i = 1, max_show do
            local nb = all_notebooks[i]
            local name_display = CozyUI.truncateText(nb.name, 35)
            local detail_str = formatSize(nb.size)
            if nb.modified > 0 then
                detail_str = detail_str .. "  \xc2\xb7  " .. os.date("%b %d", nb.modified)
            end
            -- Show class folder name if available
            if nb.class_folder then
                detail_str = detail_str .. "  \xc2\xb7  " .. nb.class_folder
            end

            local row_content = VerticalGroup:new{
                align = "left",
                TextWidget:new{
                    face = Font:getFace("cfont", 16),
                    text = NOTEBOOK_ICON .. " " .. name_display,
                    fgcolor = BLACK, max_width = content_w,
                },
                sp(2),
                TextWidget:new{
                    face = Font:getFace("cfont", 13),
                    text = detail_str,
                    fgcolor = GRAY, max_width = content_w,
                },
            }

            local nb_path = nb.path
            local TappableRow = InputContainer:extend{}
            function TappableRow:init()
                self.dimen = Geom:new{ w = content_w, h = Screen:scaleBySize(Config.UI.row_height_notebook_list) }
                self.ges_events = {
                    TapRow = { GestureRange:new{ ges = "tap", range = self.dimen } },
                }
                self[1] = LeftContainer:new{
                    dimen = self.dimen,
                    row_content,
                }
            end
            TappableRow.onTapRow = function()
                screen:onClose()
                UIManager:nextTick(function()
                    local ReaderUI = require("apps/reader/readerui")
                    ReaderUI:showReader(nb_path)
                end)
                return true
            end

            table.insert(items, CenterContainer:new{
                dimen = Geom:new{ w = sw, h = Screen:scaleBySize(Config.UI.row_height_notebook_list) },
                TappableRow:new{},
            })
        end
    end

    -- Assemble
    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do
        table.insert(content, item)
    end

    self[1] = FrameContainer:new{
        dimen = self.dimen,
        bordersize = 0, padding = 0,
        background = WHITE,
        content,
    }
end

function NotebooksScreen:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function NotebooksScreen:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function NotebooksScreen:onClose()
    UIManager:close(self)
    if self.on_back_callback then
        UIManager:nextTick(self.on_back_callback)
    end
    return true
end

function NotebooksScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end

-- ============================================
-- PUBLIC API
-- ============================================

local Notebooks = {}

--- Public access to helpers (used by screen + learningspace.lua)
Notebooks.generatePDF     = generatePDF
Notebooks.getNotebooksDir = getNotebooksDir
Notebooks.scanNotebooks   = scanNotebooks
Notebooks.formatSize      = formatSize
Notebooks.NOTEBOOK_ICON   = NOTEBOOK_ICON

function Notebooks.show(ui, on_back_callback)
    local screen = NotebooksScreen:new{
        ui = ui,
        on_back_callback = on_back_callback,
    }
    UIManager:show(screen)
end

return Notebooks
