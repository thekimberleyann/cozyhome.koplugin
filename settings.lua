-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         settings.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-10
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Settings hub screen. Configure Cozy Home
--       preferences, tile visibility, hidden folders,
--       and display options.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - lib/cozyui.lua
--       - lib/database.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
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
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen

local Config = require("config")
local Database = require("lib/database")
local CozyUI = require("lib/cozyui")

local BLACK      = CozyUI.BLACK
local DARK_GRAY  = CozyUI.DARK_GRAY
local GRAY       = CozyUI.GRAY
local LIGHT_GRAY = CozyUI.LIGHT_GRAY
local WHITE      = CozyUI.WHITE
local sp         = CozyUI.sp

-- ─── Categories ───

local CATEGORIES = {
    { key = "homepage",    label = "Homepage",       icon_text = "H", description = "Tiles, layout, stats bar" },

    { key = "highlights",  label = "Highlights",     icon_text = "≡", description = "Flashcard creation, display" },
    { key = "notecards",   label = "Notecards",      icon_text = "C", description = "Review limits, intervals" },
    { key = "focus",       label = "Focus",          icon_text = "◉", description = "Timer durations, sessions" },
    { key = "learnspace",  label = "Learning Space", icon_text = "L", description = "Class defaults" },
    { key = "statusbar",   label = "Status Bar",     icon_text = "=", description = "WiFi, Bluetooth visibility" },
    { key = "advanced",    label = "Advanced",       icon_text = "✦", description = "Debug, about, reset" },
}

-- TODO: Re-add Notebooks settings when pen/stylus input is fixed
-- { key = "notebooks",  label = "Notebooks",  icon_text = "N", description = "Default template, auto-save" },

local PREF = {
    show_stats_bar       = "home_show_stats_bar",
    cards_per_session    = "cards_per_session",
    new_cards_per_day    = "new_cards_per_day",
    show_wifi            = "statusbar_show_wifi",
    show_bluetooth       = "statusbar_show_bluetooth",
    sr_graduating_interval = "sr_graduating_interval",
    sr_easy_interval       = "sr_easy_interval",
    sr_starting_ease       = "sr_starting_ease",
    sr_easy_bonus          = "sr_easy_bonus",
    sr_interval_modifier   = "sr_interval_modifier",
    sr_max_interval        = "sr_max_interval",
    debug_verbose        = "debug_verbose_logging",
    -- Highlights
    hl_batch_flashcards  = "highlights_batch_flashcards",
    hl_show_chapter      = "highlights_show_chapter",
    -- Focus
    focus_work_duration  = "focus_work_duration",
    focus_short_break    = "focus_short_break",
    focus_long_break     = "focus_long_break",
    focus_sessions_before_long = "focus_sessions_before_long",
    focus_sound_enabled  = "focus_sound_enabled",
}

-- TODO: Notebook pref keys preserved for when pen is fixed
-- notebook_template    = "notebook_default_template",
-- notebook_autosave    = "notebook_autosave_seconds",

-- ─── Settings Hub Screen ───

local SettingsScreen = InputContainer:extend{
    name = "cozy_settings",
    ui = nil,
    on_close_callback = nil,
}

local Settings = {}
Settings._current_instance = nil

function SettingsScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = true
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    Database:open()
    Settings._current_instance = self
    self:buildUI()
end

function SettingsScreen:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function SettingsScreen:onCloseWidget()
    Settings._current_instance = nil
    UIManager:setDirty(nil, function() return "full", self.dimen end)
end

function SettingsScreen:onClose()
    UIManager:close(self)
    if self.on_close_callback then UIManager:nextTick(self.on_close_callback) end
    return true
end

function SettingsScreen:paintTo(bb, x, y)
    self.dimen.x = x; self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end

-- ─── Main UI ───

