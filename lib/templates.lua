-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         lib/templates.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Notebook page template generator. Draws grid
--       lines, dots, rules, cornell, and planner layouts
--       onto BlitBuffers for notebook backgrounds.
--       Cached per-session for performance.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       (none — standalone rendering module)
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local logger = require("logger")

local Templates = {}

-- Line color for templates (light gray so ink stands out)
local LINE_COLOR = Blitbuffer.Color8(0xCC)
local LINE_COLOR_DARK = Blitbuffer.Color8(0xAA)
local DOT_COLOR = Blitbuffer.Color8(0xBB)

-- ============================================
-- TEMPLATE REGISTRY
-- ============================================

Templates.TYPES = {
    { key = "blank",   label = "Blank" },
    { key = "grid",    label = "Grid" },
    { key = "lined",   label = "Lined" },
    { key = "dotgrid", label = "Dot Grid" },
    { key = "cornell", label = "Cornell" },
    { key = "planner", label = "Planner" },
}

--- Get the list of available template keys.
function Templates.getKeys()
    local keys = {}
    for _, t in ipairs(Templates.TYPES) do
        table.insert(keys, t.key)
    end
    return keys
end

--- Get a display label for a template key.
function Templates.getLabel(key)
    for _, t in ipairs(Templates.TYPES) do
        if t.key == key then return t.label end
    end
    return key
end

-- ============================================
-- TEMPLATE RENDERERS
-- ============================================
-- Each renderer receives a BlitBuffer and draws
-- the template pattern onto it. The buffer is
-- pre-filled with white by the caller.

--- Blank template - no lines, just white.
function Templates.drawBlank(bb, w, h, margin_top)
    -- Nothing to draw
end

--- Square grid template.
function Templates.drawGrid(bb, w, h, margin_top)
    margin_top = margin_top or 0
    local spacing = Screen:scaleBySize(24)
    local margin_left = Screen:scaleBySize(20)
    local margin_right = Screen:scaleBySize(20)
    local margin_bottom = Screen:scaleBySize(20)

    -- Horizontal lines
    local y = margin_top + spacing
    while y < h - margin_bottom do
        bb:paintRect(margin_left, y, w - margin_left - margin_right, 1, LINE_COLOR)
        y = y + spacing
    end

    -- Vertical lines
    local x = margin_left + spacing
    while x < w - margin_right do
        bb:paintRect(x, margin_top, 1, h - margin_top - margin_bottom, LINE_COLOR)
        x = x + spacing
    end
end

--- Horizontal ruled lines template.
function Templates.drawLined(bb, w, h, margin_top)
    margin_top = margin_top or 0
    local spacing = Screen:scaleBySize(30)
    local margin_left = Screen:scaleBySize(20)
    local margin_right = Screen:scaleBySize(20)
    local margin_bottom = Screen:scaleBySize(20)

    -- Optional left margin line (red on color, dark gray on grayscale)
    local margin_line_x = margin_left + Screen:scaleBySize(30)
    if Device:hasColorScreen() then
        bb:paintRect(margin_line_x, margin_top, 1, h - margin_top - margin_bottom,
            Blitbuffer.ColorRGB32(0xDD, 0x66, 0x66, 0xFF))
    else
        bb:paintRect(margin_line_x, margin_top, 1, h - margin_top - margin_bottom, LINE_COLOR_DARK)
    end

    -- Horizontal lines
    local y = margin_top + spacing
    while y < h - margin_bottom do
        bb:paintRect(margin_left, y, w - margin_left - margin_right, 1, LINE_COLOR)
        y = y + spacing
    end
end

--- Dot grid template.
function Templates.drawDotGrid(bb, w, h, margin_top)
    margin_top = margin_top or 0
    local spacing = Screen:scaleBySize(24)
    local margin_left = Screen:scaleBySize(20)
    local margin_right = Screen:scaleBySize(20)
    local margin_bottom = Screen:scaleBySize(20)
    local dot_size = Screen:scaleBySize(2)

    local y = margin_top + spacing
    while y < h - margin_bottom do
        local x = margin_left + spacing
        while x < w - margin_right do
            bb:paintRect(x, y, dot_size, dot_size, DOT_COLOR)
            x = x + spacing
        end
        y = y + spacing
    end
end

--- Cornell note-taking layout.
-- Left column for cues/questions, right area for notes,
-- bottom section for summary.
function Templates.drawCornell(bb, w, h, margin_top)
    margin_top = margin_top or 0
    local margin = Screen:scaleBySize(15)
    local cue_width = math.floor(w * 0.30)
    local summary_height = math.floor(h * 0.18)
    local line_spacing = Screen:scaleBySize(28)

    -- Vertical divider (cue column)
    bb:paintRect(cue_width, margin_top, 2, h - margin_top - summary_height, LINE_COLOR_DARK)

    -- Horizontal divider (summary area)
    local summary_y = h - summary_height
    bb:paintRect(margin, summary_y, w - margin * 2, 2, LINE_COLOR_DARK)

    -- Light ruled lines in the notes area (right of cue column)
    local y = margin_top + line_spacing
    while y < summary_y - margin do
        bb:paintRect(cue_width + Screen:scaleBySize(10), y,
            w - cue_width - margin - Screen:scaleBySize(10), 1, LINE_COLOR)
        y = y + line_spacing
    end

    -- Light ruled lines in the summary area
    y = summary_y + line_spacing
    while y < h - margin do
        bb:paintRect(margin + Screen:scaleBySize(10), y,
            w - margin * 2 - Screen:scaleBySize(10), 1, LINE_COLOR)
        y = y + line_spacing
    end
