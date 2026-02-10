-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         main.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-05
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Plugin entry point. Registers menus, actions,
--       and loads all Cozy Home modules. Sets up the
--       highlight context menu integration for flashcard
--       creation.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - home.lua
--       - highlights.lua
--       - highlight_bridge.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

-- ============================================
-- IMPORTS
-- ============================================

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Device = require("device")
local Screen = Device.screen
local Event = require("ui/event")
local Dispatcher = require("dispatcher")
local _ = require("gettext")
local logger = require("logger")

-- ============================================
-- LOAD OUR MODULES
-- ============================================

-- Clear module cache for names shared with other cozy plugins.
-- cozy.koplugin loads first alphabetically and caches its own
-- config.lua, lib/database.lua, etc. under these generic keys.
-- Without this, require() returns the wrong plugin's modules.
package.loaded["config"] = nil
package.loaded["lib/database"] = nil
package.loaded["home"] = nil
package.loaded["statusbar"] = nil
package.loaded["history"] = nil
package.loaded["library"] = nil
package.loaded["notebooks"] = nil
package.loaded["learningspace"] = nil
package.loaded["notecards"] = nil
package.loaded["settings"] = nil
package.loaded["highlight_bridge"] = nil
package.loaded["lib/bookscanner"] = nil
package.loaded["lib/templates"] = nil
package.loaded["lib/highlights"] = nil
package.loaded["lib/coverextractor"] = nil
package.loaded["lib/kobo"] = nil
package.loaded["lib/anki_export"] = nil
package.loaded["lib/anki_import"] = nil
package.loaded["highlights"] = nil
package.loaded["focusmode"] = nil
local Config = require("config")

local Home = nil
local home_ok, home_err = pcall(function()
    Home = require("home")
end)
if not home_ok then
    logger.warn("CozyHome: Failed to load home module:", home_err)
end

local HighlightBridge = nil
local hb_ok, hb_err = pcall(function()
    HighlightBridge = require("highlight_bridge")
end)
if not hb_ok then
    logger.warn("CozyHome: Failed to load highlight_bridge module:", hb_err)
end

local HighlightsScreen = nil
local hl_ok, hl_err = pcall(function()
    HighlightsScreen = require("highlights")
end)
if not hl_ok then
    logger.warn("CozyHome: Failed to load highlights module:", hl_err)
end

local FocusMode = nil
local fm_ok, fm_err = pcall(function()
    FocusMode = require("focusmode")
end)
if not fm_ok then
    logger.warn("CozyHome: Failed to load focusmode module:", fm_err)
end

-- ============================================
-- PLUGIN DEFINITION
-- ============================================

local CozyHome = WidgetContainer:extend{
    name = Config.PLUGIN.name,
    human_name = _(Config.PLUGIN.human_name),
    description = _(Config.PLUGIN.description),
}

-- ============================================
-- INITIALIZATION
-- ============================================

function CozyHome:init()
    self:registerActions()
    self.ui.menu:registerToMainMenu(self)

    -- Register highlight menu item if we are in the reader context
    self:registerHighlightMenuItem()

    -- Load saved focus mode settings
    if FocusMode and FocusMode.loadSettings then
        pcall(FocusMode.loadSettings)
    end

    -- Auto-launch Cozy Home on startup (file manager context only)
    self:maybeAutoLaunch()

    logger.info("Cozy Home v" .. Config.PLUGIN.version .. " initialized")
end

-- ============================================
-- AUTO-LAUNCH ON STARTUP
-- ============================================

--- Show Cozy Home automatically when KOReader starts in file manager mode.
-- Only fires once per FM session. Checks the user's preference first.
function CozyHome:maybeAutoLaunch()
    -- Only auto-launch in file manager context (not when a book is open)
    if self.ui.document then return end
    -- Don't auto-launch if Home module failed to load
    if not Home then return end

    -- Check user preference (default: off until they enable it)
    local auto_launch = G_reader_settings
        and G_reader_settings:isTrue("cozyhome_auto_launch")
    if not auto_launch then return end

    -- Use nextTick so the file manager finishes its own init first.
    -- This shows Cozy Home on top of the file manager — pressing
    -- Back from Cozy Home reveals the normal file browser underneath.
    UIManager:nextTick(function()
        Home.show(self.ui)
    end)
