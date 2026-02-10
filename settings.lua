-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         settings.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-09
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
local OverlapGroup = require("ui/widget/overlapgroup")
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
    { key = "homepage",   label = "Homepage",       icon_text = "H", description = "Tiles, layout, stats bar" },
    { key = "library",    label = "Library",         icon_text = "B", description = "View mode, sorting, hidden folders" },
    { key = "notebooks",  label = "Notebooks",       icon_text = "N", description = "Default template, auto-save" },
    { key = "learnspace", label = "Learning Space",  icon_text = "L", description = "Class defaults" },
    { key = "notecards",  label = "Notecards",       icon_text = "C", description = "Review limits, intervals" },
    { key = "statusbar",  label = "Status Bar",      icon_text = "=", description = "WiFi, Bluetooth visibility" },
    { key = "advanced",   label = "Advanced",        icon_text = "✦", description = "Debug, about, reset" },
}

local PREF = {
    show_stats_bar       = "home_show_stats_bar",
    library_view_mode    = "library_view_mode",
    library_sort_mode    = "library_sort_mode",
    notebook_template    = "notebook_default_template",
    notebook_autosave    = "notebook_autosave_seconds",
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
}

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

    -- Category rows
    local row_h = 60
    for _, cat in ipairs(CATEGORIES) do
        local row = self:buildCategoryRow(cat, content_w, row_h)
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = row_h}, row,
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

function SettingsScreen:buildCategoryRow(cat, content_w, row_h)
    local settings_screen = self
    local icon_w_sz = 36
    local arrow_w = 30

    local icon = TextWidget:new{
        face = Font:getFace("tfont", 22), text = cat.icon_text, fgcolor = BLACK,
    }
    local label = TextWidget:new{
        face = Font:getFace("cfont", 17), text = cat.label, fgcolor = BLACK,
    }
    local desc = TextWidget:new{
        face = Font:getFace("smallinfofont", 13), text = cat.description, fgcolor = DARK_GRAY,
    }
    local arrow = TextWidget:new{
        face = Font:getFace("cfont", 17), text = "▸", fgcolor = GRAY,
    }

    local label_group = VerticalGroup:new{
        align = "left", label, sp(2), desc,
    }

    local label_w = content_w - icon_w_sz - arrow_w - 36
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
    elseif key == "library" then self:openLibrarySettings()
    elseif key == "notebooks" then self:openNotebookSettings()
    elseif key == "learnspace" then self:openLearnSpaceSettings()
    elseif key == "notecards" then self:openNotecardSettings()
    elseif key == "statusbar" then self:openStatusBarSettings()
    elseif key == "advanced" then self:openAdvancedSettings()
    end
end

-- ─── Sub-screen builder ───