end

--- Daily planner layout.
-- Time slots on the left, notes area on the right,
-- todo list at the bottom.
function Templates.drawPlanner(bb, w, h, margin_top)
    margin_top = margin_top or 0
    local margin = Screen:scaleBySize(15)
    local time_col_width = math.floor(w * 0.15)
    local row_height = Screen:scaleBySize(36)
    local notes_start = math.floor(w * 0.65)
    local todo_height = math.floor(h * 0.25)
    local todo_y = h - todo_height

    -- "Schedule" area: time slots on the left, space for events
    local face_size = Screen:scaleBySize(10)

    -- Time labels area divider
    bb:paintRect(time_col_width, margin_top, 1, todo_y - margin_top, LINE_COLOR_DARK)

    -- Horizontal time slot lines
    local y = margin_top + row_height
    local hour = 6  -- Start at 6 AM
    while y < todo_y and hour <= 22 do
        bb:paintRect(margin, y, notes_start - margin - Screen:scaleBySize(10), 1, LINE_COLOR)
        -- Half-hour dashed line
        local half_y = y + math.floor(row_height / 2)
        if half_y < todo_y then
            local dash_x = time_col_width + Screen:scaleBySize(5)
            while dash_x < notes_start - Screen:scaleBySize(15) do
                bb:paintRect(dash_x, half_y, Screen:scaleBySize(6), 1, LINE_COLOR)
                dash_x = dash_x + Screen:scaleBySize(12)
            end
        end
        y = y + row_height
        hour = hour + 1
    end

    -- Notes column divider
    bb:paintRect(notes_start, margin_top, 2, todo_y - margin_top, LINE_COLOR_DARK)

    -- Notes area ruled lines
    local notes_line_y = margin_top + Screen:scaleBySize(30)
    while notes_line_y < todo_y - margin do
        bb:paintRect(notes_start + Screen:scaleBySize(10), notes_line_y,
            w - notes_start - margin - Screen:scaleBySize(10), 1, LINE_COLOR)
        notes_line_y = notes_line_y + Screen:scaleBySize(28)
    end

    -- Todo section divider
    bb:paintRect(margin, todo_y, w - margin * 2, 2, LINE_COLOR_DARK)

    -- Todo checkboxes area
    local todo_line_y = todo_y + Screen:scaleBySize(28)
    local checkbox_size = Screen:scaleBySize(14)
    while todo_line_y < h - margin do
        -- Checkbox outline
        local cb_x = margin + Screen:scaleBySize(8)
        local cb_y = todo_line_y - math.floor(checkbox_size / 2)
        bb:paintRect(cb_x, cb_y, checkbox_size, 1, LINE_COLOR_DARK)
        bb:paintRect(cb_x, cb_y + checkbox_size, checkbox_size, 1, LINE_COLOR_DARK)
        bb:paintRect(cb_x, cb_y, 1, checkbox_size, LINE_COLOR_DARK)
        bb:paintRect(cb_x + checkbox_size, cb_y, 1, checkbox_size + 1, LINE_COLOR_DARK)

        -- Line after checkbox
        bb:paintRect(cb_x + checkbox_size + Screen:scaleBySize(8), todo_line_y,
            w - margin * 2 - checkbox_size - Screen:scaleBySize(20), 1, LINE_COLOR)
        todo_line_y = todo_line_y + Screen:scaleBySize(28)
    end
end

-- ============================================
-- PUBLIC API
-- ============================================

--- Draw a template onto a BlitBuffer.
-- The buffer should already be the correct size and filled with white.
-- @param bb BlitBuffer to draw on
-- @param template_key string template type key
-- @param w number width of the drawing area
-- @param h number height of the drawing area
-- @param margin_top number optional top margin (for toolbar area)
function Templates.draw(bb, template_key, w, h, margin_top)
    local renderers = {
        blank   = Templates.drawBlank,
        grid    = Templates.drawGrid,
        lined   = Templates.drawLined,
        dotgrid = Templates.drawDotGrid,
        cornell = Templates.drawCornell,
        planner = Templates.drawPlanner,
    }

    local renderer = renderers[template_key]
    if renderer then
        renderer(bb, w, h, margin_top)
    else
        logger.warn("CozyHome Templates: unknown template key:", template_key)
    end
end

return Templates
