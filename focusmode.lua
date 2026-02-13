-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         focusmode.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-09
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Gamified Pomodoro focus timer with XP, levels,
--       streaks, achievements, flashcard review during
--       breaks, and session history. Full-screen UI
--       styled to the Cozy Design System.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - lib/database.lua
--       - lib/cozyui.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local SpinWidget = require("ui/widget/spinwidget")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local _ = require("gettext")
local T = require("ffi/util").template
local logger = require("logger")

local Config = require("config")
local CozyUI = require("lib/cozyui")
local Database = require("lib/database")

local BLACK      = CozyUI.BLACK
local DARK_GRAY  = CozyUI.DARK_GRAY
local GRAY       = CozyUI.GRAY
local LIGHT_GRAY = CozyUI.LIGHT_GRAY
local WHITE      = CozyUI.WHITE
local sp         = CozyUI.sp

-- ─────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────

local XP = {
    SESSION_COMPLETE = 50,
    PER_MINUTE       = 2,
    PER_PAGE         = 5,
    BREAK_TAKEN      = 10,
    FLASHCARD_REVIEW = 3,
    STREAK_MULTIPLIER = 0.05,
}

local LEVEL_THRESHOLDS = {
    0, 100, 250, 500, 850, 1300, 1900, 2650, 3550, 4600,
    5800, 7200, 8800, 10600, 12600, 14800, 17200, 19800, 22600, 25600,
}

local ACHIEVEMENTS = {
    first_focus = {
        id = "first_focus", name = _("First Focus"),
        desc = _("Complete your first focus session"),
        icon = "✦", category = "progress", tiers = {1, 1, 1, 1},
    },
    focus_apprentice = {
        id = "focus_apprentice", name = _("Focus Apprentice"),
        desc = _("Complete focus sessions"),
        icon = "◐", category = "progress", tiers = {10, 25, 50, 100},
    },
    focus_master = {
        id = "focus_master", name = _("Focus Master"),
        desc = _("Complete focus sessions"),
        icon = "●", category = "progress", tiers = {100, 250, 500, 1000},
    },
    early_bird = {
        id = "early_bird", name = _("Early Bird"),
        desc = _("Sessions before 7 AM"),
        icon = "☀", category = "time", tiers = {1, 5, 15, 30},
    },
    night_owl = {
        id = "night_owl", name = _("Night Owl"),
        desc = _("Sessions after 10 PM"),
        icon = "☾", category = "time", tiers = {1, 5, 15, 30},
    },
    weekend_scholar = {
        id = "weekend_scholar", name = _("Weekend Scholar"),
        desc = _("Sessions on weekends"),
        icon = "♡", category = "time", tiers = {5, 20, 50, 100},
    },
    marathon_runner = {
        id = "marathon_runner", name = _("Marathon Runner"),
        desc = _("4+ sessions in one day"),
        icon = "⊹", category = "dedication", tiers = {1, 5, 15, 30},
    },
    streak_starter = {
        id = "streak_starter", name = _("Streak Starter"),
        desc = _("Achieve a 3-day streak"),
        icon = "★", category = "dedication", tiers = {1, 1, 1, 1},
    },
    streak_master = {
        id = "streak_master", name = _("Streak Master"),
        desc = _("Achieve streak milestones"),
        icon = "☆", category = "dedication", tiers = {7, 14, 30, 60},
    },
    page_turner = {
        id = "page_turner", name = _("Page Turner"),
        desc = _("Read pages during focus"),
        icon = "≡", category = "milestone", tiers = {100, 500, 1500, 5000},
    },
    time_investor = {
        id = "time_investor", name = _("Time Investor"),
        desc = _("Hours in focus mode"),
        icon = "⌛", category = "milestone", tiers = {10, 50, 150, 500},
    },
    card_scholar = {
        id = "card_scholar", name = _("Card Scholar"),
        desc = _("Review flashcards during breaks"),
        icon = "◇", category = "milestone", tiers = {25, 100, 300, 1000},
    },
}

local TIER_NAMES = {"Bronze", "Silver", "Gold", "Platinum"}
local TIER_MARKS = {"·", "○", "◐", "●"}

-- Achievement display order (so they render in a consistent sequence)
local ACHIEVEMENT_ORDER = {
    "first_focus", "focus_apprentice", "focus_master",
    "early_bird", "night_owl", "weekend_scholar",
    "marathon_runner", "streak_starter", "streak_master",
    "page_turner", "time_investor", "card_scholar",
}

-- Category metadata for grouped display
local ACHIEVEMENT_CATEGORIES = {
    {name = _("Progress"), id = "progress"},
    {name = _("Time"), id = "time"},
    {name = _("Dedication"), id = "dedication"},
    {name = _("Milestones"), id = "milestone"},
}

-- ─────────────────────────────────────────
-- Module & State
-- ─────────────────────────────────────────

local FocusMode = {}
FocusMode._current_instance = nil

-- Persistent timer state (survives screen close/reopen)
local timer_state = {
    active = false,
    paused = false,
    is_break = false,
    session_type = "work",   -- "work", "short_break", "long_break"
    time_remaining = 0,
    sessions_completed = 0,
    start_page = nil,
    session_start_time = nil,
}

-- Game data (persisted to JSON via Database)
local game_data = nil

-- Reference to KOReader UI (set by show())
local ui_ref = nil

-- Module-local dialog reference (avoids polluting _G)
local break_end_dialog = nil

-- ─────────────────────────────────────────
-- Flashcard Bridge (optional — works if cozyflashcards is installed)
-- ─────────────────────────────────────────