end

-- ============================================
-- HIGHLIGHT MENU INTEGRATION
-- ============================================

--- Register a "Create Flashcard" item in the reader's highlight popup menu.
-- This follows the pattern used by vocabulary_builder and other plugins
-- that add items to the highlight context menu.
function CozyHome:registerHighlightMenuItem()
    -- Only register in reader context (self.ui.highlight exists)
    if not self.ui or not self.ui.highlight then
        return
    end

    -- Add to the highlight popup menu
    self.ui.highlight:addToHighlightDialog("cozyhome_create_card", function(this)
        return {
            text = _("Create Flashcard"),
            enabled = HighlightBridge ~= nil,
            callback = function()
                -- Collect highlight data from the reader
                local selected = this.selected_text
                if not selected then return end

                local highlight_data = {
                    text = selected.text or "",
                    book_path = self.ui.document and self.ui.document.file or "",
                    book_title = "",
                    page = selected.pos0 and selected.pos0.page or nil,
                    chapter = nil,
                }

                -- Try to get book title from document props
                local ok_props, props = pcall(function()
                    return self.ui.doc_props
                end)
                if ok_props and props then
                    highlight_data.book_title = props.title or ""
                end
                if highlight_data.book_title == "" and highlight_data.book_path ~= "" then
                    highlight_data.book_title = highlight_data.book_path:match("([^/]+)$") or ""
                end

                -- Try to get current chapter/section
                local ok_toc, toc_mgr = pcall(function()
                    return self.ui.toc
                end)
                if ok_toc and toc_mgr and toc_mgr.getTocTitleByPage then
                    local ok_ch, ch = pcall(toc_mgr.getTocTitleByPage, toc_mgr,
                        selected.pos0 and selected.pos0.page or 0)
                    if ok_ch and ch then
                        highlight_data.chapter = ch
                    end
                end

                this:onClose()
                UIManager:nextTick(function()
                    self:onCreateCardFromHighlight(highlight_data)
                end)
            end,
        }
    end)
end

-- ============================================
-- HOME SCREEN
-- ============================================

function CozyHome:showHomeScreen()
    if not Home then
        UIManager:show(InfoMessage:new{
            text = _("Cozy Home not available.\n\nError: ")
                .. tostring(home_err or "Unknown"),
            timeout = 5,
        })
        return
    end

    Home.show(self.ui)
end

-- ============================================
-- ACTIONS REGISTRATION
-- ============================================

function CozyHome:registerActions()
    Dispatcher:registerAction("cozyhome_show", {
        category = "none",
        event = "ShowCozyHome",
        title = _("Cozy Home"),
        description = _("Open Cozy Home welcome screen"),
    })
    Dispatcher:registerAction("cozyhome_create_card_from_highlight", {
        category = "none",
        event = "CreateCardFromHighlight",
        title = _("Create Flashcard"),
        description = _("Create a flashcard from highlighted text"),
    })
    Dispatcher:registerAction("cozyhome_browse_highlights", {
        category = "none",
        event = "BrowseHighlights",
        title = _("Browse Highlights"),
        description = _("Browse highlights for the current book"),
    })
    Dispatcher:registerAction("cozyhome_browse_all_highlights", {
        category = "none",
        event = "BrowseAllHighlights",
        title = _("Browse All Highlights"),
        description = _("Browse highlights across all books"),
    })
    Dispatcher:registerAction("cozyhome_focus_mode", {
        category = "none",
        event = "ShowFocusMode",
        title = _("Focus Mode"),
        description = _("Open the Pomodoro focus timer"),
    })
    Dispatcher:registerAction("cozyhome_start_focus", {
        category = "none",
        event = "StartFocusSession",
        title = _("Start Focus Session"),
        description = _("Start a Pomodoro focus session immediately"),
    })
end

-- ============================================
-- ACTION HANDLERS
-- ============================================

function CozyHome:onShowCozyHome()
    self:showHomeScreen()
    return true
end

