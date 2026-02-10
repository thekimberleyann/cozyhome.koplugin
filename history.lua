-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         history.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-05
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Recent reads screen. Displays reading history
--       using KOReader's Menu widget with Cozy styling.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local Device = require("device")
local Menu = require("ui/widget/menu")
local ReadHistory = require("readhistory")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Screen = Device.screen
local _ = require("gettext")

local History = {}

function History.show(ui, on_close)
    ReadHistory:reload()
    local hist = ReadHistory.hist or {}

    if #hist == 0 then
        UIManager:show(InfoMessage:new{
            text = _("☕ No reading history yet.\n\nOpen a book to start building your history."),
            timeout = 3,
        })
        return
    end

    local menu_items = {}
    local max_items = math.min(#hist, 50)
    for i = 1, max_items do
        local entry = hist[i]
        if entry then
            local filename = entry.text or entry.file:match("([^/]+)$") or "Unknown"
            local display = filename:gsub("%.%w+$", "")
            table.insert(menu_items, {
                text = display,
                mandatory = entry.mandatory or "",
                file = entry.file,
                dim = entry.dim,
                callback = function()
                    if History._menu then
                        UIManager:close(History._menu)
                        History._menu = nil
                    end
                    if on_close then on_close() end
                    if entry.file and not entry.dim then
                        local ReaderUI = require("apps/reader/readerui")
                        ReaderUI:showReader(entry.file)
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("This file is no longer available."),
                            timeout = 2,
                        })
                    end
                end,
            })
        end
    end

    local menu
    menu = Menu:new{
        title = _("☕ Recent Reads"),
        item_table = menu_items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        covers_fullscreen = true,
        onMenuClose = function()
            UIManager:close(menu)
            History._menu = nil
            if on_close then on_close() end
        end,
    }
    History._menu = menu
    UIManager:show(menu)
end

return History