function SettingsScreen:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local settings_screen = self
    local items = {}

    -- Header
    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Settings",
        back_callback = function() settings_screen:onClose() end,
        exit_callback = function() settings_screen:onClose() end,
        show_parent = self,
    }))
    table.insert(items, CozyUI.buildDottedDivider(sw, content_w))
    table.insert(items, sp(10))

    -- Category rows (dynamic height based on content)
    for _, cat in ipairs(CATEGORIES) do
        local row = self:buildCategoryRow(cat, content_w)
        local actual_h = row:getSize().h
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = actual_h}, row,
        })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = 1},
            LineWidget:new{
                dimen = Geom:new{w = content_w, h = 1}, background = LIGHT_GRAY,
            },
        })
    end

    table.insert(items, sp(16))
    table.insert(items, CozyUI.buildFooter(sw, "₊ ⊹ ♡ ⋆ ☆ ⋆ ♡ ⋆ ☆ ⋆ ♡ ⊹ ₊"))

    -- Assemble
    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do table.insert(content, item) end

    local scrollable = ScrollableContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        show_parent = self,
        content,
    }

    self[1] = FrameContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        bordersize = 0, padding = 0, background = WHITE,
        scrollable,
    }
end

function SettingsScreen:buildCategoryRow(cat, content_w, row_h_ignored)
    local settings_screen = self
    local icon_w_sz = 36
    local arrow_w = 30
    local v_pad = 12  -- vertical padding above and below content

    local icon = TextWidget:new{
        face = Font:getFace("tfont", 22), text = cat.icon_text, fgcolor = BLACK,
    }
    local arrow = TextWidget:new{
        face = Font:getFace("cfont", 17), text = "▸", fgcolor = GRAY,
    }

    -- Calculate label width from remaining space, then constrain text
    local label_w = content_w - icon_w_sz - arrow_w - 36

    local label = TextWidget:new{
        face = Font:getFace("cfont", 17), text = cat.label, fgcolor = BLACK,
        max_width = label_w,
    }
    local desc = TextWidget:new{
        face = Font:getFace("smallinfofont", 13), text = cat.description, fgcolor = DARK_GRAY,
        max_width = label_w,
    }

    local label_group = VerticalGroup:new{
        align = "left", label, sp(2), desc,
    }

    -- Measure actual content height and add padding
    local text_h = label:getSize().h + 2 + desc:getSize().h
    local row_h = math.max(48, text_h + v_pad * 2)
    local row_content = HorizontalGroup:new{
        align = "center",
        HorizontalSpan:new{width = 8},
        CenterContainer:new{ dimen = Geom:new{w = icon_w_sz, h = row_h}, icon },
        HorizontalSpan:new{width = 12},
        LeftContainer:new{
            dimen = Geom:new{w = label_w, h = row_h},
            label_group,
        },
        CenterContainer:new{ dimen = Geom:new{w = arrow_w, h = row_h}, arrow },
    }

    local cat_key = cat.key
    local TappableRow = InputContainer:extend{}
    function TappableRow:init()
        self.dimen = Geom:new{w = content_w, h = row_h}
        self.ges_events = {
            TapRow = { GestureRange:new{ ges = "tap", range = self.dimen } },
        }
        self[1] = row_content
    end
    TappableRow.onTapRow = function()
        settings_screen:openCategory(cat_key)
        return true
    end
    return TappableRow:new{}
end

-- ─── Category dispatch ───

function SettingsScreen:openCategory(key)
    if key == "homepage" then self:openHomepageSettings()
    elseif key == "highlights" then self:openHighlightsSettings()
    elseif key == "notecards" then self:openNotecardSettings()
    elseif key == "focus" then self:openFocusSettings()
    elseif key == "learnspace" then self:openLearnSpaceSettings()
    elseif key == "statusbar" then self:openStatusBarSettings()
    elseif key == "advanced" then self:openAdvancedSettings()
    end
end

-- ─── Sub-screen builder ───