function SettingsScreen:showSubScreen(title, rows)
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local settings_screen = self
    local items = {}

    local function goBack()
        UIManager:close(sub_screen)
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

    local row_h = 52
    for _, row_def in ipairs(rows) do
        if row_def.separator then
            table.insert(items, sp(4))
            table.insert(items, CozyUI.buildSectionDivider(sw, content_w, row_def.label or ""))
            table.insert(items, sp(4))
        else
            local row_widget = self:buildSettingRow(row_def, content_w, row_h)
            table.insert(items, CenterContainer:new{
                dimen = Geom:new{w = sw, h = row_h}, row_widget,
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
        settings_screen:buildUI()
        UIManager:setDirty(settings_screen, function() return "full", settings_screen.dimen end)
        return true
    end
    function SubScreen:paintTo(bb, x, y)
        self.dimen.x = x; self.dimen.y = y
        bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
        if self[1] then self[1]:paintTo(bb, x, y) end
    end

    sub_screen = SubScreen:new{}
    UIManager:show(sub_screen)
end

function SettingsScreen:buildSettingRow(row_def, content_w, row_h)
    local label_text = TextWidget:new{
        face = Font:getFace("cfont", 16), text = row_def.label, fgcolor = BLACK,
    }
    local value_str = ""
    if row_def.value_func then value_str = row_def.value_func() or "" end
    local value_text = TextWidget:new{
        face = Font:getFace("cfont", 15), text = value_str, fgcolor = DARK_GRAY,
    }

    local label_group
    if row_def.description then
        local desc_text = TextWidget:new{
            face = Font:getFace("smallinfofont", 12), text = row_def.description, fgcolor = GRAY,
        }
        label_group = VerticalGroup:new{ align = "left", label_text, sp(2), desc_text }
    else
        label_group = label_text
    end

    local row_content = OverlapGroup:new{
        dimen = Geom:new{w = content_w, h = row_h},
        LeftContainer:new{
            dimen = Geom:new{w = content_w * 0.65, h = row_h},
            label_group,
        },
        RightContainer:new{
            dimen = Geom:new{w = content_w, h = row_h},
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

-- ─── Library Settings ───

function SettingsScreen:openLibrarySettings()
    local settings_screen = self
    local view_modes = {
        { value = "list", label = "List (text only)" },
        { value = "list_covers", label = "List with covers" },
        { value = "gallery", label = "Cover gallery" },
    }
    local sort_modes = {
        { value = "title", label = "By title" },
        { value = "author", label = "By author" },
        { value = "recent", label = "By recent" },
    }

    local function findLabel(options, val)
        for _, m in ipairs(options) do if m.value == val then return m.label end end
        return val
    end

    local rows = {
        {
            label = _("Default view mode"),
            description = _("How books are displayed when opening Library"),
            value_func = function() return findLabel(view_modes, Database:getPref(PREF.library_view_mode, "list")) end,
            callback = function()
                self:showCyclePicker(_("Default View Mode"), view_modes, Database:getPref(PREF.library_view_mode, "list"), function(val)
                    Database:setPref(PREF.library_view_mode, val)
                    settings_screen:openLibrarySettings()
                end)
            end,
        },
        {
            label = _("Default sort order"),
            description = _("How books are sorted when opening Library"),
            value_func = function() return findLabel(sort_modes, Database:getPref(PREF.library_sort_mode, "title")) end,
            callback = function()
                self:showCyclePicker(_("Default Sort Order"), sort_modes, Database:getPref(PREF.library_sort_mode, "title"), function(val)
                    Database:setPref(PREF.library_sort_mode, val)
                    settings_screen:openLibrarySettings()
                end)
            end,
        },
        { separator = true, label = "Folders" },
        {
            label = _("Manage hidden folders"),
            description = _("Folders excluded from library scan"),
            value_func = function()
                local hidden = Database:getHiddenFolders()
                local count = 0
                for _ in pairs(hidden) do count = count + 1 end
                return count .. " hidden"
            end,
            callback = function() settings_screen:showHiddenFolderManager() end,
        },
    }
    self:showSubScreen(_("Library"), rows)
end

function SettingsScreen:showHiddenFolderManager()
    local hidden = Database:getHiddenFolders()
    local paths = {}
    for path in pairs(hidden) do table.insert(paths, path) end
    table.sort(paths)

    if #paths == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No hidden folders."), timeout = 5,
        })
        return
    end

    local buttons = {}
    for _, path in ipairs(paths) do
        local display = path
        if #display > 40 then display = "..." .. display:sub(-37) end
        local p = path
        table.insert(buttons, {{
            text = "○ " .. display,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = _("Unhide this folder?\n\n") .. p,
                    ok_text = _("Unhide"),
                    ok_callback = function()
                        Database:removeHiddenFolder(p)
                        UIManager:close(folder_dialog)
                        self:showHiddenFolderManager()
                    end,
                })
            end,
        }})
    end
    table.insert(buttons, {{ text = _("Done"), callback = function() UIManager:close(folder_dialog) end }})

    local ButtonDialog = require("ui/widget/buttondialog")
    folder_dialog = ButtonDialog:new{
        title = _("✦ Hidden Folders ✦"),
        buttons = buttons,
    }
    UIManager:show(folder_dialog)
