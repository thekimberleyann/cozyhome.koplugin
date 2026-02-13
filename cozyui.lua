-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         cozyui.lua (root copy)
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-07
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Backward-compatibility copy of lib/cozyui.lua.
--       The canonical version lives at lib/cozyui.lua.
--       Provides the standard visual building blocks
--       used by all Cozy Home screens.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       (none — standalone UI helper module)
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Screen = require("device").screen

local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalSpan = require("ui/widget/verticalspan")

local _ = require("gettext")

local CozyUI = {}

-- ─── Grayscale palette ───
CozyUI.BLACK      = Blitbuffer.COLOR_BLACK
CozyUI.DARK_GRAY  = Blitbuffer.COLOR_DARK_GRAY
CozyUI.GRAY       = Blitbuffer.COLOR_GRAY
CozyUI.LIGHT_GRAY = Blitbuffer.gray(0.85)
CozyUI.WHITE      = Blitbuffer.COLOR_WHITE

-- Shorthand vertical spacer
function CozyUI.sp(h) return VerticalSpan:new{width = h} end

-- Truncate text to a max length
function CozyUI.truncateText(text, max_length)
    max_length = max_length or 200
    if not text or type(text) ~= "string" then return "" end
    if #text <= max_length then return text end
    return text:sub(1, max_length - 3) .. "..."
end

-- ☕ Title + ✕ close header (legacy — prefer buildScreenHeader for new screens)
function CozyUI.buildCozyHeader(sw, content_w, title_text, close_callback)
    local title_widget = TextWidget:new{
        face = Font:getFace("tfont", 22),
        text = "☕ " .. _(title_text),
        fgcolor = CozyUI.BLACK,
    }
    local close_btn = Button:new{
        text = "✕",
        callback = close_callback,
        bordersize = 0, text_font_size = 20, margin = 0, padding = 0,
    }
    -- Measure close button, give title the rest
    local close_w = close_btn:getSize().w
    local title_gap = 8
    local title_max_w = math.max(0, content_w - close_w - title_gap)
    title_widget.max_width = title_max_w
    local bar_h = math.max(title_widget:getSize().h, close_btn:getSize().h) + 6

    local bar = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{w = title_max_w, h = bar_h},
            title_widget,
        },
        HorizontalSpan:new{width = title_gap},
        CenterContainer:new{
            dimen = Geom:new{w = close_w, h = bar_h},
            close_btn,
        },
    }
    return CenterContainer:new{
        dimen = Geom:new{w = sw, h = bar_h},
        bar,
    }
end

--- Standard 3-column screen header: [< Back]  ☕ Title  [✕]
-- @param opts table with:
--   sw           number   screen width
--   title        string   title text (will be prefixed with ☕)
--   back_callback  function  called when back button is tapped
--   exit_callback  function  called when ✕ is tapped
--   right_text     string    (optional) custom right button text, default "✕"
--   right_callback function  (optional) override right button callback
--   show_parent    widget    (optional) parent for button repaint
--   no_prefix      boolean   (optional) if true, don't prepend ☕ to title
function CozyUI.buildScreenHeader(opts)
    local sw = opts.sw or Screen:getWidth()
    local pad = opts.pad or 15
    local content_w = sw - pad * 2
    local bar_h = Screen:scaleBySize(opts.bar_h or 44)

    local back_btn = Button:new{
        text = _("< Back"),
        callback = opts.back_callback,
        bordersize = 0,
        text_font_size = 14,
        padding = 4,
        show_parent = opts.show_parent,
    }

    local title_str = opts.no_prefix and _(opts.title) or ("☕ " .. _(opts.title))
    local title_widget = TextWidget:new{
        face = Font:getFace("tfont", 20),
        text = title_str,
        fgcolor = CozyUI.BLACK,
        bold = true,
    }

    local right_text = opts.right_text or "✕"
    local right_cb = opts.right_callback or opts.exit_callback
    local exit_btn = Button:new{
        text = right_text,
        callback = right_cb,
        bordersize = 0,
        text_font_size = 14,
        padding = 4,
        show_parent = opts.show_parent,
    }

    -- Measure buttons first, give title the remaining space
    local back_w = back_btn:getSize().w
    local exit_w = exit_btn:getSize().w
    local title_gap = 8  -- minimum gap between title and buttons
    local title_max_w = math.max(0, content_w - back_w - exit_w - title_gap * 2)
    title_widget.max_width = title_max_w

    local bar = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{w = back_w, h = bar_h},
            back_btn,
        },
        HorizontalSpan:new{width = title_gap},
        CenterContainer:new{
            dimen = Geom:new{w = title_max_w, h = bar_h},
            title_widget,
        },
        HorizontalSpan:new{width = title_gap},
        CenterContainer:new{
            dimen = Geom:new{w = exit_w, h = bar_h},
            exit_btn,
        },
    }

    return FrameContainer:new{
        dimen = Geom:new{w = sw, h = bar_h},
        bordersize = 0,
        padding = 0,
        padding_left = pad,
        padding_right = pad,
        background = CozyUI.WHITE,
        bar,
    }