function SettingsScreen:showSubScreen(title, rows)
    -- Close any existing sub-screen before opening a new one
    -- (prevents stacking when settings callbacks re-open the same screen)
    if self._current_sub_screen then
        UIManager:close(self._current_sub_screen)
        self._current_sub_screen = nil
    end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local settings_screen = self
    local items = {}

    local function goBack()
        if settings_screen._current_sub_screen then
            UIManager:close(settings_screen._current_sub_screen)
            settings_screen._current_sub_screen = nil
        end
        settings_screen:buildUI()
        UIManager:setDirty(settings_screen, function() return "full", settings_screen.dimen end)
    end
    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = title,
        back_callback = goBack,
        exit_callback = goBack,
        show_parent = settings_screen,
    }))
    table.insert(items, CozyUI.buildDottedDivider(sw, content_w))
    table.insert(items, sp(8))

    for _, row_def in ipairs(rows) do
        if row_def.separator then
            table.insert(items, sp(4))
            table.insert(items, CozyUI.buildSectionDivider(sw, content_w, row_def.label or ""))
            table.insert(items, sp(4))
        else
            local row_widget = self:buildSettingRow(row_def, content_w)
            local actual_h = row_widget:getSize().h
            table.insert(items, CenterContainer:new{
                dimen = Geom:new{w = sw, h = actual_h}, row_widget,
            })
        end
    end

    table.insert(items, sp(16))
    table.insert(items, CozyUI.buildFooter(sw, "₊ ⊹ ♡ ⋆ ☆ ⋆ ♡ ⋆ ☆ ⋆ ♡ ⊹ ₊"))

    local content = VerticalGroup:new{ align = "center" }
    for _, item in ipairs(items) do table.insert(content, item) end

    local SubScreen = InputContainer:extend{}
    function SubScreen:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self.covers_fullscreen = true
        if Device:hasKeys() then
            self.key_events.Close = { { Device.input.group.Back } }
        end
        local scrollable = ScrollableContainer:new{
            dimen = Geom:new{w = sw, h = sh},
            show_parent = self,
            content,
        }
        self[1] = FrameContainer:new{
            dimen = Geom:new{w = sw, h = sh},
            bordersize = 0, padding = 0, background = WHITE,
            scrollable,
        }
    end
    function SubScreen:onShow()
        UIManager:setDirty(self, function() return "full", self.dimen end)
        return true
    end
    function SubScreen:onCloseWidget()
        UIManager:setDirty(nil, function() return "full", self.dimen end)
    end
    function SubScreen:onClose()
        UIManager:close(self)
        settings_screen._current_sub_screen = nil
        settings_screen:buildUI()
        UIManager:setDirty(settings_screen, function() return "full", settings_screen.dimen end)
        return true
    end
    function SubScreen:paintTo(bb, x, y)
        self.dimen.x = x; self.dimen.y = y
        bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
        if self[1] then self[1]:paintTo(bb, x, y) end
    end

    self._current_sub_screen = SubScreen:new{}
    UIManager:show(self._current_sub_screen)
end

function SettingsScreen:buildSettingRow(row_def, content_w, row_h_ignored)
    local v_pad = 10  -- vertical padding above and below content

    local label_text = TextWidget:new{
        face = Font:getFace("cfont", 16), text = row_def.label, fgcolor = BLACK,
    }
    local value_str = ""
    if row_def.value_func then value_str = row_def.value_func() or "" end
    local value_text = TextWidget:new{
        face = Font:getFace("cfont", 15), text = value_str, fgcolor = DARK_GRAY,
    }

    -- Measure value first, give label the remaining space
    local value_w = value_text:getSize().w
    local row_gap = 12  -- gap between label and value
    local label_max_w = math.max(0, content_w - value_w - row_gap)

    -- Apply max_width to label text so it truncates on small screens
    label_text.max_width = label_max_w

    local label_group
    local content_h
    if row_def.description then
        local desc_text = TextWidget:new{
            face = Font:getFace("smallinfofont", 12), text = row_def.description, fgcolor = GRAY,
            max_width = label_max_w,
        }
        label_group = VerticalGroup:new{ align = "left", label_text, sp(2), desc_text }
        content_h = label_text:getSize().h + 2 + desc_text:getSize().h
    else
        label_group = label_text
        content_h = label_text:getSize().h
    end

    -- Use the taller of the label group or the value text, plus padding
    local row_h = math.max(40, math.max(content_h, value_text:getSize().h) + v_pad * 2)

    local row_content = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{w = label_max_w, h = row_h},
            label_group,
        },
        HorizontalSpan:new{width = row_gap},
        RightContainer:new{
            dimen = Geom:new{w = value_w, h = row_h},
            value_text,
        },
    }

    local cb = row_def.callback
    local TappableRow = InputContainer:extend{}
    function TappableRow:init()
        self.dimen = Geom:new{w = content_w, h = row_h}
        self.ges_events = {
            TapSetting = { GestureRange:new{ ges = "tap", range = self.dimen } },
        }
        self[1] = row_content
    end
    TappableRow.onTapSetting = function()
        if cb then cb() end
        return true
    end
    return TappableRow:new{}