local function getFlashcardDB()
    -- Try to open the cozy_flashcards.db directly
    local DataStorage = require("datastorage")
    local SQ3 = require("lua-ljsqlite3/init")
    local lfs = require("libs/libkoreader-lfs")

    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
    local attr = lfs.attributes(db_path)
    if not attr then return nil end

    local ok, conn = pcall(SQ3.open, db_path)
    if not ok or not conn then return nil end
    return conn
end

--- Get count of cards due for review
local function getDueCardCount()
    local conn = getFlashcardDB()
    if not conn then return 0 end

    local count = 0
    pcall(function()
        local today = os.date("%Y-%m-%d")
        local stmt = conn:prepare(
            "SELECT COUNT(*) FROM flashcards WHERE suspended = 0 "
            .. "AND (state = 'new' OR (next_review IS NOT NULL AND next_review <= ?))"
        )
        if stmt then
            stmt:bind(today)
            local row = stmt:step()
            if row then count = tonumber(row[1]) or 0 end
            stmt:close()
        end
    end)
    pcall(function() conn:close() end)
    return count
end

-- ─────────────────────────────────────────
-- Game Data Persistence
-- ─────────────────────────────────────────

local function loadGameData()
    if game_data then return end
    local data = Database:getFocusGameData()
    if data then
        game_data = data
    else
        game_data = {
            xp = 0, level = 1,
            total_sessions = 0, total_pages = 0,
            total_minutes = 0, total_flashcards = 0,
            streak_days = 0, last_session_date = nil,
            freeze_tokens = 0,
            achievements = {},
            sessions_today = 0, today_date = os.date("%Y-%m-%d"),
        }
        Database:saveFocusGameData(game_data)
    end
    -- Reset daily counter if date changed
    local today = os.date("%Y-%m-%d")
    if game_data.today_date ~= today then
        game_data.sessions_today = 0
        game_data.today_date = today
        Database:saveFocusGameData(game_data)
    end
    -- Ensure total_flashcards field exists (migration)
    if not game_data.total_flashcards then
        game_data.total_flashcards = 0
    end
end

local function saveGameData()
    if game_data then Database:saveFocusGameData(game_data) end
end

-- ─────────────────────────────────────────
-- Level & XP helpers
-- ─────────────────────────────────────────

local function getLevelForXP(xp)
    for i = #LEVEL_THRESHOLDS, 1, -1 do
        if xp >= LEVEL_THRESHOLDS[i] then return i end
    end
    return 1
end

local function getLevelProgress()
    local level = getLevelForXP(game_data.xp)
    local cur = LEVEL_THRESHOLDS[level] or 0
    local nxt = LEVEL_THRESHOLDS[level + 1]
    if not nxt then return game_data.xp - cur, 0 end
    return game_data.xp - cur, nxt - cur
end

local function getStreakBonus()
    return math.min((game_data.streak_days or 0) * XP.STREAK_MULTIPLIER, 1.0)
end

local function awardXP(amount, source)
    local streak_bonus = getStreakBonus()
    local actual_xp = math.floor(amount * (1 + streak_bonus))
    local old_level = getLevelForXP(game_data.xp)
    game_data.xp = game_data.xp + actual_xp
    local new_level = getLevelForXP(game_data.xp)
    if new_level > old_level then game_data.level = new_level end
    saveGameData()
    return actual_xp
end

-- ─────────────────────────────────────────
-- Streak
-- ─────────────────────────────────────────

local function progressAchievement(id, amount)
    local a = ACHIEVEMENTS[id]
    if not a then return end
    if not game_data.achievements[id] then
        game_data.achievements[id] = {progress = 0, tier = 0}
    end
    local d = game_data.achievements[id]
    d.progress = d.progress + amount
    for tier = 4, d.tier + 1, -1 do
        if d.progress >= a.tiers[tier] and d.tier < tier then
            d.tier = tier
            break
        end
    end
    saveGameData()
end

local function updateStreak()
    local today = os.date("%Y-%m-%d")
    local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
    if game_data.last_session_date == today then
        return
    elseif game_data.last_session_date == yesterday then
        game_data.streak_days = game_data.streak_days + 1
    elseif game_data.last_session_date then
        if game_data.freeze_tokens > 0 then
            game_data.freeze_tokens = game_data.freeze_tokens - 1
            game_data.streak_days = game_data.streak_days + 1
        else
            game_data.streak_days = 1
        end
    else
        game_data.streak_days = 1
    end
    game_data.last_session_date = today
    if game_data.streak_days > 0 and game_data.streak_days % 7 == 0 then
        game_data.freeze_tokens = game_data.freeze_tokens + 1
    end
    if game_data.streak_days >= 3 then progressAchievement("streak_starter", 1) end
    progressAchievement("streak_master", game_data.streak_days)
    saveGameData()
end

-- ─────────────────────────────────────────
-- Timer helpers
-- ─────────────────────────────────────────

local function formatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

local function getCurrentPage()
    if ui_ref and ui_ref.document then
        local page = ui_ref.paging and ui_ref.paging.current_page
        if not page and ui_ref.rolling then
            page = ui_ref.rolling.current_page
        end
        return page
    end
    return nil
end

-- Forward declarations
local timerTick
local onTimerComplete

timerTick = function()
    if not timer_state.active or timer_state.paused then return end
    timer_state.time_remaining = timer_state.time_remaining - 1
    if timer_state.time_remaining <= 0 then
        onTimerComplete()
    else
        UIManager:scheduleIn(1, timerTick)
        -- Refresh the screen if it's open
        if FocusMode._current_instance then
            FocusMode._current_instance:refresh()
        end
    end
end

-- ─────────────────────────────────────────
-- Session completion logic
-- ─────────────────────────────────────────