end

-- ···••••·····  dotted divider under headers
function CozyUI.buildDottedDivider(sw, content_w)
    local dot_count = math.floor(content_w / 8)
    local center = math.floor(dot_count / 2)
    local dot_chars = {}
    for i = 1, dot_count do
        if i >= center - 2 and i <= center + 2 then
            table.insert(dot_chars, "•")
        else
            table.insert(dot_chars, "·")
        end
    end
    local dot_widget = TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = table.concat(dot_chars),
        fgcolor = CozyUI.LIGHT_GRAY,
    }
    return CenterContainer:new{
        dimen = Geom:new{w = sw, h = dot_widget:getSize().h},
        dot_widget,
    }
end

-- ── ✦ Label ✦ ──  section divider
function CozyUI.buildSectionDivider(sw, content_w, label)
    local label_widget = TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = "✦ " .. label .. " ✦",
        fgcolor = CozyUI.GRAY,
    }
    local label_w = label_widget:getSize().w
    local line_w = math.floor((content_w - label_w - 20) / 2)
    if line_w < 10 then line_w = 10 end
    return CenterContainer:new{
        dimen = Geom:new{w = sw, h = label_widget:getSize().h + 4},
        HorizontalGroup:new{
            align = "center",
            LineWidget:new{dimen = Geom:new{w = line_w, h = 1}, background = CozyUI.LIGHT_GRAY},
            HorizontalSpan:new{width = 10},
            label_widget,
            HorizontalSpan:new{width = 10},
            LineWidget:new{dimen = Geom:new{w = line_w, h = 1}, background = CozyUI.LIGHT_GRAY},
        },
    }
end

-- Label ····· Value  stat row
-- Clamps label+value so they always fit within content_w.
function CozyUI.buildStatRow(sw, content_w, label, value)
    local face = Font:getFace("cfont", 18)
    local gap = 20  -- minimum space for dots + two 8px spans
    -- Reserve at most 40% for label, 55% for value (5% for dots minimum)
    local max_label_w = math.floor(content_w * 0.40)
    local max_value_w = math.floor(content_w * 0.55)

    local label_widget = TextWidget:new{
        face = face,
        text = label,
        fgcolor = CozyUI.BLACK,
        max_width = max_label_w,
    }
    local value_widget = TextWidget:new{
        face = face,
        text = tostring(value),
        fgcolor = CozyUI.BLACK,
        max_width = max_value_w,
    }
    local used_w = label_widget:getSize().w + value_widget:getSize().w + gap
    local dot_w = content_w - used_w
    local dot_count = math.max(3, math.floor(dot_w / 6))
    local dots_widget = TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = string.rep("·", dot_count),
        fgcolor = CozyUI.LIGHT_GRAY,
    }
    return CenterContainer:new{
        dimen = Geom:new{w = sw, h = label_widget:getSize().h + 4},
        HorizontalGroup:new{
            align = "center",
            label_widget,
            HorizontalSpan:new{width = 8},
            dots_widget,
            HorizontalSpan:new{width = 8},
            value_widget,
        },
    }
end

-- Rounded box container
function CozyUI.buildRoundedBox(inner_widget)
    return FrameContainer:new{
        padding = 14,
        margin = 0,
        bordersize = 1,
        radius = 10,
        color = CozyUI.GRAY,
        background = CozyUI.WHITE,
        inner_widget,
    }
end

-- Footer tagline
function CozyUI.buildFooter(sw, tagline)
    local widget = TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = _(tagline or "kozy home"),
        fgcolor = CozyUI.GRAY,
    }
    return CenterContainer:new{
        dimen = Geom:new{w = sw, h = widget:getSize().h},
        widget,
    }
end

-- Standard back button (left-aligned, borderless)
function CozyUI.buildBackButton(text, callback, show_parent)
    return Button:new{
        text = _(text or "< Back"),
        callback = callback,
        bordersize = 0,
        text_font_size = 16,
        padding = 4,
        show_parent = show_parent,
    }
end

-- Primary action button (bordered, bold)
function CozyUI.buildPrimaryButton(content_w, text, callback, show_parent)
    local btn_w = math.floor(content_w * 0.92)
    return CenterContainer:new{
        dimen = Geom:new{w = content_w, h = 44},
        Button:new{
            text = _(text),
            callback = callback,
            width = btn_w,
            bordersize = 2,
            radius = 8,
            text_font_bold = true,
            padding_v = 10,
            show_parent = show_parent,
        },
    }
end

-- Status icons for card/item lists
CozyUI.STATUS = {
    NEW       = "○",
    LEARNING  = "◐",
    MASTERED  = "●",
    SUSPENDED = "◦",
}

return CozyUI
