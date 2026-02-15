-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         lib/cozyui.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-07
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Cozy Design System v0.20.0 shared helpers.
--       Provides the standard visual building blocks
--       (headers, dividers, stat rows, rounded boxes,
--       buttons, footers) used by all Cozy Home screens.
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
local VerticalGroup = require("ui/widget/verticalgroup")
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
-- When a focus timer is active, shows:  [< Back]  ☕ Title  ⏱ MM:SS  [✕]
-- @param opts table with:
--   sw           number   screen width
--   title        string   title text (will be prefixed with ☕)
--   back_callback  function  called when back button is tapped
--   exit_callback  function  called when ✕ is tapped
--   right_text     string    (optional) custom right button text, default "✕"
--   right_callback function  (optional) override right button callback
--   show_parent    widget    (optional) parent for button repaint
--   no_prefix      boolean   (optional) if true, don't prepend ☕ to title
--   hide_timer     boolean   (optional) if true, never show the focus timer
function CozyUI.buildScreenHeader(opts)
    local sw = opts.sw or Screen:getWidth()
    local pad = opts.pad or 15
    local content_w = sw - pad * 2
    local bar_h = Screen:scaleBySize(opts.bar_h or 52)

    local back_btn = Button:new{
        text = _("< Back"),
        callback = opts.back_callback,
        bordersize = 0,
        text_font_size = 16,
        padding = 8,
        padding_h = 12,
        show_parent = opts.show_parent,
    }

    local title_str = opts.no_prefix and _(opts.title) or ("☕ " .. _(opts.title))
    local title_widget = TextWidget:new{
        face = Font:getFace("tfont", 20),
        text = title_str,
        fgcolor = CozyUI.BLACK,
        bold = true,
    }

    -- Build right-side group: optional timer + close button
    local right_text = opts.right_text or "✕"
    local right_cb = opts.right_callback or opts.exit_callback
    local exit_btn = Button:new{
        text = right_text,
        callback = right_cb,
        bordersize = 0,
        text_font_size = 22,
        padding = 10,
        padding_h = 16,
        margin = 0,
        show_parent = opts.show_parent,
    }

    -- Check if focus timer is active (via the global provider)
    local timer_widget = nil
    if not opts.hide_timer and CozyUI.getTimerDisplay then
        local timer_info = CozyUI.getTimerDisplay()
        if timer_info and timer_info.text then
            -- Show clock symbol + countdown: ◷ 23:41
            timer_widget = TextWidget:new{
                face = Font:getFace("cfont", 14),
                text = "◷ " .. timer_info.text,
                fgcolor = CozyUI.DARK_GRAY,
            }
        end
    end

    -- Assemble the right side: [timer]  [✕]
    local right_group
    if timer_widget then
        right_group = HorizontalGroup:new{
            align = "center",
            timer_widget,
            HorizontalSpan:new{width = 8},
            exit_btn,
        }
    else
        right_group = exit_btn
    end

    -- Measure buttons first, give title the remaining space
    local back_w = back_btn:getSize().w
    local right_w = right_group:getSize().w
    local title_gap = 8  -- minimum gap between title and buttons
    local title_max_w = math.max(0, content_w - back_w - right_w - title_gap * 2)
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
            dimen = Geom:new{w = right_w, h = bar_h},
            right_group,
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
        text = _(tagline or "cozy home"),
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

--- Global timer text provider.
-- Set this to a function that returns {text="MM:SS", label="Focus"} or nil.
-- FocusMode sets this on load so all screens can display the countdown.
CozyUI.getTimerDisplay = nil

--- Compact stat block: label above, value below.
-- No dots, no horizontal cramming. Fits any screen width.
-- @param sw number: screen width
-- @param content_w number: content area width
-- @param label string: small gray label text
-- @param value string: larger black value text
function CozyUI.buildStatBlock(sw, content_w, label, value)
    local label_widget = TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = label,
        fgcolor = CozyUI.GRAY,
        max_width = content_w,
    }
    local value_widget = TextWidget:new{
        face = Font:getFace("cfont", 18),
        text = tostring(value),
        fgcolor = CozyUI.BLACK,
        max_width = content_w,
    }
    local group = VerticalGroup:new{
        align = "left",
        label_widget,
        VerticalSpan:new{width = 2},
        value_widget,
    }
    local h = label_widget:getSize().h + 2 + value_widget:getSize().h + 6
    return CenterContainer:new{
        dimen = Geom:new{w = sw, h = h},
        LeftContainer:new{
            dimen = Geom:new{w = content_w, h = h},
            FrameContainer:new{
                bordersize = 0, padding = 0,
                padding_left = 4, padding_bottom = 6,
                background = CozyUI.WHITE,
                group,
            },
        },
    }
end

--- Grid of stat blocks: 2 columns side by side.
-- Each item is {label, value}.
-- @param sw number: screen width
-- @param content_w number: content area width
-- @param left table: {label, value}
-- @param right table: {label, value}
function CozyUI.buildStatPair(sw, content_w, left, right)
    local col_w = math.floor(content_w * 0.48)

    local function buildCol(data)
        local lbl = TextWidget:new{
            face = Font:getFace("smallinfofont"),
            text = data[1],
            fgcolor = CozyUI.GRAY,
            max_width = col_w,
        }
        local val = TextWidget:new{
            face = Font:getFace("cfont", 18),
            text = tostring(data[2]),
            fgcolor = CozyUI.BLACK,
            max_width = col_w,
        }
        return LeftContainer:new{
            dimen = Geom:new{w = col_w, h = lbl:getSize().h + 2 + val:getSize().h},
            VerticalGroup:new{
                align = "left",
                lbl,
                VerticalSpan:new{width = 2},
                val,
            },
        }
    end

    local left_col = buildCol(left)
    local right_col = buildCol(right)
    local row_h = math.max(left_col:getSize().h, right_col:getSize().h) + 6

    return CenterContainer:new{
        dimen = Geom:new{w = sw, h = row_h},
        HorizontalGroup:new{
            align = "top",
            left_col,
            HorizontalSpan:new{width = math.floor(content_w * 0.04)},
            right_col,
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

-- ─── Input sanitization helper ───
--- Sanitizes user-provided text input: trims whitespace, removes
-- control characters, and enforces a maximum length.
-- @param text string|nil: Raw input text
-- @param max_len number: Maximum allowed length
-- @param allow_newlines boolean|nil: If true, preserves newlines
-- @return string: Sanitized text (empty string if input was nil/invalid)
function CozyUI.sanitizeInput(text, max_len, allow_newlines)
    if not text or type(text) ~= "string" then return "" end

    -- Trim whitespace
    text = text:match("^%s*(.-)%s*$") or ""

    -- Remove control characters (except newlines if allowed)
    if not allow_newlines then
        text = text:gsub("%c", "")
    else
        text = text:gsub("[%c\r]", function(c)
            return (c == "\n") and c or ""
        end)
    end

    -- Enforce length
    if max_len and #text > max_len then
        text = text:sub(1, max_len)
    end

    return text
end

return CozyUI
