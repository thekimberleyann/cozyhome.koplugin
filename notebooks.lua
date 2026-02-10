-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         notebooks.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Notebook manager with full-screen drawing canvas.
--       Create named notebooks, select templates, draw
--       with stylus, manage pages, and persist strokes
--       via SQLite. Graceful fallback on non-stylus devices.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - lib/cozyui.lua
--       - lib/database.lua
--       - lib/templates.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

-- ============================================
-- IMPORTS
-- ============================================

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
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
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template
local time = require("ui/time")

local Config = require("config")
local CozyUI = require("lib/cozyui")
local Templates = require("lib/templates")

-- ============================================
-- CONSTANTS
-- ============================================

local TOOLBAR_HEIGHT = 44
local TOOL_PEN = "pen"
local TOOL_ERASER = "eraser"

-- ============================================
-- NOTEBOOK LIST SCREEN
-- ============================================

local NotebookListScreen = InputContainer:extend{
    name = "cozy_notebook_list",
    ui = nil,
    on_close_callback = nil,
}

local Notebooks = {}
Notebooks._list_instance = nil
Notebooks._canvas_instance = nil

function NotebookListScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    Notebooks._list_instance = self
    self:buildUI()
end

function NotebookListScreen:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function NotebookListScreen:onCloseWidget()
    Notebooks._list_instance = nil
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function NotebookListScreen:onClose()
    UIManager:close(self)
    if self.on_close_callback then
        UIManager:nextTick(self.on_close_callback)
    end
    return true
end

function NotebookListScreen:buildUI()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local pad = Config.UI.content_padding
    local list_screen = self

    local Database = require("lib/database")
    local notebooks = Database:getNotebooks()

    local items = {}

    -- Title bar: [< Back]  ☕ Notebooks  [✕]
    table.insert(items, CozyUI.buildScreenHeader({
        sw = screen_w,
        title = "Notebooks",
        back_callback = function() list_screen:onClose() end,
        exit_callback = function() list_screen:onClose() end,
        show_parent = self,
    }))

    -- Separator
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = 2 },
        LineWidget:new{
            dimen = Geom:new{ w = screen_w - pad * 2, h = 1 },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        },
    })

    -- Notebook list or empty state
    if #notebooks == 0 then
        table.insert(items, VerticalSpan:new{ width = 60 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 50 },
            TextWidget:new{
                face = Font:getFace("cfont", 16),
                text = _("No notebooks yet."),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        })
        table.insert(items, VerticalSpan:new{ width = 10 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = 30 },
            TextWidget:new{
                face = Font:getFace("smallinfofont", 13),
                text = _("Tap [+ New] to create your first notebook."),
                fgcolor = Blitbuffer.COLOR_GRAY,
            },
        })
    else
        local row_h = Screen:scaleBySize(60)
        local content_w = screen_w - pad * 2

        for idx, nb in ipairs(notebooks) do
            local row = self:buildNotebookRow(nb, content_w, row_h)
            table.insert(items, LeftContainer:new{
                dimen = Geom:new{ w = screen_w, h = row_h },
                row,
            })
            if idx < #notebooks then
                table.insert(items, LeftContainer:new{
                    dimen = Geom:new{ w = screen_w, h = 1 },
                    LineWidget:new{
                        dimen = Geom:new{ w = content_w, h = 1 },
                        background = Blitbuffer.COLOR_LIGHT_GRAY,
                    },
                })
            end
        end
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