function CozyHome:onBrowseHighlights()
    if not HighlightsScreen then
        UIManager:show(InfoMessage:new{
            text = _("Highlights module not available.\n\nError: ")
                .. tostring(hl_err or "Unknown"),
            timeout = 5,
        })
        return true
    end
    HighlightsScreen.showForCurrentBook(self.ui)
    return true
end

function CozyHome:onBrowseAllHighlights()
    if not HighlightsScreen then
        UIManager:show(InfoMessage:new{
            text = _("Highlights module not available.\n\nError: ")
                .. tostring(hl_err or "Unknown"),
            timeout = 5,
        })
        return true
    end
    HighlightsScreen.showForAllBooks(self.ui)
    return true
end

function CozyHome:onShowFocusMode()
    if not FocusMode then
        UIManager:show(InfoMessage:new{
            text = _("Focus Mode not available.\n\nError: ")
                .. tostring(fm_err or "Unknown"),
            timeout = 5,
        })
        return true
    end
    FocusMode.show(self.ui)
    return true
end

function CozyHome:onStartFocusSession()
    if not FocusMode then
        UIManager:show(InfoMessage:new{
            text = _("Focus Mode not available."),
            timeout = 3,
        })
        return true
    end
    FocusMode.startWork()
    return true
end

--- Handle creating a flashcard from highlight data.
-- @param highlight_data table: { text, book_path, book_title, page, chapter }
function CozyHome:onCreateCardFromHighlight(highlight_data)
    if HighlightBridge then
        HighlightBridge.createCardFromHighlight(highlight_data)
    else
        UIManager:show(InfoMessage:new{
            text = _("Highlight bridge not available."),
            timeout = 3,
        })
    end
    return true
end

-- ============================================
-- MENU DEFINITION
-- ============================================

function CozyHome:addToMainMenu(menu_items)
    menu_items.cozyhome = {
        text_func = function()
            if FocusMode and FocusMode.isActive() then
                local ts = FocusMode.getTimerState()
                local m = math.floor(ts.time_remaining / 60)
                local s = ts.time_remaining % 60
                return string.format("Cozy Home  ◷ %02d:%02d", m, s)
            end
            return _("Cozy Home")
        end,
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Open Cozy Home"),
                keep_menu_open = false,
                callback = function()
                    self:showHomeScreen()
                end,
            },
            {
                text = _("Browse Highlights (This Book)"),
                keep_menu_open = false,
                enabled_func = function()
                    return HighlightsScreen ~= nil and self.ui and self.ui.document ~= nil
                end,
                callback = function()
                    self:onBrowseHighlights()
                end,
            },
            {
                text = _("Browse All Highlights"),
                keep_menu_open = false,
                enabled_func = function()
                    return HighlightsScreen ~= nil
                end,
                callback = function()
                    self:onBrowseAllHighlights()
                end,
            },
            {
                text_func = function()
                    if FocusMode and FocusMode.isActive() then
                        local ts = FocusMode.getTimerState()
                        local label = ts.is_break and "Break" or "Focus"
                        local m = math.floor(ts.time_remaining / 60)
                        local s = ts.time_remaining % 60
                        return string.format("(%s) %s %02d:%02d", label, "Focus Mode", m, s)
                    end
                    return _("Focus Mode")
                end,
                keep_menu_open = false,
                enabled_func = function()
                    return FocusMode ~= nil
                end,
                callback = function()
                    self:onShowFocusMode()
                end,
                separator = true,
            },
            {
                text = _("Open on startup"),
                checked_func = function()
                    return G_reader_settings:isTrue("cozyhome_auto_launch")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("cozyhome_auto_launch")
                end,
            },
            {
                text = _("About"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = Config.PLUGIN.human_name
                            .. " v" .. Config.PLUGIN.version
                            .. "\n\n" .. Config.PLUGIN.description,
                    })
                end,
            },
        },
    }
end

-- ============================================
-- CLEANUP
-- ============================================

function CozyHome:onCloseDocument()
    logger.dbg("CozyHome: Document closed")
end

-- ============================================
-- RETURN THE PLUGIN
-- ============================================

return CozyHome