local function onWorkSessionComplete()
    timer_state.sessions_completed = timer_state.sessions_completed + 1
    game_data.total_sessions = game_data.total_sessions + 1
    game_data.sessions_today = game_data.sessions_today + 1

    local pages_read = 0
    local cur_page = getCurrentPage()
    if timer_state.start_page and cur_page then
        pages_read = math.max(0, cur_page - timer_state.start_page)
        game_data.total_pages = game_data.total_pages + pages_read
    end

    local dur = Config.FOCUS.work_duration
    game_data.total_minutes = game_data.total_minutes + dur
    updateStreak()

    local total_xp = XP.SESSION_COMPLETE + dur * XP.PER_MINUTE + pages_read * XP.PER_PAGE
    local earned = awardXP(total_xp, "work session")

    progressAchievement("first_focus", 1)
    progressAchievement("focus_apprentice", 1)
    progressAchievement("focus_master", 1)
    progressAchievement("page_turner", pages_read)
    progressAchievement("time_investor", dur / 60)

    local hour = tonumber(os.date("%H"))
    if hour < 7 then progressAchievement("early_bird", 1) end
    if hour >= 22 then progressAchievement("night_owl", 1) end
    local weekday = tonumber(os.date("%w"))
    if weekday == 0 or weekday == 6 then progressAchievement("weekend_scholar", 1) end
    if game_data.sessions_today >= 4 then progressAchievement("marathon_runner", 1) end

    Database:addFocusSession({
        book_path = ui_ref and ui_ref.document and ui_ref.document.file,
        book_title = ui_ref and ui_ref.document and ui_ref.document:getProps() and ui_ref.document:getProps().title,
        duration_minutes = dur,
        pages_read = pages_read,
        xp_earned = earned,
        completed = true,
    })
    saveGameData()

    -- Determine break type
    local break_type = "short_break"
    local break_dur = Config.FOCUS.short_break
    if timer_state.sessions_completed >= Config.FOCUS.sessions_before_long_break then
        break_type = "long_break"
        break_dur = Config.FOCUS.long_break
        timer_state.sessions_completed = 0
    end

    -- Build completion summary
    local xp_in, xp_need = getLevelProgress()
    local pct = xp_need > 0 and math.floor((xp_in / xp_need) * 10) or 10
    local bar = string.rep("●", pct) .. string.rep("○", 10 - pct)
    local streak_pct = math.floor(getStreakBonus() * 100)

    local msg = string.format(
        "Session Complete!\n\n"
        .. "+%d XP · %d pages · %d-day streak (+%d%%)\n"
        .. "Level %d  [%s]  %d/%s XP\n"
        .. "Today: %d sessions",
        earned, pages_read, game_data.streak_days, streak_pct,
        game_data.level, bar, xp_in, xp_need > 0 and tostring(xp_need) or "MAX",
        game_data.sessions_today
    )

    -- Check if flashcards are available for break review
    local due_cards = 0
    pcall(function() due_cards = getDueCardCount() end)

    local dialog
    local break_buttons = {
        {
            {
                text = T(_("Take %1-min break"), break_dur),
                callback = function()
                    UIManager:close(dialog)
                    awardXP(XP.BREAK_TAKEN, "taking break")
                    FocusMode.startBreak(break_dur, break_type)
                end,
            },
        },
    }

    -- Add flashcard review option if cards are due
    if due_cards > 0 then
        table.insert(break_buttons, {
            {
                text = T(_("Review Cards (%1 due) + Break"), due_cards),
                callback = function()
                    UIManager:close(dialog)
                    awardXP(XP.BREAK_TAKEN, "taking break")
                    FocusMode.startBreak(break_dur, break_type)
                    -- Launch flashcard review after a tick so the break timer starts
                    UIManager:nextTick(function()
                        FocusMode.launchFlashcardReview()
                    end)
                end,
            },
        })
    end

    table.insert(break_buttons, {
        {
            text = _("Start new session"),
            callback = function()
                UIManager:close(dialog)
                FocusMode.startWork()
            end,
        },
    })
    table.insert(break_buttons, {
        {
            text = _("Done for now"),
            callback = function()
                UIManager:close(dialog)
            end,
        },
    })

    dialog = ButtonDialog:new{
        title = _("✦ Focus Complete ✦"),
        info_face = Font:getFace("cfont", 16),
        buttons = break_buttons,
    }
    UIManager:show(InfoMessage:new{text = msg, timeout = nil})
    UIManager:show(dialog)
end

onTimerComplete = function()
    timer_state.active = false
    if timer_state.is_break then
        -- Break ended
        local due_cards = 0
        pcall(function() due_cards = getDueCardCount() end)

        local break_buttons = {
            {{text = _("Start next focus session"), callback = function()
                if break_end_dialog then UIManager:close(break_end_dialog) end
                FocusMode.startWork()
            end}},
        }
        if due_cards > 0 then
            table.insert(break_buttons, 1, {
                {text = T(_("Review Cards (%1 due)"), due_cards), callback = function()
                    if break_end_dialog then UIManager:close(break_end_dialog) end
                    FocusMode.launchFlashcardReview()
                end},
            })
        end
        table.insert(break_buttons, {
            {text = _("Done for now"), callback = function()
                if break_end_dialog then UIManager:close(break_end_dialog) end
            end},
        })

        break_end_dialog = ButtonDialog:new{
            title = _("✦ Break Over ✦"),
            buttons = break_buttons,
        }
        UIManager:show(InfoMessage:new{text = _("Break time is over!\nReady to focus again?"), timeout = nil})
        UIManager:show(break_end_dialog)
    else
        onWorkSessionComplete()
    end
    -- Refresh open screen
    if FocusMode._current_instance then
        FocusMode._current_instance:refresh()
    end