end

-- ─── Helpers ───

function SettingsScreen:showCyclePicker(title, options, current_value, on_select)
    local buttons = {}
    for _, opt in ipairs(options) do
        local prefix = opt.value == current_value and "● " or "○ "
        table.insert(buttons, {{
            text = prefix .. opt.label,
            callback = function()
                on_select(opt.value)
                UIManager:close(picker_dialog)
            end,
        }})
    end
    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function() UIManager:close(picker_dialog) end,
    }})

    local ButtonDialog = require("ui/widget/buttondialog")
    picker_dialog = ButtonDialog:new{
        title = "✦ " .. title .. " ✦",
        buttons = buttons,
    }
    UIManager:show(picker_dialog)
end

function SettingsScreen:showNumberInput(title, current_value, min_val, max_val, on_set)
    local input_dialog
    input_dialog = InputDialog:new{
        title = "✦ " .. title,
        input = tostring(current_value),
        input_type = "number",
        buttons = {{
            {
                text = _("Cancel"), id = "close",
                callback = function() UIManager:close(input_dialog) end,
            },
            {
                text = _("Set"), is_enter_default = true,
                callback = function()
                    local val = tonumber(input_dialog:getInputText())
                    if val then
                        if min_val and val < min_val then val = min_val end
                        if max_val and val > max_val then val = max_val end
                        on_set(val)
                    end
                    UIManager:close(input_dialog)
                end,
            },
        }},
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

-- ─── Homepage Settings ───

function SettingsScreen:openHomepageSettings()
    local settings_screen = self
    local rows = {
        {
            label = _("Show stats bar"),
            description = _("Books in progress, cards due at bottom"),
            value_func = function()
                return Database:getPref(PREF.show_stats_bar, "true") == "true" and "On" or "Off"
            end,
            callback = function()
                local current = Database:getPref(PREF.show_stats_bar, "true")
                local new_val = current == "true" and "false" or "true"
                Database:setPref(PREF.show_stats_bar, new_val)
                Config.UI.show_stats_bar = (new_val == "true")
                settings_screen:openHomepageSettings()
            end,
        },
        { separator = true, label = "Tile Visibility" },
    }

    for _, tile_def in ipairs(Config.TILES) do
        local tile_key = tile_def.key
        table.insert(rows, {
            label = "  " .. tile_def.label,
            value_func = function()
                return self:getTileVisible(tile_key) and "Visible" or "Hidden"
            end,
            callback = function()
                self:setTileVisible(tile_key, not self:getTileVisible(tile_key))
                settings_screen:openHomepageSettings()
            end,
        })
    end

    table.insert(rows, { separator = true, label = "" })
    table.insert(rows, {
        label = _("Reset tile order to default"),
        description = _("Restores original tile arrangement"),
        value_func = function() return "" end,
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Reset all tiles to default order and visibility?"),
                ok_text = _("Reset"),
                ok_callback = function()
                    self:resetTileDefaults()
                    UIManager:show(InfoMessage:new{ text = _("Tiles reset to defaults."), timeout = 2 })
                    settings_screen:openHomepageSettings()
                end,
            })
        end,
    })

    self:showSubScreen(_("Homepage"), rows)
end

function SettingsScreen:getTileVisible(tile_key)
    return Database:getPref("tile_visible_" .. tile_key, "true") ~= "false"
end