function NotebookListScreen:buildNotebookRow(notebook, width, height)
    local list_screen = self
    local face_title = Font:getFace("cfont", 16)
    local face_detail = Font:getFace("smallinfofont", 12)

    local title_w = TextWidget:new{
        face = face_title,
        text = notebook.name,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = width - 80,
    }

    local template_label = Templates.getLabel(notebook.template or "grid")
    local pc = tonumber(notebook.page_count) or 1
    local detail_str = template_label
        .. "  ·  " .. tostring(pc) .. " page(s)"
        .. "  ·  " .. tostring(notebook.updated_at or "")

    local detail_w = TextWidget:new{
        face = face_detail,
        text = detail_str,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = width - 20,
    }

    local text_group = VerticalGroup:new{
        align = "left",
        title_w,
        VerticalSpan:new{ width = 3 },
        detail_w,
    }

    local row_content = FrameContainer:new{
        dimen = Geom:new{ w = width, h = height },
        bordersize = 0,
        padding = 8,
        background = Blitbuffer.COLOR_WHITE,
        LeftContainer:new{
            dimen = Geom:new{ w = width - 16, h = height - 16 },
            text_group,
        },
    }

    -- Tappable wrapper
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
            HoldRow = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
            },
        }
        self[1] = row_content
    end
    function TappableRow:onTapRow()
        list_screen:openNotebook(notebook)
        return true
    end
    function TappableRow:onHoldRow()
        list_screen:showNotebookActions(notebook)
        return true
    end

    return TappableRow:new{}
end

function NotebookListScreen:openNotebook(notebook)
    UIManager:close(self)
    UIManager:nextTick(function()
        Notebooks.openCanvas(notebook, self.ui, self.on_close_callback)
    end)
end