end

-- ─────────────────────────────────────────
-- Flashcard review during breaks
-- ─────────────────────────────────────────

--- Launch the cozyflashcards review screen if available.
-- Falls back to a message if the plugin isn't installed.
function FocusMode.launchFlashcardReview()
    -- Try to require cozyflashcards' review module
    -- The flashcards plugin registers itself; we try to trigger its review
    local launched = false

    -- Method 1: Try to use the Dispatcher event system
    pcall(function()
        local Event = require("ui/event")
        UIManager:broadcastEvent(Event:new("StartFlashcardReview"))
        launched = true
    end)

    if not launched then
        UIManager:show(InfoMessage:new{
            text = _("Install Cozy Flashcards to review cards during breaks."),
            timeout = 3,
        })
    end
end

--- Called when a flashcard is reviewed during a break.
-- Other plugins can call FocusMode.onFlashcardReviewed() to grant XP.
function FocusMode.onFlashcardReviewed()
    if timer_state.is_break and timer_state.active then
        loadGameData()
        game_data.total_flashcards = (game_data.total_flashcards or 0) + 1
        awardXP(XP.FLASHCARD_REVIEW, "flashcard review")
        progressAchievement("card_scholar", 1)
        saveGameData()
    end
end

-- ─────────────────────────────────────────
-- Public timer controls
-- ─────────────────────────────────────────

function FocusMode.startWork()
    if timer_state.active then
        UIManager:show(InfoMessage:new{text = _("A session is already running."), timeout = 2})
        return
    end
    loadGameData()
    timer_state.active = true
    timer_state.paused = false
    timer_state.is_break = false
    timer_state.session_type = "work"
    timer_state.time_remaining = Config.FOCUS.work_duration * 60
    timer_state.start_page = getCurrentPage()
    timer_state.session_start_time = os.time()
    UIManager:scheduleIn(1, timerTick)
    if FocusMode._current_instance then
        FocusMode._current_instance:refresh()
    end
end

function FocusMode.startBreak(duration, break_type)
    timer_state.active = true
    timer_state.paused = false
    timer_state.is_break = true
    timer_state.session_type = break_type or "short_break"
    timer_state.time_remaining = duration * 60
    UIManager:scheduleIn(1, timerTick)
    if FocusMode._current_instance then
        FocusMode._current_instance:refresh()
    end
end

function FocusMode.togglePause()
    if not timer_state.active then return end
    timer_state.paused = not timer_state.paused
    if not timer_state.paused then
        UIManager:scheduleIn(1, timerTick)
    end
    if FocusMode._current_instance then
        FocusMode._current_instance:refresh()
    end
end

function FocusMode.stopSession(force)
    if not timer_state.active then return end
    local do_stop = function()
        timer_state.active = false
        timer_state.paused = false
        if FocusMode._current_instance then
            FocusMode._current_instance:refresh()
        end
    end
    if force then
        do_stop()
    else
        UIManager:show(ConfirmBox:new{
            text = _("Stop the current session?\nYou won't earn XP for incomplete sessions."),
            ok_text = _("Stop"), cancel_text = _("Continue"),
            ok_callback = do_stop,
        })
    end
end

function FocusMode.isActive()
    return timer_state.active
end

function FocusMode.getTimerState()
    return timer_state
end

-- ─────────────────────────────────────────
-- Focus Screen (full-screen Cozy UI)
-- ─────────────────────────────────────────

local CozyFocusScreen = InputContainer:extend{
    name = "cozy_focus_screen",
    covers_fullscreen = true,
    ui = nil,
    on_close_callback = nil,
}

function CozyFocusScreen:init()
    self.dimen = Geom:new{x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight()}
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    loadGameData()
    FocusMode._current_instance = self
    self:buildUI()
end

function CozyFocusScreen:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function CozyFocusScreen:onCloseWidget()
    FocusMode._current_instance = nil
    UIManager:setDirty(nil, function() return "full", self.dimen end)
end

function CozyFocusScreen:onClose()
    UIManager:close(self)
    if self.on_close_callback then self.on_close_callback() end
    return true
end

function CozyFocusScreen:refresh()
    self:buildUI()
    UIManager:setDirty(self, function() return "partial", self.dimen end)
end