function SettingsScreen:setTileVisible(tile_key, visible)
    Database:setPref("tile_visible_" .. tile_key, visible and "true" or "false")
end

function SettingsScreen:resetTileDefaults()
    for _, tile_def in ipairs(Config.TILES) do
        Database:setPref("tile_visible_" .. tile_def.key, "true")
    end
    Database:setPref(PREF.show_stats_bar, "true")
    Config.UI.show_stats_bar = true
end

-- ─── Highlights Settings ───

function SettingsScreen:openHighlightsSettings()
    local settings_screen = self
    local rows = {
        {
            label = _("Show chapter names"),
            description = _("Display chapter info with each highlight"),
            value_func = function()
                return Database:getPref(PREF.hl_show_chapter, "true") == "true" and "On" or "Off"
            end,
            callback = function()
                local current = Database:getPref(PREF.hl_show_chapter, "true")
                local new_val = current == "true" and "false" or "true"
                Database:setPref(PREF.hl_show_chapter, new_val)
                settings_screen:openHighlightsSettings()
            end,
        },
        {
            label = _("Batch flashcard creation"),
            description = _("Show button to create cards from highlights"),
            value_func = function()
                return Database:getPref(PREF.hl_batch_flashcards, "true") == "true" and "On" or "Off"
            end,
            callback = function()
                local current = Database:getPref(PREF.hl_batch_flashcards, "true")
                local new_val = current == "true" and "false" or "true"
                Database:setPref(PREF.hl_batch_flashcards, new_val)
                settings_screen:openHighlightsSettings()
            end,
        },
        { separator = true, label = "Diagnostics" },
        {
            label = _("Debug highlights"),
            description = _("Show diagnostic info about highlight loading"),
            value_func = function() return "" end,
            callback = function()
                local HighlightsModule = package.loaded["highlights"]
                if not HighlightsModule then
                    pcall(function() HighlightsModule = require("highlights") end)
                end
                if HighlightsModule and HighlightsModule.showDiagnostic then
                    HighlightsModule.showDiagnostic(settings_screen.ui)
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Highlights module not available."), timeout = 3,
                    })
                end
            end,
        },
    }
    self:showSubScreen(_("Highlights"), rows)
end

-- ─── Focus Settings ───

