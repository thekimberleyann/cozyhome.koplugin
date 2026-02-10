-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         statusbar.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-05
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Top status bar widget for the home screen.
--       Shows time, battery, and contextual info.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local PowerD = Device:getPowerDevice()
local Screen = Device.screen
local _ = require("gettext")

local Config = require("config")
local CozyUI = require("lib/cozyui")

local StatusBar = WidgetContainer:extend{
    width = nil,
    height = nil,
    show_wifi = false,
    show_bluetooth = false,
}

function StatusBar:init()
    self.width = self.width or Screen:getWidth()
    self.height = self.height or Config.UI.statusbar_height
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self:buildContent()
end

function StatusBar:getTimeString()
    return os.date("%I:%M %p")
end

function StatusBar:getBatteryString()
    local pct = PowerD:getCapacity()
    local charging = PowerD:isCharging()
    return charging and (pct .. "% ⚡") or (pct .. "%")
end

function StatusBar:getWifiString()
    if not self.show_wifi then return nil end
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:isWifiOn() then return "WiFi" end
    return nil
end

function StatusBar:buildContent()
    local content_w = math.floor(self.width * 0.85)
    local pad = math.floor((self.width - content_w) / 2)
    local face = Font:getFace("smallinfofont", Config.UI.font_size_status)

    local time_text = TextWidget:new{
        face = face, text = self:getTimeString(), fgcolor = CozyUI.DARK_GRAY,
    }

    local battery_text = TextWidget:new{
        face = face, text = self:getBatteryString(), fgcolor = CozyUI.DARK_GRAY,
    }

    local wifi_str = self:getWifiString()
    local right_items = {}
    if wifi_str then
        table.insert(right_items, TextWidget:new{
            face = face, text = wifi_str, fgcolor = CozyUI.GRAY,
        })
        table.insert(right_items, HorizontalSpan:new{width = 10})
    end
    table.insert(right_items, battery_text)

    local right_group = HorizontalGroup:new{ align = "center" }
    for _, item in ipairs(right_items) do
        table.insert(right_group, item)
    end

    local bar = OverlapGroup:new{
        dimen = Geom:new{ w = content_w, h = self.height },
        LeftContainer:new{
            dimen = Geom:new{ w = content_w, h = self.height },
            time_text,
        },
        RightContainer:new{
            dimen = Geom:new{ w = content_w, h = self.height },
            right_group,
        },
    }

    self[1] = FrameContainer:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        bordersize = 0, padding = 0,
        padding_left = pad, padding_right = pad,
        background = CozyUI.WHITE,
        bar,
    }
end

function StatusBar:refresh()
    self:buildContent()
end

return StatusBar