function NotebookListScreen:showCreateDialog()
    local list_screen = self
    local template_idx = 1
    local template_keys = Templates.getKeys()

    local dialog
    dialog = InputDialog:new{
        title = _("✦ New Notebook ✦"),
        input = "",
        input_hint = _("Notebook name"),
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
                    text = _("Template: Grid"),
                    callback = function()
                        template_idx = template_idx % #template_keys + 1
                        -- Update button text
                        local label = Templates.getLabel(template_keys[template_idx])
                        dialog:getButtonById("template_btn"):setText(_("Template: ") .. label)
                        UIManager:setDirty(dialog, "full")
                    end,
                    id = "template_btn",
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText()
                        if name and name ~= "" then
                            local Database = require("lib/database")
                            local nb_id = Database:createNotebook(name, template_keys[template_idx])
                            UIManager:close(dialog)
                            if nb_id then
                                -- Refresh list
                                list_screen:buildUI()
                                UIManager:setDirty(list_screen, "full")
                            end
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter a name."),
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

function NotebookListScreen:showNotebookActions(notebook)
    local list_screen = self
    local Database = require("lib/database")

    local dialog
    dialog = require("ui/widget/buttondialogtitle"):new{
        title = notebook.name,
        buttons = {
            {
                {
                    text = _("Open"),
                    callback = function()
                        UIManager:close(dialog)
                        list_screen:openNotebook(notebook)
                    end,
                },
                {
                    text = _("Rename"),
                    callback = function()
                        UIManager:close(dialog)
                        list_screen:showRenameDialog(notebook)
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(dialog)
                        list_screen:confirmDelete(notebook)
                    end,
                },
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

function NotebookListScreen:showRenameDialog(notebook)
    local list_screen = self
    local dialog
    dialog = InputDialog:new{
        title = _("✦ Rename Notebook ✦"),
        input = notebook.name,
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
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_name = dialog:getInputText()
                        if new_name and new_name ~= "" then
                            local Database = require("lib/database")
                            Database:renameNotebook(notebook.id, new_name)
                            UIManager:close(dialog)
                            list_screen:buildUI()
                            UIManager:setDirty(list_screen, "full")
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function NotebookListScreen:confirmDelete(notebook)
    local list_screen = self
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete notebook '%1' and all its pages?\n\nThis cannot be undone."), notebook.name),
        ok_text = _("Delete"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            local Database = require("lib/database")
            Database:deleteNotebook(notebook.id)
            list_screen:buildUI()
            UIManager:setDirty(list_screen, "full")
        end,
    })
end

function NotebookListScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

-- ============================================
-- CANVAS SCREEN (Drawing Surface)
-- ============================================

local CanvasScreen = InputContainer:extend{
    name = "cozy_notebook_canvas",
    ui = nil,
    on_close_callback = nil,

    -- Notebook data
    notebook = nil,
    current_page = 1,
    page_count = 1,
    template_key = "grid",

    -- Drawing state
    strokes = nil,       -- strokes for current page
    current_stroke = nil,
    undo_stack = nil,
    current_tool = TOOL_PEN,
    pen_width = 3,
    eraser_width = 20,

    -- Stylus raw input
    stylus_callback_registered = false,
    pen_down = false,
    pen_x = 0,
    pen_y = 0,

    -- Refresh management
    last_refresh_time = 0,
    refresh_interval_ms = 16,
    dirty_region = nil,
    pending_refresh = nil,
    refresh_delay_ms = 600,

    -- Template background buffer
    _template_bb = nil,

    -- Toolbar height
    toolbar_h = 0,
}

function CanvasScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true
    self.strokes = {}
    self.undo_stack = {}
    self.toolbar_h = Screen:scaleBySize(TOOLBAR_HEIGHT)

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self.template_key = self.notebook.template or "grid"
    self.page_count = self.notebook.page_count or 1
    self.current_page = 1

    Notebooks._canvas_instance = self

    -- Load strokes for current page
    self:loadPageStrokes()

    -- Generate template background
    self:generateTemplate()

    -- Setup stylus input
    self:setupStylusInput()
end

function CanvasScreen:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function CanvasScreen:onCloseWidget()
    self:savePageStrokes()
    self:teardownStylusInput()
    self:freeTemplate()
    Notebooks._canvas_instance = nil
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function CanvasScreen:onClose()
    self:savePageStrokes()
    UIManager:close(self)
    -- Return to notebook list
    UIManager:nextTick(function()
        Notebooks.show(self.ui, self.on_close_callback)
    end)
    return true
end

-- ============================================
-- TEMPLATE BACKGROUND
-- ============================================

function CanvasScreen:generateTemplate()
    self:freeTemplate()
    local w = Screen:getWidth()
    local h = Screen:getHeight()
    self._template_bb = Blitbuffer.new(w, h, Screen.bb:getType())
    self._template_bb:fill(Blitbuffer.COLOR_WHITE)
    Templates.draw(self._template_bb, self.template_key, w, h, self.toolbar_h)
end

function CanvasScreen:freeTemplate()
    if self._template_bb then
        self._template_bb:free()
        self._template_bb = nil
    end
end

-- ============================================
-- STROKE PERSISTENCE
-- ============================================

function CanvasScreen:loadPageStrokes()
    local Database = require("lib/database")
    local data = Database:getPageStrokes(self.notebook.id, self.current_page)
    if data then
        self.strokes = data
    else
        self.strokes = {}
    end
    self.undo_stack = {}
end

function CanvasScreen:savePageStrokes()
    if not self.notebook then return end
    local Database = require("lib/database")
    Database:savePageStrokes(self.notebook.id, self.current_page, self.strokes)
    Database:updateNotebookTimestamp(self.notebook.id)
end

-- ============================================
-- PAGE NAVIGATION
-- ============================================

function CanvasScreen:goToPage(page_num)
    if page_num < 1 or page_num > self.page_count then return end
    if page_num == self.current_page then return end

    self:savePageStrokes()
    self.current_page = page_num
    self:loadPageStrokes()
    self:repaintFull()
end

function CanvasScreen:addPage()
    self:savePageStrokes()
    self.page_count = self.page_count + 1
    self.current_page = self.page_count

    local Database = require("lib/database")
    Database:setNotebookPageCount(self.notebook.id, self.page_count)

    self.strokes = {}
    self.undo_stack = {}
    self:repaintFull()
end

function CanvasScreen:deletePage()
    if self.page_count <= 1 then
        UIManager:show(InfoMessage:new{
            text = _("Cannot delete the last page."),
            timeout = 2,
        })
        return
    end

    local ConfirmBox = require("ui/widget/confirmbox")
    local canvas = self
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete page %1 of %2?"), self.current_page, self.page_count),
        ok_text = _("Delete"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            local Database = require("lib/database")
            Database:deleteNotebookPage(canvas.notebook.id, canvas.current_page, canvas.page_count)
            canvas.page_count = canvas.page_count - 1
            if canvas.current_page > canvas.page_count then
                canvas.current_page = canvas.page_count
            end
            Database:setNotebookPageCount(canvas.notebook.id, canvas.page_count)
            canvas:loadPageStrokes()
            canvas:repaintFull()
        end,
    })
end

-- ============================================
-- STYLUS INPUT
-- ============================================

function CanvasScreen:setupStylusInput()
    local Input = Device.input
    if not Input then return end

    -- Try direct stylus callback for lowest latency
    if Input.registerStylusCallback then
        local canvas = self
        Input:registerStylusCallback(function(input, slot)
            return canvas:handleStylusSlot(input, slot)
        end)
        self.stylus_callback_registered = true
        logger.info("CozyHome Notebooks: stylus callback registered")
    end

    -- Also register touch zones as fallback
    if self.ui and self.ui.registerTouchZones then
        self.ui:registerTouchZones({
            {
                id = "notebook_canvas_tap",
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                overrides = {},
                handler = function(ges) return self:onCanvasTap(ges) end,
            },
            {
                id = "notebook_canvas_pan",
                ges = "pan",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                overrides = {},
                handler = function(ges) return self:onCanvasPan(ges) end,
            },
            {
                id = "notebook_canvas_pan_release",
                ges = "pan_release",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                overrides = {},
                handler = function(ges) return self:onCanvasPanRelease(ges) end,
            },
        })
    end

    -- Simple gesture handling for toolbar taps
    self.ges_events = {
        TapCanvas = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
    }
end

function CanvasScreen:teardownStylusInput()
    if self.stylus_callback_registered then
        local Input = Device.input
        if Input and Input.unregisterStylusCallback then
            Input:unregisterStylusCallback()
        end
        self.stylus_callback_registered = false
    end

    if self.ui and self.ui.unRegisterTouchZones then
        self.ui:unRegisterTouchZones({
            { id = "notebook_canvas_tap" },
            { id = "notebook_canvas_pan" },
            { id = "notebook_canvas_pan_release" },
        })
    end

    self:cancelPendingRefresh()
end

function CanvasScreen:transformCoordinates(x, y)
    -- Borrow the transform logic from pencil plugin
    local rotation = Screen:getRotationMode()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()

    if rotation == 0 then
        return x, y
    elseif rotation == 1 then
        return sw - y, x
    elseif rotation == 2 then
        return sw - x, sh - y
    elseif rotation == 3 then
        return y, sh - x
    end
    return x, y
end

function CanvasScreen:handleStylusSlot(input, slot)
    local TOOL_TYPE_PEN = 1
    local TOOL_TYPE_ERASER = 2

    -- Determine effective tool from hardware
    local effective_tool = self.current_tool
    if slot.tool == TOOL_TYPE_ERASER then
        effective_tool = TOOL_ERASER
    end

    if slot.id and slot.id >= 0 then
        local raw_x = slot.x or self.pen_x
        local raw_y = slot.y or self.pen_y
        local x, y = self:transformCoordinates(raw_x, raw_y)

        -- Check if tap is in toolbar area
        if not self.pen_down and y < self.toolbar_h then
            return false  -- Let the toolbar handle it
        end

        if not self.pen_down then
            -- Pen down
            self.pen_down = true
            self:cancelPendingRefresh()

            if effective_tool == TOOL_ERASER then
                self.erasing = true
                self.eraser_deleted = {}
            else
                -- Start new stroke
                self.current_stroke = {
                    points = {},
                    width = self.pen_width,
                }
            end
        end

        self.pen_x = x
        self.pen_y = y

        if effective_tool == TOOL_ERASER and self.erasing then
            local deleted = self:eraseAtPoint(x, y)
            if deleted then
                for _, s in ipairs(deleted) do
                    table.insert(self.eraser_deleted, s)
                end
                self:repaintFull()
            end
        elseif self.current_stroke then
            table.insert(self.current_stroke.points, { x = x, y = y })
            local n = #self.current_stroke.points
            local width = self.current_stroke.width

            if n >= 2 then
                local p1 = self.current_stroke.points[n - 1]
                local p2 = self.current_stroke.points[n]
                self:drawLineSegment(Screen.bb, p1.x, p1.y, p2.x, p2.y, width)
            elseif n == 1 then
                local p = self.current_stroke.points[1]
                local half_w = math.floor(width / 2)
                Screen.bb:paintRect(p.x - half_w, p.y - half_w, width, width, Blitbuffer.COLOR_BLACK)
            end

            -- Accumulate dirty region
            local half_w = math.floor(width / 2) + 2
            if n >= 2 then
                local p1 = self.current_stroke.points[n - 1]
                local p2 = self.current_stroke.points[n]
                local dx = math.min(p1.x, p2.x) - half_w
                local dy = math.min(p1.y, p2.y) - half_w
                local dw = math.abs(p2.x - p1.x) + width + 4
                local dh = math.abs(p2.y - p1.y) + width + 4
                self:accumulateDirty(dx, dy, dw, dh)
            else
                self:accumulateDirty(x - half_w, y - half_w, width + 4, width + 4)
            end

            -- Periodic refresh
            local now = time.now()
            if time.to_ms(now - self.last_refresh_time) >= self.refresh_interval_ms then
                self.last_refresh_time = now
                self:flushDirtyRegion()
            end
        end
    else
        -- Pen lifted
        if self.pen_down then
            self.pen_down = false

            if self.erasing then
                self.erasing = false
                if self.eraser_deleted and #self.eraser_deleted > 0 then
                    table.insert(self.undo_stack, { type = "delete", strokes = self.eraser_deleted })
                    self:savePageStrokes()
                end
                self.eraser_deleted = nil
            elseif self.current_stroke and #self.current_stroke.points >= 1 then
                table.insert(self.strokes, self.current_stroke)
                table.insert(self.undo_stack, { type = "add", stroke_idx = #self.strokes })
                self:savePageStrokes()
                self.current_stroke = nil
            end

            self:scheduleDelayedRefresh()
        end
    end

    return true  -- Dominate: prevent gesture detection
end

-- ============================================
-- GESTURE FALLBACKS (for devices without stylus callback)
-- ============================================

function CanvasScreen:onTapCanvas(_, ges)
    if not ges then return false end
    local x, y = ges.pos.x, ges.pos.y

    -- Toolbar area: handle toolbar taps
    if y < self.toolbar_h then
        return self:handleToolbarTap(x, y)
    end

    -- Drawing area: single dot
    if self.current_tool == TOOL_ERASER then
        local deleted = self:eraseAtPoint(x, y)
        if deleted then
            table.insert(self.undo_stack, { type = "delete", strokes = deleted })
            self:savePageStrokes()
            self:repaintFull()
        end
    else
        local stroke = {
            points = { { x = x, y = y } },
            width = self.pen_width,
        }
        table.insert(self.strokes, stroke)
        table.insert(self.undo_stack, { type = "add", stroke_idx = #self.strokes })
        self:savePageStrokes()

        local half_w = math.floor(self.pen_width / 2)
        Screen.bb:paintRect(x - half_w, y - half_w, self.pen_width, self.pen_width, Blitbuffer.COLOR_BLACK)
        Screen:refreshFast(x - half_w - 2, y - half_w - 2, self.pen_width + 4, self.pen_width + 4)
    end

    return true
end

function CanvasScreen:onCanvasTap(ges)
    return self:onTapCanvas(nil, ges)
end

function CanvasScreen:onCanvasPan(ges)
    if not ges then return false end
    if ges.pos.y < self.toolbar_h then return false end

    if self.current_tool == TOOL_ERASER then
        local deleted = self:eraseAtPoint(ges.pos.x, ges.pos.y)
        if deleted then
            if not self._pan_eraser_deleted then
                self._pan_eraser_deleted = {}
            end
            for _, s in ipairs(deleted) do
                table.insert(self._pan_eraser_deleted, s)
            end
            self:repaintFull()
        end
        return true
    end

    -- Pen mode
    if not self.current_stroke then
        self.current_stroke = {
            points = {},
            width = self.pen_width,
        }
        if ges.start_pos then
            table.insert(self.current_stroke.points, { x = ges.start_pos.x, y = ges.start_pos.y })
        end
    end

    table.insert(self.current_stroke.points, { x = ges.pos.x, y = ges.pos.y })

    local n = #self.current_stroke.points
    if n >= 2 then
        local p1 = self.current_stroke.points[n - 1]
        local p2 = self.current_stroke.points[n]
        self:drawLineSegment(Screen.bb, p1.x, p1.y, p2.x, p2.y, self.pen_width)
    end

    return true
end

function CanvasScreen:onCanvasPanRelease(ges)
    if self.current_tool == TOOL_ERASER then
        if self._pan_eraser_deleted and #self._pan_eraser_deleted > 0 then
            table.insert(self.undo_stack, { type = "delete", strokes = self._pan_eraser_deleted })
            self:savePageStrokes()
        end
        self._pan_eraser_deleted = nil
        return true
    end

    if self.current_stroke and #self.current_stroke.points >= 1 then
        table.insert(self.strokes, self.current_stroke)
        table.insert(self.undo_stack, { type = "add", stroke_idx = #self.strokes })
        self:savePageStrokes()
    end
    self.current_stroke = nil
    self:scheduleDelayedRefresh()
    return true
end

-- ============================================
-- TOOLBAR TAP HANDLING
-- ============================================

function CanvasScreen:handleToolbarTap(x, y)
    local screen_w = Screen:getWidth()
    local btn_w = math.floor(screen_w / 7)

    -- Buttons from left to right:
    -- [Back] [Pen] [Eraser] [Undo] [<] [Page X/Y] [>] [+Page] [Del]
    -- Simplified layout with fewer regions:
    local region = math.floor(x / btn_w)

    if region == 0 then
        -- Back
        self:onClose()
    elseif region == 1 then
        -- Pen tool
        self.current_tool = TOOL_PEN
        self:repaintFull()
    elseif region == 2 then
        -- Eraser tool
        self.current_tool = TOOL_ERASER
        self:repaintFull()
    elseif region == 3 then
        -- Undo
        self:undo()
    elseif region == 4 then
        -- Previous page
        if self.current_page > 1 then
            self:goToPage(self.current_page - 1)
        end
    elseif region == 5 then
        -- Next page or add page
        if self.current_page < self.page_count then
            self:goToPage(self.current_page + 1)
        end
    elseif region == 6 then
        -- Add page / Delete page (tap right edge for add, hold for delete submenu)
        self:showPageMenu()
    end

    return true
end

function CanvasScreen:showPageMenu()
    local canvas = self
    local dialog
    dialog = require("ui/widget/buttondialogtitle"):new{
        title = T(_("✦ Page %1 of %2 ✦"), self.current_page, self.page_count),
        buttons = {
            {
                {
                    text = _("Add Page After"),
                    callback = function()
                        UIManager:close(dialog)
                        canvas:addPage()
                    end,
                },
                {
                    text = _("Delete This Page"),
                    callback = function()
                        UIManager:close(dialog)
                        canvas:deletePage()
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

-- ============================================
-- DRAWING HELPERS
-- ============================================

function CanvasScreen:drawLineSegment(bb, x1, y1, x2, y2, width)
    local dx = x2 - x1
    local dy = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    local half_w = math.floor(width / 2)
    local color = Blitbuffer.COLOR_BLACK

    if dist < 1 then
        bb:paintRect(x1 - half_w, y1 - half_w, width, width, color)
        return
    end

    local steps = math.ceil(dist)
    for i = 0, steps do
        local t = i / steps
        local x = math.floor(x1 + dx * t)
        local y = math.floor(y1 + dy * t)
        bb:paintRect(x - half_w, y - half_w, width, width, color)
    end
end

function CanvasScreen:eraseAtPoint(px, py)
    local threshold = self.eraser_width
    local threshold_sq = threshold * threshold
    local deleted = {}
    local indices_to_remove = {}

    for i, stroke in ipairs(self.strokes) do
        if stroke.points then
            for _, pt in ipairs(stroke.points) do
                local dx = px - pt.x
                local dy = py - pt.y
                if dx * dx + dy * dy <= threshold_sq then
                    table.insert(deleted, stroke)
                    table.insert(indices_to_remove, i)
                    break
                end
            end
        end
    end

    if #indices_to_remove > 0 then
        table.sort(indices_to_remove, function(a, b) return a > b end)
        for _, idx in ipairs(indices_to_remove) do
            table.remove(self.strokes, idx)
        end
        return deleted
    end
    return nil
end

function CanvasScreen:undo()
    if #self.undo_stack == 0 then return end

    local last = table.remove(self.undo_stack)
    if last.type == "add" then
        local idx = last.stroke_idx
        if idx and self.strokes[idx] then
            table.remove(self.strokes, idx)
        end
    elseif last.type == "delete" then
        for _, stroke in ipairs(last.strokes) do
            table.insert(self.strokes, stroke)
        end
    end

    self:savePageStrokes()
    self:repaintFull()
end

-- ============================================
-- REFRESH MANAGEMENT
-- ============================================

function CanvasScreen:accumulateDirty(x, y, w, h)
    if self.dirty_region then
        local r = self.dirty_region
        local nx = math.min(r.x, x)
        local ny = math.min(r.y, y)
        local nx2 = math.max(r.x + r.w, x + w)
        local ny2 = math.max(r.y + r.h, y + h)
        self.dirty_region = { x = nx, y = ny, w = nx2 - nx, h = ny2 - ny }
    else
        self.dirty_region = { x = x, y = y, w = w, h = h }
    end
end

function CanvasScreen:flushDirtyRegion()
    if not self.dirty_region then return end
    local r = self.dirty_region
    local rx = math.max(0, math.floor(r.x))
    local ry = math.max(0, math.floor(r.y))
    local rw = math.min(Screen:getWidth() - rx, math.ceil(r.w))
    local rh = math.min(Screen:getHeight() - ry, math.ceil(r.h))
    Screen:refreshUI(rx, ry, rw, rh)
    self.dirty_region = nil
end

function CanvasScreen:scheduleDelayedRefresh()
    self:cancelPendingRefresh()
    self.pending_refresh = UIManager:scheduleIn(self.refresh_delay_ms / 1000, function()
        self.pending_refresh = nil
        UIManager:setDirty(self, "fast")
    end)
end

function CanvasScreen:cancelPendingRefresh()
    if self.pending_refresh then
        UIManager:unschedule(self.pending_refresh)
        self.pending_refresh = nil
    end
end

function CanvasScreen:repaintFull()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
end

-- ============================================
-- PAINTING
-- ============================================

function CanvasScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    -- Paint template background
    if self._template_bb then
        bb:blitFrom(self._template_bb, x, y, 0, 0, self.dimen.w, self.dimen.h)
    else
        bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    end

    -- Paint toolbar
    self:paintToolbar(bb, x, y)

    -- Paint all saved strokes
    for _, stroke in ipairs(self.strokes) do
        self:renderStroke(bb, stroke)
    end

    -- Paint current in-progress stroke
    if self.current_stroke then
        self:renderStroke(bb, self.current_stroke)
    end
end

function CanvasScreen:paintToolbar(bb, x, y)
    local screen_w = self.dimen.w
    local h = self.toolbar_h
    local pad = 6

    -- Toolbar background
    bb:paintRect(x, y, screen_w, h, Blitbuffer.COLOR_WHITE)
    -- Bottom border
    bb:paintRect(x, y + h - 1, screen_w, 1, Blitbuffer.COLOR_LIGHT_GRAY)

    local face = Font:getFace("smallinfofont", 12)
    local face_bold = Font:getFace("tfont", 12)

    -- Layout buttons across toolbar width
    local btn_w = math.floor(screen_w / 7)
    local btn_y = y + math.floor(h / 2)

    local labels = {
        "< Back",
        self.current_tool == TOOL_PEN and "[Pen]" or "Pen",
        self.current_tool == TOOL_ERASER and "[Eraser]" or "Eraser",
        "Undo",
        "<",
        tostring(self.current_page) .. "/" .. tostring(self.page_count),
        ">",
    }

    for i, label in ipairs(labels) do
        local use_bold = (i == 2 and self.current_tool == TOOL_PEN)
            or (i == 3 and self.current_tool == TOOL_ERASER)
        local f = use_bold and face_bold or face
        local tw = TextWidget:new{
            face = f,
            text = label,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        local tw_size = tw:getSize()
        local tx = x + (i - 1) * btn_w + math.floor((btn_w - tw_size.w) / 2)
        local ty = btn_y - math.floor(tw_size.h / 2)
        tw:paintTo(bb, tx, ty)
        tw:free()
    end
end

function CanvasScreen:renderStroke(bb, stroke)
    if not stroke or not stroke.points or #stroke.points < 1 then return end

    local width = stroke.width or self.pen_width
    local color = Blitbuffer.COLOR_BLACK

    if #stroke.points == 1 then
        local p = stroke.points[1]
        local half_w = math.floor(width / 2)
        bb:paintRect(p.x - half_w, p.y - half_w, width, width, color)
    else
        for i = 2, #stroke.points do
            local p1 = stroke.points[i - 1]
            local p2 = stroke.points[i]
            self:drawLineSegment(bb, p1.x, p1.y, p2.x, p2.y, width)
        end
    end
end

-- ============================================
-- PUBLIC API
-- ============================================

--- Show the notebook list screen.
function Notebooks.show(ui, on_close_callback)
    -- Check if device has stylus support
    if not Device:isTouchDevice() then
        UIManager:show(InfoMessage:new{
            text = _("Notebooks require a touch-enabled device."),
            timeout = 3,
        })
        return
    end

    if Notebooks._list_instance then
        UIManager:close(Notebooks._list_instance)
        Notebooks._list_instance = nil
    end

    local screen = NotebookListScreen:new{
        ui = ui,
        on_close_callback = on_close_callback,
    }
    UIManager:show(screen)
end

--- Open a notebook directly in the canvas.
function Notebooks.openCanvas(notebook, ui, on_close_callback)
    if Notebooks._canvas_instance then
        UIManager:close(Notebooks._canvas_instance)
        Notebooks._canvas_instance = nil
    end

    local screen = CanvasScreen:new{
        ui = ui,
        on_close_callback = on_close_callback,
        notebook = notebook,
    }
    UIManager:show(screen)
end

--- Check if the device likely supports stylus notebooks.
function Notebooks.isSupported()
    -- All touch devices can use basic finger drawing;
    -- Stylus-specific features (pressure, eraser end) need stylus hardware.
    return Device:isTouchDevice()
end

function Notebooks.isOpen()
    return Notebooks._list_instance ~= nil or Notebooks._canvas_instance ~= nil
end

function Notebooks.close()
    if Notebooks._canvas_instance then
        UIManager:close(Notebooks._canvas_instance)
        Notebooks._canvas_instance = nil
    end
    if Notebooks._list_instance then
        UIManager:close(Notebooks._list_instance)
        Notebooks._list_instance = nil
    end
end

return Notebooks