function SettingsScreen:openFocusSettings()
    local settings_screen = self
    local rows = {
        {
            label = _("Work duration"),
            description = _("Minutes per focus session (5-60)"),
            value_func = function()
                return (Database:getPref(PREF.focus_work_duration, tostring(Config.FOCUS.work_duration)) or "25") .. " min"
            end,
            callback = function()
                local current = tonumber(Database:getPref(PREF.focus_work_duration, tostring(Config.FOCUS.work_duration))) or 25
                self:showNumberInput(_("Work duration (minutes)"), current, 5, 60, function(val)
                    Database:setPref(PREF.focus_work_duration, tostring(val))
                    Config.FOCUS.work_duration = val
                    settings_screen:openFocusSettings()
                end)
            end,
        },
        {
            label = _("Short break"),
            description = _("Minutes for short break (1-15)"),
            value_func = function()
                return (Database:getPref(PREF.focus_short_break, tostring(Config.FOCUS.short_break)) or "5") .. " min"
            end,
            callback = function()
                local current = tonumber(Database:getPref(PREF.focus_short_break, tostring(Config.FOCUS.short_break))) or 5
                self:showNumberInput(_("Short break (minutes)"), current, 1, 15, function(val)
                    Database:setPref(PREF.focus_short_break, tostring(val))
                    Config.FOCUS.short_break = val
                    settings_screen:openFocusSettings()
                end)
            end,
        },
        {
            label = _("Long break"),
            description = _("Minutes for long break (5-30)"),
            value_func = function()
                return (Database:getPref(PREF.focus_long_break, tostring(Config.FOCUS.long_break)) or "15") .. " min"
            end,
            callback = function()
                local current = tonumber(Database:getPref(PREF.focus_long_break, tostring(Config.FOCUS.long_break))) or 15
                self:showNumberInput(_("Long break (minutes)"), current, 5, 30, function(val)
                    Database:setPref(PREF.focus_long_break, tostring(val))
                    Config.FOCUS.long_break = val
                    settings_screen:openFocusSettings()
                end)
            end,
        },
        {
            label = _("Sessions before long break"),
            description = _("Work sessions before a long break (2-8)"),
            value_func = function()
                return Database:getPref(PREF.focus_sessions_before_long, tostring(Config.FOCUS.sessions_before_long_break)) or "4"
            end,
            callback = function()
                local current = tonumber(Database:getPref(PREF.focus_sessions_before_long, tostring(Config.FOCUS.sessions_before_long_break))) or 4
                self:showNumberInput(_("Sessions before long break"), current, 2, 8, function(val)
                    Database:setPref(PREF.focus_sessions_before_long, tostring(val))
                    Config.FOCUS.sessions_before_long_break = val
                    settings_screen:openFocusSettings()
                end)
            end,
        },
        { separator = true, label = "" },
        {
            label = _("Reset focus settings to defaults"),
            value_func = function() return "" end,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Reset focus timer settings to defaults?\n\n25 min work, 5 min short break,\n15 min long break, every 4 sessions."),
                    ok_text = _("Reset"),
                    ok_callback = function()
                        Database:setPref(PREF.focus_work_duration, "25")
                        Database:setPref(PREF.focus_short_break, "5")
                        Database:setPref(PREF.focus_long_break, "15")
                        Database:setPref(PREF.focus_sessions_before_long, "4")
                        Config.FOCUS.work_duration = 25
                        Config.FOCUS.short_break = 5
                        Config.FOCUS.long_break = 15
                        Config.FOCUS.sessions_before_long_break = 4
                        UIManager:show(InfoMessage:new{ text = _("Focus settings reset."), timeout = 2 })
                        settings_screen:openFocusSettings()
                    end,
                })
            end,
        },
    }
    self:showSubScreen(_("Focus"), rows)
end

-- ─── Learning Space Settings ───

function SettingsScreen:openLearnSpaceSettings()
    local settings_screen = self
    local rows = {
        {
            label = _("Learning spaces summary"),
            description = _("Total classes created"),
            value_func = function() return tostring(#Database:getClasses()) .. " classes" end,
            callback = function() end,
        },
        { separator = true, label = "Danger Zone" },
        {
            label = _("Delete all classes"),
            description = _("Remove all learning space classes and their book links"),
            value_func = function() return "" end,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Delete ALL learning space classes?\n\nBooks are not affected."),
                    ok_text = _("Delete All"),
                    ok_callback = function()
                        for _, cls in ipairs(Database:getClasses()) do Database:deleteClass(cls.id) end
                        UIManager:show(InfoMessage:new{ text = _("All classes deleted."), timeout = 2 })
                        settings_screen:openLearnSpaceSettings()
                    end,
                })
            end,
        },
    }
    self:showSubScreen(_("Learning Space"), rows)
end

-- ─── Notecard Settings ───