function CozyFocusScreen:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local focus_screen = self
    local items = {}

    -- Header (hide_timer: this screen has its own big timer display)
    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Focus Mode",
        back_callback = function() focus_screen:onClose() end,
        exit_callback = function() focus_screen:onClose() end,
        show_parent = self,
        hide_timer = true,
    }))
    table.insert(items, CozyUI.buildDottedDivider(sw, content_w))
    table.insert(items, sp(6))

    -- ── Timer Display ──
    if timer_state.active then
        local type_label = timer_state.is_break
            and (timer_state.session_type == "long_break" and _("Long Break") or _("Short Break"))
            or _("Focus Session")
        local pause_label = timer_state.paused and "  (paused)" or ""

        -- Big timer text
        local timer_text = TextWidget:new{
            face = Font:getFace("tfont", 40),
            text = formatTime(timer_state.time_remaining),
            fgcolor = BLACK,
        }
        local label_text = TextWidget:new{
            face = Font:getFace("cfont", 15),
            text = type_label .. pause_label,
            fgcolor = GRAY,
        }

        local timer_box = CozyUI.buildRoundedBox(
            VerticalGroup:new{
                align = "center",
                sp(8),
                CenterContainer:new{
                    dimen = Geom:new{w = content_w - 30, h = timer_text:getSize().h},
                    timer_text,
                },
                sp(4),
                CenterContainer:new{
                    dimen = Geom:new{w = content_w - 30, h = label_text:getSize().h},
                    label_text,
                },
                sp(8),
            }
        )
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = timer_box:getSize().h},
            timer_box,
        })
        table.insert(items, sp(8))

        -- Control buttons
        local btn_w = math.floor(content_w * 0.42)
        local pause_btn = Button:new{
            text = timer_state.paused and _("Resume") or _("Pause"),
            callback = function() FocusMode.togglePause() end,
            width = btn_w, bordersize = 2, radius = 8,
            text_font_bold = true, padding_v = 10,
            show_parent = self,
        }
        local stop_btn = Button:new{
            text = _("Stop"),
            callback = function() FocusMode.stopSession() end,
            width = btn_w, bordersize = 1, radius = 8,
            padding_v = 10, show_parent = self,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = pause_btn:getSize().h},
            HorizontalGroup:new{
                align = "center",
                pause_btn,
                HorizontalSpan:new{width = 12},
                stop_btn,
            },
        })

        -- During breaks: show "Review Cards" button if available
        if timer_state.is_break then
            local due_cards = 0
            pcall(function() due_cards = getDueCardCount() end)
            if due_cards > 0 then
                table.insert(items, sp(8))
                local review_btn = Button:new{
                    text = T(_("◇ Review Cards (%1 due)"), due_cards),
                    callback = function() FocusMode.launchFlashcardReview() end,
                    width = math.floor(content_w * 0.92),
                    bordersize = 1, radius = 8, padding_v = 10,
                    show_parent = self,
                }
                table.insert(items, CenterContainer:new{
                    dimen = Geom:new{w = sw, h = review_btn:getSize().h},
                    review_btn,
                })
            end
        end
    else
        -- No timer running — show start button
        local start_btn = Button:new{
            text = T(_("Start Focus · %1 min"), Config.FOCUS.work_duration),
            callback = function()
                FocusMode.startWork()
            end,
            width = math.floor(content_w * 0.92),
            bordersize = 2, radius = 8,
            text_font_bold = true, padding_v = 14,
            show_parent = self,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = start_btn:getSize().h},
            start_btn,
        })
    end

    table.insert(items, sp(6))
    table.insert(items, CozyUI.buildSectionDivider(sw, content_w, "Stats"))
    table.insert(items, sp(4))

    -- ── Stats ──
    local xp_in, xp_need = getLevelProgress()
    local pct = xp_need > 0 and math.floor((xp_in / xp_need) * 10) or 10
    local bar = string.rep("●", pct) .. string.rep("○", 10 - pct)
    local hours = math.floor((game_data.total_minutes or 0) / 60)
    local mins = (game_data.total_minutes or 0) % 60
    local streak_pct = math.floor(getStreakBonus() * 100)

    -- XP progress bar — always shown as a centered line
    local bar_text = TextWidget:new{
        face = Font:getFace("cfont", 16),
        text = string.format("Lv.%d  [%s]  %d/%s XP",
            game_data.level or 1, bar, xp_in,
            xp_need > 0 and tostring(xp_need) or "MAX"),
        fgcolor = BLACK,
        max_width = content_w,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = bar_text:getSize().h + 4},
        bar_text,
    })
    table.insert(items, sp(6))

    if timer_state.active then
        -- Compact: 2-column pairs for the essentials
        table.insert(items, CozyUI.buildStatPair(sw, content_w,
            {_("Streak"), string.format("%d days (+%d%%)", game_data.streak_days or 0, streak_pct)},
            {_("Today"), string.format("%d sessions", game_data.sessions_today or 0)}
        ))
        table.insert(items, CozyUI.buildStatPair(sw, content_w,
            {_("Total Time"), string.format("%dh %dm", hours, mins)},
            {_("Total XP"), tostring(game_data.xp or 0)}
        ))
    else
        -- Full stats in 2-column grid (scrollable in idle view)
        table.insert(items, CozyUI.buildStatPair(sw, content_w,
            {_("Total XP"), tostring(game_data.xp or 0)},
            {_("Sessions"), tostring(game_data.total_sessions or 0)}
        ))
        table.insert(items, CozyUI.buildStatPair(sw, content_w,
            {_("Pages Read"), tostring(game_data.total_pages or 0)},
            {_("Focus Time"), string.format("%dh %dm", hours, mins)}
        ))
        table.insert(items, CozyUI.buildStatPair(sw, content_w,
            {_("Cards Reviewed"), tostring(game_data.total_flashcards or 0)},
            {_("Streak"), string.format("%d days (+%d%%)", game_data.streak_days or 0, streak_pct)}
        ))
        table.insert(items, CozyUI.buildStatPair(sw, content_w,
            {_("Freeze Tokens"), tostring(game_data.freeze_tokens or 0)},
            {_("Today"), string.format("%d sessions", game_data.sessions_today or 0)}
        ))
    end
    table.insert(items, sp(8))

    -- ── Action buttons ──
    local btn_w2 = math.floor(content_w * 0.28)
    local achiev_btn = Button:new{
        text = _("Awards"),
        callback = function() focus_screen:showAchievements() end,
        width = btn_w2, bordersize = 1, radius = 8, padding_v = 10,
        show_parent = self,
    }
    local history_btn = Button:new{
        text = _("History"),
        callback = function() focus_screen:showHistory() end,
        width = btn_w2, bordersize = 1, radius = 8, padding_v = 10,
        show_parent = self,
    }
    local settings_btn = Button:new{
        text = _("Settings"),
        callback = function() focus_screen:showSettings() end,
        width = btn_w2, bordersize = 1, radius = 8, padding_v = 10,
        show_parent = self,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = achiev_btn:getSize().h},
        HorizontalGroup:new{
            align = "center",
            achiev_btn,
            HorizontalSpan:new{width = 8},
            history_btn,
            HorizontalSpan:new{width = 8},
            settings_btn,
        },
    })

    -- Assemble
    local content = VerticalGroup:new{align = "center"}
    for _, item in ipairs(items) do table.insert(content, item) end

    -- When the timer is ticking, refresh() is called every second.
    -- A ScrollableContainer resets its scroll position on every rebuild,
    -- which makes the page snap back to the top whenever the user scrolls.
    -- Fix: only wrap in ScrollableContainer when the timer is NOT active.
    -- When the timer IS active the layout is compact enough to fit on screen.
    if timer_state.active then
        self[1] = FrameContainer:new{
            dimen = Geom:new{w = sw, h = sh},
            bordersize = 0, padding = 0,
            background = WHITE,
            content,
        }
    else
        local scrollable = ScrollableContainer:new{
            dimen = Geom:new{w = sw, h = sh},
            show_parent = self,
            content,
        }
        self[1] = FrameContainer:new{
            dimen = Geom:new{w = sw, h = sh},
            bordersize = 0, padding = 0,
            background = WHITE,
            scrollable,
        }
    end