end

-- ─── Notebook Settings ───

function SettingsScreen:openNotebookSettings()
    local settings_screen = self
    local templates = {
        { value = "blank", label = "Blank" }, { value = "grid", label = "Grid" },
        { value = "lined", label = "Lined" }, { value = "dotgrid", label = "Dot Grid" },
        { value = "cornell", label = "Cornell" }, { value = "planner", label = "Planner" },
    }
    local function templateLabel(val)
        for _, t in ipairs(templates) do if t.value == val then return t.label end end
        return val
    end

    local rows = {
        {
            label = _("Default page template"),
            description = _("Template used when creating new notebooks"),
            value_func = function() return templateLabel(Database:getPref(PREF.notebook_template, "grid")) end,
            callback = function()
                self:showCyclePicker(_("Default Template"), templates, Database:getPref(PREF.notebook_template, "grid"), function(val)
                    Database:setPref(PREF.notebook_template, val)
                    settings_screen:openNotebookSettings()
                end)
            end,
        },
        {
            label = _("Auto-save interval"),
            description = _("Seconds between automatic saves (10-300)"),
            value_func = function() return Database:getPref(PREF.notebook_autosave, "30") .. "s" end,
            callback = function()
                self:showNumberInput(_("Auto-save interval (seconds)"), tonumber(Database:getPref(PREF.notebook_autosave, "30")) or 30, 10, 300, function(val)
                    Database:setPref(PREF.notebook_autosave, tostring(val))
                    settings_screen:openNotebookSettings()
                end)
            end,
        },
    }

    local has_stylus = Device.hasStylus and Device:hasStylus()
    if not has_stylus then
        table.insert(rows, { separator = true, label = "Device" })
        table.insert(rows, {
            label = _("Note: No stylus detected"),
            description = _("Notebooks work best with a stylus-capable device"),
            value_func = function() return "" end, callback = function() end,
        })
        table.insert(rows, {
            label = _("Show Notebooks tile anyway"),
            description = _("Force the Notebooks tile to appear on Home"),
            value_func = function()
                return Database:getPref("notebooks_force_show", "false") == "true" and "On" or "Off"
            end,
            callback = function()
                local current = Database:getPref("notebooks_force_show", "false")
                Database:setPref("notebooks_force_show", current == "true" and "false" or "true")
                settings_screen:openNotebookSettings()
            end,
        })
    end

    self:showSubScreen(_("Notebooks"), rows)
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
                    text = _("Delete ALL learning space classes?\n\nBooks and notebooks are not affected."),
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
            label = _("Debug Highlights"),
            description = _("Show diagnostic info about highlight loading"),
            value_func = function() return "" end,
            callback = function()
                local HighlightsScreen = package.loaded["highlights"]
                if not HighlightsScreen then
                    pcall(function() HighlightsScreen = require("highlights") end)
                end
                if HighlightsScreen and HighlightsScreen.showDiagnostic then
                    HighlightsScreen.showDiagnostic(settings_screen.ui)
                else
                    UIManager:show(InfoMessage:new{
                        text = _("Highlights module not available."), timeout = 3,
                    })
                end
            end,
        },
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
                    text = _("Reset ALL settings to defaults?\n\nNotebooks, classes, and saves are not affected."),
                    ok_text = _("Reset"),
                    ok_callback = function()
                        local conn = Database:getConn()
                        if conn then pcall(function() conn:exec("DELETE FROM preferences") end) end
                        Config.UI.show_stats_bar = true
                        Config.DEBUG.verbose_logging = false
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
                        .. "\n\nModules: Home, Library, Notebooks,"
                        .. "\nLearning Spaces, Notecards, Settings",
                })
            end,
        },
    }
    self:showSubScreen(_("Advanced"), rows)
end

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