function SettingsScreen:openNotecardSettings()
    local settings_screen = self
    local rows = {
        {
            label = _("Cards per review session"),
            description = _("Maximum cards shown per review (5-100)"),
            value_func = function() return Database:getPref(PREF.cards_per_session, "20") end,
            callback = function()
                self:showNumberInput(_("Cards per session"), tonumber(Database:getPref(PREF.cards_per_session, "20")) or 20, 5, 100, function(val)
                    Database:setPref(PREF.cards_per_session, tostring(val))
                    settings_screen:openNotecardSettings()
                end)
            end,
        },
        {
            label = _("New cards per day"),
            description = _("Maximum new cards introduced daily (1-50)"),
            value_func = function() return Database:getPref(PREF.new_cards_per_day, "10") end,
            callback = function()
                self:showNumberInput(_("New cards per day"), tonumber(Database:getPref(PREF.new_cards_per_day, "10")) or 10, 1, 50, function(val)
                    Database:setPref(PREF.new_cards_per_day, tostring(val))
                    settings_screen:openNotecardSettings()
                end)
            end,
        },
        { separator = true, label = "Spaced Repetition" },
        {
            label = _("Graduating interval"), description = _("Days to move from learning to review (1-30)"),
            value_func = function() return Database:getPref(PREF.sr_graduating_interval, "1") .. "d" end,
            callback = function()
                self:showNumberInput(_("Graduating interval (days)"), tonumber(Database:getPref(PREF.sr_graduating_interval, "1")) or 1, 1, 30, function(val)
                    Database:setPref(PREF.sr_graduating_interval, tostring(val)); settings_screen:openNotecardSettings()
                end)
            end,
        },
        {
            label = _("Easy interval"), description = _("Days for cards rated 'Easy' (1-60)"),
            value_func = function() return Database:getPref(PREF.sr_easy_interval, "4") .. "d" end,
            callback = function()
                self:showNumberInput(_("Easy interval (days)"), tonumber(Database:getPref(PREF.sr_easy_interval, "4")) or 4, 1, 60, function(val)
                    Database:setPref(PREF.sr_easy_interval, tostring(val)); settings_screen:openNotecardSettings()
                end)
            end,
        },
        {
            label = _("Starting ease"), description = _("Initial ease factor (130-300)"),
            value_func = function() return Database:getPref(PREF.sr_starting_ease, "250") .. "%" end,
            callback = function()
                self:showNumberInput(_("Starting ease (%)"), tonumber(Database:getPref(PREF.sr_starting_ease, "250")) or 250, 130, 300, function(val)
                    Database:setPref(PREF.sr_starting_ease, tostring(val)); settings_screen:openNotecardSettings()
                end)
            end,
        },
        {
            label = _("Easy bonus"), description = _("Multiplier for 'Easy' (100-200)"),
            value_func = function() return Database:getPref(PREF.sr_easy_bonus, "130") .. "%" end,
            callback = function()
                self:showNumberInput(_("Easy bonus (%)"), tonumber(Database:getPref(PREF.sr_easy_bonus, "130")) or 130, 100, 200, function(val)
                    Database:setPref(PREF.sr_easy_bonus, tostring(val)); settings_screen:openNotecardSettings()
                end)
            end,
        },
        {
            label = _("Interval modifier"), description = _("Global interval multiplier (50-200)"),
            value_func = function() return Database:getPref(PREF.sr_interval_modifier, "100") .. "%" end,
            callback = function()
                self:showNumberInput(_("Interval modifier (%)"), tonumber(Database:getPref(PREF.sr_interval_modifier, "100")) or 100, 50, 200, function(val)
                    Database:setPref(PREF.sr_interval_modifier, tostring(val)); settings_screen:openNotecardSettings()
                end)
            end,
        },
        {
            label = _("Maximum interval"), description = _("Max review interval in days (30-3650)"),
            value_func = function() return Database:getPref(PREF.sr_max_interval, "365") .. "d" end,
            callback = function()
                self:showNumberInput(_("Maximum interval (days)"), tonumber(Database:getPref(PREF.sr_max_interval, "365")) or 365, 30, 3650, function(val)
                    Database:setPref(PREF.sr_max_interval, tostring(val)); settings_screen:openNotecardSettings()
                end)
            end,
        },
        { separator = true, label = "" },
        {
            label = _("Reset SR settings to defaults"),
            value_func = function() return "" end,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Reset all spaced repetition settings to defaults?"),
                    ok_text = _("Reset"),
                    ok_callback = function()
                        Database:setPref(PREF.sr_graduating_interval, "1")
                        Database:setPref(PREF.sr_easy_interval, "4")
                        Database:setPref(PREF.sr_starting_ease, "250")
                        Database:setPref(PREF.sr_easy_bonus, "130")
                        Database:setPref(PREF.sr_interval_modifier, "100")
                        Database:setPref(PREF.sr_max_interval, "365")
                        UIManager:show(InfoMessage:new{ text = _("SR settings reset."), timeout = 2 })
                        settings_screen:openNotecardSettings()
                    end,
                })
            end,
        },
    }
    self:showSubScreen(_("Notecards"), rows)