end

-- ─────────────────────────────────────────
-- Achievements Screen (full-screen Cozy UI)
-- ─────────────────────────────────────────

local CozyAchievementsScreen = InputContainer:extend{
    name = "cozy_achievements_screen",
    covers_fullscreen = true,
    on_close_callback = nil,
}

function CozyAchievementsScreen:init()
    self.dimen = Geom:new{x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight()}
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:buildUI()
end

function CozyAchievementsScreen:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function CozyAchievementsScreen:onCloseWidget()
    UIManager:setDirty(nil, function() return "full", self.dimen end)
end

function CozyAchievementsScreen:onClose()
    UIManager:close(self)
    if self.on_close_callback then self.on_close_callback() end
    return true
end

function CozyAchievementsScreen:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local screen = self
    local items = {}

    -- Header
    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Achievements",
        back_callback = function() screen:onClose() end,
        exit_callback = function() screen:onClose() end,
        show_parent = self,
    }))
    table.insert(items, CozyUI.buildDottedDivider(sw, content_w))
    table.insert(items, sp(10))

    -- Count totals for summary
    local total_unlocked = 0
    local total_possible = 0
    for _, id in ipairs(ACHIEVEMENT_ORDER) do
        total_possible = total_possible + 4  -- 4 tiers each
        local d = game_data.achievements[id]
        if d then total_unlocked = total_unlocked + (d.tier or 0) end
    end

    -- Summary stat
    table.insert(items, CozyUI.buildStatBlock(sw, content_w,
        _("Unlocked"),
        string.format("%d / %d tiers", total_unlocked, total_possible)))
    table.insert(items, sp(8))

    -- Render each category
    for _, cat in ipairs(ACHIEVEMENT_CATEGORIES) do
        table.insert(items, CozyUI.buildSectionDivider(sw, content_w, cat.name))
        table.insert(items, sp(6))

        for _, id in ipairs(ACHIEVEMENT_ORDER) do
            local a = ACHIEVEMENTS[id]
            if a and a.category == cat.id then
                local d = game_data.achievements[id] or {progress = 0, tier = 0}
                local tier_mark = d.tier > 0 and TIER_MARKS[d.tier] or " "
                local tier_label = d.tier > 0 and TIER_NAMES[d.tier] or ""

                -- Progress towards next tier
                local progress_str
                if d.tier >= 4 then
                    progress_str = "✓ Complete"
                else
                    local next_target = a.tiers[d.tier + 1] or a.tiers[4]
                    progress_str = string.format("%d / %d", d.progress, next_target)
                end

                -- Achievement name with icon and tier marker
                local name_str = string.format("%s %s %s", tier_mark, a.icon, a.name)
                if tier_label ~= "" then
                    name_str = name_str .. " (" .. tier_label .. ")"
                end

                table.insert(items, CozyUI.buildStatBlock(sw, content_w, name_str, progress_str))
            end
        end
        table.insert(items, sp(8))
    end

    -- Tier legend
    table.insert(items, sp(4))
    local legend = TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = "· = none   ○ = Bronze   ◐ = Silver   ● = Gold/Plat",
        fgcolor = GRAY,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = legend:getSize().h},
        legend,
    })

    table.insert(items, sp(16))
    table.insert(items, CozyUI.buildFooter(sw, "every achievement earned"))

    -- Assemble
    local content = VerticalGroup:new{align = "center"}
    for _, item in ipairs(items) do table.insert(content, item) end

    local scrollable = ScrollableContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        show_parent = self,
        content,
    }

    self[1] = FrameContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        bordersize = 0, padding = 0,
        background = WHITE,
        scrollable,
    }
end

function CozyAchievementsScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end

-- ─────────────────────────────────────────
-- Session History Screen (full-screen Cozy UI)
-- ─────────────────────────────────────────

local CozyHistoryScreen = InputContainer:extend{
    name = "cozy_history_screen",
    covers_fullscreen = true,
    on_close_callback = nil,
}

function CozyHistoryScreen:init()
    self.dimen = Geom:new{x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight()}
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:buildUI()
end

function CozyHistoryScreen:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
    return true
end

function CozyHistoryScreen:onCloseWidget()
    UIManager:setDirty(nil, function() return "full", self.dimen end)
end

function CozyHistoryScreen:onClose()
    UIManager:close(self)
    if self.on_close_callback then self.on_close_callback() end
    return true
end

function CozyHistoryScreen:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local screen = self
    local items = {}

    -- Header
    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Session History",
        back_callback = function() screen:onClose() end,
        exit_callback = function() screen:onClose() end,
        show_parent = self,
    }))
    table.insert(items, CozyUI.buildDottedDivider(sw, content_w))
    table.insert(items, sp(10))

    -- Get session stats from DB
    local db_stats = Database:getFocusSessionStats()

    -- Summary stats
    table.insert(items, CozyUI.buildSectionDivider(sw, content_w, "Summary"))
    table.insert(items, sp(6))

    local total_hours = math.floor(db_stats.total_minutes / 60)
    local total_mins = db_stats.total_minutes % 60

    table.insert(items, CozyUI.buildStatPair(sw, content_w,
        {_("Today"), string.format("%d sessions · %d min", db_stats.today_sessions, db_stats.today_minutes)},
        {_("This Week"), string.format("%d sessions · %d min", db_stats.week_sessions, db_stats.week_minutes)}
    ))
    table.insert(items, CozyUI.buildStatBlock(sw, content_w,
        _("All Time"),
        string.format("%d sessions · %dh %dm", db_stats.total_sessions, total_hours, total_mins)
    ))
    table.insert(items, sp(8))

    -- Recent sessions list
    table.insert(items, CozyUI.buildSectionDivider(sw, content_w, "Recent Sessions"))
    table.insert(items, sp(6))

    local sessions = self:getRecentSessions(30)

    if #sessions == 0 then
        local empty_text = TextWidget:new{
            face = Font:getFace("cfont", 16),
            text = _("No sessions recorded yet."),
            fgcolor = GRAY,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = empty_text:getSize().h + 20},
            empty_text,
        })
    else
        local current_date = nil
        for _, session in ipairs(sessions) do
            -- Group by date
            local session_date = session.started_at and session.started_at:sub(1, 10) or "Unknown"
            if session_date ~= current_date then
                current_date = session_date
                -- Date subheader
                local date_label = TextWidget:new{
                    face = Font:getFace("smallinfofont"),
                    text = "── " .. session_date .. " ──",
                    fgcolor = LIGHT_GRAY,
                }
                table.insert(items, sp(4))
                table.insert(items, CenterContainer:new{
                    dimen = Geom:new{w = sw, h = date_label:getSize().h},
                    date_label,
                })
                table.insert(items, sp(2))
            end

            -- Session entry: time as label, details as value
            local time_str = session.started_at and session.started_at:sub(12, 16) or ""
            local dur_str = string.format("%d min", session.duration_minutes or 0)
            local pages_str = (session.pages_read and session.pages_read > 0)
                and string.format(" · %d pg", session.pages_read) or ""
            local xp_str = (session.xp_earned and session.xp_earned > 0)
                and string.format(" · +%d XP", session.xp_earned) or ""
            local book_str = ""
            if session.book_title and session.book_title ~= "" then
                book_str = CozyUI.truncateText(session.book_title, 40)
            end

            local label = time_str
            if book_str ~= "" then label = time_str .. "  " .. book_str end
            local value = dur_str .. pages_str .. xp_str

            table.insert(items, CozyUI.buildStatBlock(sw, content_w, label, value))
        end
    end

    table.insert(items, sp(16))
    table.insert(items, CozyUI.buildFooter(sw, "every minute counts"))

    -- Assemble
    local content = VerticalGroup:new{align = "center"}
    for _, item in ipairs(items) do table.insert(content, item) end

    local scrollable = ScrollableContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        show_parent = self,
        content,
    }

    self[1] = FrameContainer:new{
        dimen = Geom:new{w = sw, h = sh},
        bordersize = 0, padding = 0,
        background = WHITE,
        scrollable,
    }
end

--- Fetch recent focus sessions from the database.
-- @param limit number: Max sessions to return
-- @return table: Array of session records
function CozyHistoryScreen:getRecentSessions(limit)
    local conn = Database:getConn()
    if not conn then return {} end

    -- Ensure the table exists
    pcall(function()
        conn:exec([[
            CREATE TABLE IF NOT EXISTS focus_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                book_path TEXT,
                book_title TEXT,
                started_at TEXT DEFAULT (datetime('now', 'localtime')),
                duration_minutes INTEGER NOT NULL,
                pages_read INTEGER DEFAULT 0,
                xp_earned INTEGER DEFAULT 0,
                completed INTEGER DEFAULT 1
            );
        ]])
    end)

    local sessions = {}
    pcall(function()
        local stmt = conn:prepare(
            "SELECT book_path, book_title, started_at, duration_minutes, pages_read, xp_earned, completed "
            .. "FROM focus_sessions WHERE completed = 1 "
            .. "ORDER BY started_at DESC LIMIT ?"
        )
        if stmt then
            stmt:bind(limit or 30)
            for row in stmt:rows() do
                table.insert(sessions, {
                    book_path = row[1],
                    book_title = row[2],
                    started_at = row[3],
                    duration_minutes = tonumber(row[4]) or 0,
                    pages_read = tonumber(row[5]) or 0,
                    xp_earned = tonumber(row[6]) or 0,
                    completed = tonumber(row[7]) or 0,
                })
            end
            stmt:close()
        end
    end)
    return sessions
end

function CozyHistoryScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end

-- ─────────────────────────────────────────
-- Sub-screen launchers from CozyFocusScreen
-- ─────────────────────────────────────────

function CozyFocusScreen:showAchievements()
    local focus_screen = self
    local screen = CozyAchievementsScreen:new{
        on_close_callback = function()
            -- Re-show the focus screen after closing achievements
            FocusMode.show(focus_screen.ui, focus_screen.on_close_callback)
        end,
    }
    UIManager:close(self)
    UIManager:show(screen)
end