end

-- ─── Status Bar Settings ───

function SettingsScreen:openStatusBarSettings()
    local settings_screen = self
    local rows = {
        {
            label = _("Show WiFi indicator"),
            description = _("Display WiFi status in the status bar"),
            value_func = function() return Database:getPref(PREF.show_wifi, "false") == "true" and "On" or "Off" end,
            callback = function()
                local current = Database:getPref(PREF.show_wifi, "false")
                Database:setPref(PREF.show_wifi, current == "true" and "false" or "true")
                settings_screen:openStatusBarSettings()
            end,
        },
        {
            label = _("Show Bluetooth indicator"),
            description = _("Display Bluetooth status in the status bar"),
            value_func = function() return Database:getPref(PREF.show_bluetooth, "false") == "true" and "On" or "Off" end,
            callback = function()
                local current = Database:getPref(PREF.show_bluetooth, "false")
                Database:setPref(PREF.show_bluetooth, current == "true" and "false" or "true")
                settings_screen:openStatusBarSettings()
            end,
        },
    }
    self:showSubScreen(_("Status Bar"), rows)
end

-- ─── Advanced Settings ───

function SettingsScreen:openAdvancedSettings()
    local settings_screen = self
    local rows = {
        { separator = true, label = "Debug" },
        {
            label = _("Verbose logging"),
            description = _("Enable detailed debug output"),
            value_func = function()
                return Database:getPref(PREF.debug_verbose, "false") == "true" and "On" or "Off"
            end,
            callback = function()
                local current = Database:getPref(PREF.debug_verbose, "false")
                local new_val = current == "true" and "false" or "true"
                Database:setPref(PREF.debug_verbose, new_val)
                Config.DEBUG.verbose_logging = (new_val == "true")
                settings_screen:openAdvancedSettings()
            end,
        },
        { separator = true, label = "Reset" },
        {
            label = _("Reset all Cozy Home settings"),
            description = _("Clear all preferences to factory defaults"),
            value_func = function() return "" end,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Reset ALL settings to defaults?\n\nClasses, cards, and saves are not affected."),
                    ok_text = _("Reset"),
                    ok_callback = function()
                        local conn = Database:getConn()
                        if conn then pcall(function() conn:exec("DELETE FROM preferences") end) end
                        Config.UI.show_stats_bar = true
                        Config.DEBUG.verbose_logging = false
                        Config.FOCUS.work_duration = 25
                        Config.FOCUS.short_break = 5
                        Config.FOCUS.long_break = 15
                        Config.FOCUS.sessions_before_long_break = 4
                        UIManager:show(InfoMessage:new{ text = _("All settings reset."), timeout = 2 })
                        settings_screen:openAdvancedSettings()
                    end,
                })
            end,
        },
        { separator = true, label = "About" },
        {
            label = _("About Cozy Home"),
            value_func = function() return "v" .. Config.PLUGIN.version end,
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = "☕ " .. Config.PLUGIN.human_name
                        .. " v" .. Config.PLUGIN.version
                        .. "\n\n" .. Config.PLUGIN.description
                        .. "\n\nDesigned for Kobo e-ink devices."
                        .. "\n\nModules: Home, Highlights,"
                        .. "\nLearning Spaces, Notecards, Focus, Settings",
                })
            end,
        },
    }
    self:showSubScreen(_("Advanced"), rows)
end

-- TODO: Re-add Notebook settings when pen/stylus input is fixed
-- function SettingsScreen:openNotebookSettings() ... end

-- ─── Public API ───

function Settings.show(ui, on_close_callback)
    if Settings._current_instance then
        UIManager:close(Settings._current_instance)
        Settings._current_instance = nil
    end
    UIManager:show(SettingsScreen:new{
        ui = ui, on_close_callback = on_close_callback,
    })
end

function Settings.isOpen() return Settings._current_instance ~= nil end

function Settings.close()
    if Settings._current_instance then
        UIManager:close(Settings._current_instance)
        Settings._current_instance = nil
    end
end

return Settings