function CozyFocusScreen:showHistory()
    local focus_screen = self
    local screen = CozyHistoryScreen:new{
        on_close_callback = function()
            FocusMode.show(focus_screen.ui, focus_screen.on_close_callback)
        end,
    }
    UIManager:close(self)
    UIManager:show(screen)
end

-- ─── Settings sub-screen ───

function CozyFocusScreen:showSettings()
    local focus_screen = self
    local dialog
    dialog = ButtonDialog:new{
        title = _("✦ Focus Settings ✦"),
        buttons = {
            {{
                text = T(_("Work: %1 min"), Config.FOCUS.work_duration),
                callback = function()
                    UIManager:close(dialog)
                    UIManager:show(SpinWidget:new{
                        title = _("Work Duration (minutes)"),
                        value = Config.FOCUS.work_duration,
                        value_min = 5, value_max = 60, value_step = 5,
                        ok_always_enabled = true,
                        callback = function(spin)
                            Config.FOCUS.work_duration = spin.value
                            Database:setPref("focus_work_duration", tostring(spin.value))
                            UIManager:close(spin)
                            focus_screen:refresh()
                            focus_screen:showSettings()
                        end,
                    })
                end,
            }},
            {{
                text = T(_("Short break: %1 min"), Config.FOCUS.short_break),
                callback = function()
                    UIManager:close(dialog)
                    UIManager:show(SpinWidget:new{
                        title = _("Short Break (minutes)"),
                        value = Config.FOCUS.short_break,
                        value_min = 1, value_max = 15, value_step = 1,
                        ok_always_enabled = true,
                        callback = function(spin)
                            Config.FOCUS.short_break = spin.value
                            Database:setPref("focus_short_break", tostring(spin.value))
                            UIManager:close(spin)
                            focus_screen:showSettings()
                        end,
                    })
                end,
            }},
            {{
                text = T(_("Long break: %1 min"), Config.FOCUS.long_break),
                callback = function()
                    UIManager:close(dialog)
                    UIManager:show(SpinWidget:new{
                        title = _("Long Break (minutes)"),
                        value = Config.FOCUS.long_break,
                        value_min = 5, value_max = 30, value_step = 5,
                        ok_always_enabled = true,
                        callback = function(spin)
                            Config.FOCUS.long_break = spin.value
                            Database:setPref("focus_long_break", tostring(spin.value))
                            UIManager:close(spin)
                            focus_screen:showSettings()
                        end,
                    })
                end,
            }},
            {{
                text = T(_("Long break after: %1 sessions"), Config.FOCUS.sessions_before_long_break),
                callback = function()
                    UIManager:close(dialog)
                    UIManager:show(SpinWidget:new{
                        title = _("Sessions Before Long Break"),
                        value = Config.FOCUS.sessions_before_long_break,
                        value_min = 2, value_max = 8, value_step = 1,
                        ok_always_enabled = true,
                        callback = function(spin)
                            Config.FOCUS.sessions_before_long_break = spin.value
                            Database:setPref("focus_sessions_before_long", tostring(spin.value))
                            UIManager:close(spin)
                            focus_screen:showSettings()
                        end,
                    })
                end,
            }},
            {{
                text = _("Close"),
                callback = function() UIManager:close(dialog) end,
            }},
        },
    }
    UIManager:show(dialog)
end

-- ─── Paint ───

function CozyFocusScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end

-- ─────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────

function FocusMode.show(ui, on_close_callback)
    ui_ref = ui
    if FocusMode._current_instance then
        UIManager:close(FocusMode._current_instance)
        FocusMode._current_instance = nil
    end
    local screen = CozyFocusScreen:new{
        ui = ui,
        on_close_callback = on_close_callback,
    }
    UIManager:show(screen)
end

function FocusMode.close()
    if FocusMode._current_instance then
        UIManager:close(FocusMode._current_instance)
        FocusMode._current_instance = nil
    end
end

--- Load saved settings from DB into Config on startup
function FocusMode.loadSettings()
    loadGameData()
    local wd = Database:getPref("focus_work_duration", nil)
    if wd then Config.FOCUS.work_duration = tonumber(wd) or 25 end
    local sb = Database:getPref("focus_short_break", nil)
    if sb then Config.FOCUS.short_break = tonumber(sb) or 5 end
    local lb = Database:getPref("focus_long_break", nil)
    if lb then Config.FOCUS.long_break = tonumber(lb) or 15 end
    local sl = Database:getPref("focus_sessions_before_long", nil)
    if sl then Config.FOCUS.sessions_before_long_break = tonumber(sl) or 4 end
end

--- Get a summary string for the home screen stats bar
function FocusMode.getStatsForHome()
    loadGameData()
    if timer_state.active then
        local label = timer_state.is_break and "break" or "focus"
        return string.format("%s %s", label, formatTime(timer_state.time_remaining))
    end
    if game_data.sessions_today and game_data.sessions_today > 0 then
        return string.format("Lv.%d · %d focus today", game_data.level or 1, game_data.sessions_today)
    end
    return nil
end

--- Returns timer display info for the header countdown.
-- Called by CozyUI.buildScreenHeader via the getTimerDisplay provider.
-- @return table {text="MM:SS", label="Focus"} or nil if no timer active
function FocusMode.getTimerDisplay()
    if not timer_state.active then return nil end
    local label = timer_state.is_break
        and (timer_state.session_type == "long_break" and "Break" or "Break")
        or "Focus"
    if timer_state.paused then label = "Paused" end
    return {
        text = formatTime(timer_state.time_remaining),
        label = label,
    }
end

-- Register with CozyUI so every screen header shows the countdown
CozyUI.getTimerDisplay = FocusMode.getTimerDisplay

return FocusMode
