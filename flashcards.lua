-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         flashcards.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-10
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Flashcards hub with two-tab interface: Stacks
--       (deck tiles) and All Cards (flat list). Reads
--       from cozy_flashcards.db. Decks live in the
--       flashcards DB; categories/tags in cozyhome.db.
--
--       Includes a self-contained review engine so
--       Cozy Home works without Cozy Flashcards installed.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - lib/cozyui.lua
--       - lib/database.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

-- ============================================
-- IMPORTS
-- ============================================

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
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
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local Config = require("config")
local CozyUI = require("lib/cozyui")

-- ============================================
-- CONSTANTS
-- ============================================

local TAB_STACKS = "stacks"
local TAB_ALLCARDS = "allcards"

-- Grayscale palette shortcuts
local BLACK      = Blitbuffer.COLOR_BLACK
local DARK_GRAY  = Blitbuffer.COLOR_DARK_GRAY
local GRAY       = Blitbuffer.COLOR_GRAY
local LIGHT_GRAY = Blitbuffer.gray(0.85)
local WHITE      = Blitbuffer.COLOR_WHITE

-- ============================================
-- FLASHCARD DATABASE BRIDGE
-- ============================================
-- Direct read/write access to cozy_flashcards.db.

local CardDB = {}

function CardDB.openConn()
    local DataStorage = require("datastorage")
    local SQ3 = require("lua-ljsqlite3/init")
    local lfs = require("libs/libkoreader-lfs")
    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
    local attr = lfs.attributes(db_path)
    if not attr then return nil end
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok then return nil end

    -- Migration: add learning_step column (safe to run multiple times)
    pcall(function()
        conn:exec("ALTER TABLE flashcards ADD COLUMN learning_step INTEGER DEFAULT 0;")
    end)

    return conn
end

function CardDB.isAvailable()
    local conn = CardDB.openConn()
    if conn then
        pcall(function() conn:close() end)
        return true
    end
    return false
end

--- Get overall flashcard counts.
function CardDB.getCounts()
    local counts = { total = 0, due_today = 0, new = 0, learning = 0, review = 0, suspended = 0, mastered = 0 }
    local conn = CardDB.openConn()
    if not conn then return counts end

    pcall(function()
        local s1 = conn:prepare("SELECT COUNT(*) FROM flashcards")
        if s1 then local r = s1:step(); if r then counts.total = tonumber(r[1]) or 0 end; s1:close() end

        local s2 = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE suspended = 0 AND (next_review IS NULL OR date(next_review) <= date('now', 'localtime'))")
        if s2 then local r = s2:step(); if r then counts.due_today = tonumber(r[1]) or 0 end; s2:close() end

        local s3 = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE suspended = 0 AND state = 'new'")
        if s3 then local r = s3:step(); if r then counts.new = tonumber(r[1]) or 0 end; s3:close() end

        local s4 = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE suspended = 0 AND (state = 'learning' OR state = 'relearning')")
        if s4 then local r = s4:step(); if r then counts.learning = tonumber(r[1]) or 0 end; s4:close() end

        local s5 = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE suspended = 0 AND state = 'review'")
        if s5 then local r = s5:step(); if r then counts.review = tonumber(r[1]) or 0 end; s5:close() end

        local s6 = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE suspended = 1")
        if s6 then local r = s6:step(); if r then counts.suspended = tonumber(r[1]) or 0 end; s6:close() end

        local s7 = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE suspended = 0 AND interval_days >= 21")
        if s7 then local r = s7:step(); if r then counts.mastered = tonumber(r[1]) or 0 end; s7:close() end
    end)

    pcall(function() conn:close() end)
    return counts
end

--- Get all decks with counts (reads from decks table in flashcard DB).
function CardDB.getAllDecks()
    local decks = {}
    local conn = CardDB.openConn()
    if not conn then return decks end

    pcall(function()
        -- Ensure decks table exists (in case user hasn't opened flashcards plugin yet)
        pcall(function()
            conn:exec([[
                CREATE TABLE IF NOT EXISTS decks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    description TEXT,
                    created_at TEXT DEFAULT (datetime('now', 'localtime')),
                    updated_at TEXT DEFAULT (datetime('now', 'localtime')),
                    sort_order INTEGER DEFAULT 0
                );
            ]])
            conn:exec("INSERT OR IGNORE INTO decks (id, name, description) VALUES (1, 'General', 'Default deck for all cards')")
        end)

        -- Ensure deck_id column exists on flashcards
        pcall(function()
            conn:exec("ALTER TABLE flashcards ADD COLUMN deck_id INTEGER DEFAULT 1;")
        end)

        local stmt = conn:prepare(
            "SELECT id, name, description, sort_order FROM decks ORDER BY sort_order ASC, name ASC"
        )
        if not stmt then return end

        local row = stmt:step()
        while row do
            table.insert(decks, {
                id = tonumber(row[1]),
                name = row[2],
                description = row[3],
                sort_order = tonumber(row[4]) or 0,
                total = 0, new_count = 0, learning_count = 0,
                due_count = 0, mastered_count = 0,
            })
            row = stmt:step()
        end
        stmt:close()

        -- Fill counts per deck
        for __, deck in ipairs(decks) do
            local cs = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE deck_id = ? AND suspended = 0")
            if cs then cs:bind(deck.id); local r = cs:step(); deck.total = (r and tonumber(r[1])) or 0; cs:close() end

            local ns = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE deck_id = ? AND suspended = 0 AND state = 'new'")
            if ns then ns:bind(deck.id); local r = ns:step(); deck.new_count = (r and tonumber(r[1])) or 0; ns:close() end

            local ls = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE deck_id = ? AND suspended = 0 AND (state = 'learning' OR state = 'relearning')")
            if ls then ls:bind(deck.id); local r = ls:step(); deck.learning_count = (r and tonumber(r[1])) or 0; ls:close() end

            local ds = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE deck_id = ? AND suspended = 0 AND (next_review IS NULL OR date(next_review) <= date('now', 'localtime'))")
            if ds then ds:bind(deck.id); local r = ds:step(); deck.due_count = (r and tonumber(r[1])) or 0; ds:close() end

            local ms = conn:prepare("SELECT COUNT(*) FROM flashcards WHERE deck_id = ? AND suspended = 0 AND interval_days >= 21")
            if ms then ms:bind(deck.id); local r = ms:step(); deck.mastered_count = (r and tonumber(r[1])) or 0; ms:close() end
        end
    end)

    pcall(function() conn:close() end)
    return decks
end

--- Create a new deck in the flashcard DB.
function CardDB.createDeck(name, description)
    if not name or name == "" then return nil end
    local conn = CardDB.openConn()
    if not conn then return nil end

    local deck_id = nil
    pcall(function()
        local stmt = conn:prepare("INSERT INTO decks (name, description) VALUES (?, ?)")
        if stmt then
            stmt:bind(name, description)
            stmt:step()
            stmt:close()
            local id_stmt = conn:prepare("SELECT last_insert_rowid()")
            if id_stmt then
                local r = id_stmt:step()
                if r then deck_id = tonumber(r[1]) end
                id_stmt:close()
            end
        end
    end)

    pcall(function() conn:close() end)
    return deck_id
end

--- Rename a deck.
function CardDB.renameDeck(deck_id, new_name)
    if not new_name or new_name == "" then return false end
    local conn = CardDB.openConn()
    if not conn then return false end

    local success = false
    pcall(function()
        local stmt = conn:prepare("UPDATE decks SET name = ?, updated_at = datetime('now', 'localtime') WHERE id = ?")
        if stmt then stmt:bind(new_name, deck_id); stmt:step(); stmt:close(); success = true end
    end)

    pcall(function() conn:close() end)
    return success
end

--- Delete a deck (moves cards to General). Cannot delete General (id=1).
function CardDB.deleteDeck(deck_id)
    if deck_id == 1 then return false end
    local conn = CardDB.openConn()
    if not conn then return false end

    pcall(function()
        local ms = conn:prepare("UPDATE flashcards SET deck_id = 1 WHERE deck_id = ?")
        if ms then ms:bind(deck_id); ms:step(); ms:close() end
        local ds = conn:prepare("DELETE FROM decks WHERE id = ?")
        if ds then ds:bind(deck_id); ds:step(); ds:close() end
    end)

    pcall(function() conn:close() end)
    return true
end

--- Move a card to a deck.
function CardDB.moveCardToDeck(card_id, deck_id)
    local conn = CardDB.openConn()
    if not conn then return false end

    local success = false
    pcall(function()
        local stmt = conn:prepare("UPDATE flashcards SET deck_id = ? WHERE id = ?")
        if stmt then stmt:bind(deck_id, card_id); stmt:step(); stmt:close(); success = true end
    end)

    pcall(function() conn:close() end)
    return success
end

--- Get a page of cards, optionally filtered by book_path, deck_id, or suspended status.
-- @param page number: 1-based page number
-- @param per_page number: cards per page
-- @param book_filter string|nil: filter by book_path
-- @param deck_filter number|nil: filter by deck_id
-- @param suspended_filter string|nil: nil = active only, "only" = suspended only
-- @return cards table, total number
function CardDB.getCards(page, per_page, book_filter, deck_filter, suspended_filter)
    local cards = {}
    local total = 0
    local conn = CardDB.openConn()
    if not conn then return cards, total end

    pcall(function()
        local where_parts = {}
        local bind_vals = {}
        if suspended_filter == "only" then
            table.insert(where_parts, "suspended = 1")
        else
            table.insert(where_parts, "suspended = 0")
        end
        if book_filter then
            table.insert(where_parts, "book_path = ?")
            table.insert(bind_vals, book_filter)
        end
        if deck_filter then
            table.insert(where_parts, "deck_id = ?")
            table.insert(bind_vals, deck_filter)
        end
        local where = ""
        if #where_parts > 0 then
            where = "WHERE " .. table.concat(where_parts, " AND ")
        end

        -- Count
        local cs = conn:prepare("SELECT COUNT(*) FROM flashcards " .. where)
        if cs then
            if #bind_vals > 0 then cs:bind(unpack(bind_vals)) end
            local r = cs:step()
            if r then total = tonumber(r[1]) or 0 end
            cs:close()
        end

        -- Fetch page
        local offset = (page - 1) * per_page
        local fetch_vals = {}
        for __, v in ipairs(bind_vals) do table.insert(fetch_vals, v) end
        table.insert(fetch_vals, per_page)
        table.insert(fetch_vals, offset)

        local qs = conn:prepare(
            "SELECT id, book_path, book_title, front, back, state, interval_days, "
            .. "ease_factor, review_count, correct_count, suspended, next_review, created_at, deck_id "
            .. "FROM flashcards " .. where
            .. " ORDER BY created_at DESC LIMIT ? OFFSET ?"
        )
        if qs then
            qs:bind(unpack(fetch_vals))
            for row in qs:rows() do
                table.insert(cards, {
                    id = tonumber(row[1]),
                    book_path = row[2],
                    book_title = row[3],
                    front = row[4],
                    back = row[5],
                    state = row[6] or "new",
                    interval_days = tonumber(row[7]) or 0,
                    ease_factor = tonumber(row[8]) or 2.5,
                    review_count = tonumber(row[9]) or 0,
                    correct_count = tonumber(row[10]) or 0,
                    suspended = tonumber(row[11]) or 0,
                    next_review = row[12],
                    created_at = row[13],
                    deck_id = tonumber(row[14]) or 1,
                })
            end
            qs:close()
        end
    end)

    pcall(function() conn:close() end)
    return cards, total
end

--- Get distinct books that have flashcards.
function CardDB.getBooksWithCards()
    local books = {}
    local conn = CardDB.openConn()
    if not conn then return books end

    pcall(function()
        local stmt = conn:prepare(
            "SELECT book_path, book_title, COUNT(*) as cnt "
            .. "FROM flashcards WHERE book_path IS NOT NULL AND book_path != '' "
            .. "GROUP BY book_path ORDER BY cnt DESC"
        )
        if stmt then
            for row in stmt:rows() do
                table.insert(books, {
                    book_path = row[1],
                    book_title = row[2] or row[1]:match("([^/]+)$") or "Unknown",
                    card_count = tonumber(row[3]) or 0,
                })
            end
            stmt:close()
        end
    end)

    pcall(function() conn:close() end)
    return books
end

--- Get a single card by ID.
function CardDB.getCard(card_id)
    local card = nil
    local conn = CardDB.openConn()
    if not conn then return nil end

    pcall(function()
        local stmt = conn:prepare(
            "SELECT id, book_path, book_title, front, back, source_text, source_page, "
            .. "source_chapter, state, interval_days, ease_factor, review_count, "
            .. "correct_count, suspended, next_review, last_reviewed, created_at, tags, deck_id, "
            .. "learning_step "
            .. "FROM flashcards WHERE id = ?"
        )
        if stmt then
            stmt:bind(card_id)
            local row = stmt:step()
            if row then
                card = {
                    id = tonumber(row[1]),
                    book_path = row[2],
                    book_title = row[3],
                    front = row[4],
                    back = row[5],
                    source_text = row[6],
                    source_page = tonumber(row[7]),
                    source_chapter = row[8],
                    state = row[9] or "new",
                    interval_days = tonumber(row[10]) or 0,
                    ease_factor = tonumber(row[11]) or 2.5,
                    review_count = tonumber(row[12]) or 0,
                    correct_count = tonumber(row[13]) or 0,
                    suspended = tonumber(row[14]) or 0,
                    next_review = row[15],
                    last_reviewed = row[16],
                    created_at = row[17],
                    tags = row[18],
                    deck_id = tonumber(row[19]) or 1,
                    learning_step = tonumber(row[20]) or 0,
                }
            end
            stmt:close()
        end
    end)

    pcall(function() conn:close() end)
    return card
end

--- Update a card's front and/or back text.
-- @param card_id number: Card ID
-- @param front string|nil: New front text (nil = no change)
-- @param back string|nil: New back text (nil = no change)
-- @return boolean: true if updated
function CardDB.updateCardText(card_id, front, back)
    if not front and not back then return false end
    local conn = CardDB.openConn()
    if not conn then return false end
    local ok = false
    pcall(function()
        local parts = {}
        local vals = {}
        if front then
            table.insert(parts, "front = ?")
            table.insert(vals, front)
        end
        if back then
            table.insert(parts, "back = ?")
            table.insert(vals, back)
        end
        table.insert(vals, card_id)
        local sql = "UPDATE flashcards SET " .. table.concat(parts, ", ") .. " WHERE id = ?"
        local stmt = conn:prepare(sql)
        if stmt then
            stmt:bind(unpack(vals))
            stmt:step()
            stmt:close()
            ok = true
        end
    end)
    pcall(function() conn:close() end)
    return ok
end

--- Delete a card by ID.
function CardDB.deleteCard(card_id)
    local conn = CardDB.openConn()
    if not conn then return false end
    local success = false
    pcall(function()
        local stmt = conn:prepare("DELETE FROM flashcards WHERE id = ?")
        if stmt then stmt:bind(card_id); stmt:step(); stmt:close(); success = true end
    end)
    pcall(function() conn:close() end)
    return success
end

--- Toggle suspended status for a card.
function CardDB.toggleSuspend(card_id)
    local conn = CardDB.openConn()
    if not conn then return false end
    local success = false
    pcall(function()
        local stmt = conn:prepare(
            "UPDATE flashcards SET suspended = CASE WHEN suspended = 1 THEN 0 ELSE 1 END WHERE id = ?"
        )
        if stmt then stmt:bind(card_id); stmt:step(); stmt:close(); success = true end
    end)
    pcall(function() conn:close() end)
    return success
end

-- ============================================
-- REVIEW ENGINE (self-contained, no external plugin needed)
-- ============================================

--- Ensure review_history and daily_stats tables exist.
local function ensureReviewTables(conn)
    pcall(function()
        conn:exec([[
            CREATE TABLE IF NOT EXISTS review_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                card_id INTEGER NOT NULL,
                reviewed_at TEXT DEFAULT (datetime('now', 'localtime')),
                rating INTEGER NOT NULL,
                time_taken_ms INTEGER,
                old_interval INTEGER,
                new_interval INTEGER,
                old_ease REAL,
                new_ease REAL
            );
        ]])
        conn:exec([[
            CREATE TABLE IF NOT EXISTS daily_stats (
                date TEXT PRIMARY KEY,
                cards_reviewed INTEGER DEFAULT 0,
                cards_correct INTEGER DEFAULT 0,
                time_spent_seconds INTEGER DEFAULT 0
            );
        ]])
    end)
end

--- Get the active scheduling preset.
-- Reads from G_reader_settings (shared with cozyflashcards plugin).
-- Falls back to the "relaxed" preset if the setting is missing or invalid.
-- @return table: the preset definition from Config.SCHEDULING_PRESETS
local function getSchedulingPreset()
    local G_reader_settings = require("luasettings"):open(
        require("datastorage"):getSettingsDir() .. "/settings.reader.lua"
    )
    local fc_settings = G_reader_settings:readSetting("cozyflashcards") or {}
    local key = fc_settings.scheduling_preset or Config.DEFAULT_SCHEDULING_PRESET
    local preset = Config.SCHEDULING_PRESETS[key]
    if not preset then
        preset = Config.SCHEDULING_PRESETS[Config.DEFAULT_SCHEDULING_PRESET]
    end
    return preset
end

--- Format a minute-based interval into a human-readable label.
-- @param minutes number: interval in minutes
-- @return string: e.g. "10m", "2h", "4d"
local function formatInterval(minutes)
    if minutes < 60 then
        return tostring(math.floor(minutes)) .. "m"
    elseif minutes < 1440 then
        local hours = math.floor(minutes / 60)
        return tostring(hours) .. "h"
    else
        local days = math.floor(minutes / 1440)
        return tostring(days) .. "d"
    end
end

--- Convert conn:exec() result columns into an array of card tables.
local function rowsToCards(results)
    if not results or not results.id then return {} end
    local cards = {}
    for i = 1, #results.id do
        table.insert(cards, {
            id = tonumber(results.id[i]),
            book_path = results.book_path[i],
            book_title = results.book_title[i],
            front = results.front[i],
            back = results.back[i],
            state = results.state[i] or "new",
            interval_days = tonumber(results.interval_days[i]) or 0,
            ease_factor = tonumber(results.ease_factor[i]) or 2.5,
            review_count = tonumber(results.review_count[i]) or 0,
            correct_count = tonumber(results.correct_count[i]) or 0,
            suspended = tonumber(results.suspended[i]) or 0,
            next_review = results.next_review[i],
            last_reviewed = results.last_reviewed[i],
            deck_id = results.deck_id and tonumber(results.deck_id[i]) or 1,
            learning_step = results.learning_step and tonumber(results.learning_step[i]) or 0,
        })
    end
    return cards
end

--- Fetch due cards for review (all decks).
function CardDB.getDueCards(limit, new_card_limit)
    local conn = CardDB.openConn()
    if not conn then return {} end
    limit = limit or 100

    local cards = {}
    pcall(function()
        -- Review/learning/relearning cards first
        local review_sql = string.format([[
            SELECT * FROM flashcards
            WHERE suspended = 0 AND state != 'new'
            AND next_review IS NOT NULL
            AND date(next_review) <= date('now', 'localtime')
            ORDER BY
                CASE WHEN state = 'relearning' THEN 0
                     WHEN state = 'learning' THEN 1 ELSE 2 END,
                next_review ASC
            LIMIT %d
        ]], limit)
        cards = rowsToCards(conn:exec(review_sql))

        -- Then new cards up to remaining capacity
        local remaining = limit - #cards
        if remaining > 0 then
            local new_limit = remaining
            if new_card_limit and new_card_limit > 0 then
                local today = os.date("%Y-%m-%d")
                local cs = conn:prepare(
                    "SELECT COUNT(*) FROM flashcards WHERE state != 'new' AND date(last_reviewed) = ? AND review_count = 1"
                )
                cs:bind(today)
                local row = cs:step()
                local already = (row and tonumber(row[1])) or 0
                cs:close()
                new_limit = math.min(remaining, math.max(0, new_card_limit - already))
            end
            if new_limit > 0 then
                local new_sql = string.format([[
                    SELECT * FROM flashcards
                    WHERE suspended = 0
                    AND state = 'new' AND (next_review IS NULL OR date(next_review) <= date('now', 'localtime'))
                    ORDER BY created_at ASC LIMIT %d
                ]], new_limit)
                for __, c in ipairs(rowsToCards(conn:exec(new_sql))) do
                    table.insert(cards, c)
                end
            end
        end
    end)

    pcall(function() conn:close() end)
    return cards
end

--- Fetch due cards filtered by deck IDs.
function CardDB.getDueCardsByDecks(deck_ids, limit, new_card_limit)
    if not deck_ids or #deck_ids == 0 then return {} end
    local conn = CardDB.openConn()
    if not conn then return {} end
    limit = limit or 100

    -- Build safe IN clause
    local id_strs = {}
    for __, id in ipairs(deck_ids) do
        local num = tonumber(id)
        if num then table.insert(id_strs, tostring(math.floor(num))) end
    end
    if #id_strs == 0 then pcall(function() conn:close() end); return {} end
    local in_clause = "(" .. table.concat(id_strs, ",") .. ")"

    local cards = {}
    pcall(function()
        local review_sql = string.format([[
            SELECT * FROM flashcards
            WHERE suspended = 0 AND deck_id IN %s
            AND state != 'new' AND next_review IS NOT NULL
            AND date(next_review) <= date('now', 'localtime')
            ORDER BY
                CASE WHEN state = 'relearning' THEN 0
                     WHEN state = 'learning' THEN 1 ELSE 2 END,
                next_review ASC
            LIMIT %d
        ]], in_clause, limit)
        cards = rowsToCards(conn:exec(review_sql))

        local remaining = limit - #cards
        if remaining > 0 then
            local new_limit = remaining
            if new_card_limit and new_card_limit > 0 then
                local today = os.date("%Y-%m-%d")
                local cs = conn:prepare(
                    "SELECT COUNT(*) FROM flashcards WHERE deck_id IN " .. in_clause
                    .. " AND state != 'new' AND date(last_reviewed) = ? AND review_count = 1"
                )
                cs:bind(today)
                local row = cs:step()
                local already = (row and tonumber(row[1])) or 0
                cs:close()
                new_limit = math.min(remaining, math.max(0, new_card_limit - already))
            end
            if new_limit > 0 then
                local new_sql = string.format([[
                    SELECT * FROM flashcards
                    WHERE suspended = 0 AND deck_id IN %s
                    AND state = 'new' AND (next_review IS NULL OR date(next_review) <= date('now', 'localtime'))
                    ORDER BY created_at ASC LIMIT %d
                ]], in_clause, new_limit)
                for __, c in ipairs(rowsToCards(conn:exec(new_sql))) do
                    table.insert(cards, c)
                end
            end
        end
    end)

    pcall(function() conn:close() end)
    return cards
end

--- Record a review using SM-2 algorithm. Updates card state + logs history.
-- @param card_id number: flashcard ID
-- @param rating number: 0 (Again), 2 (Hard), 3 (Good), 5 (Easy)
-- @param time_taken_ms number: milliseconds spent on card
-- @return boolean: true if successful
function CardDB.recordReview(card_id, rating, time_taken_ms)
    local card = CardDB.getCard(card_id)
    if not card then return false end
    local conn = CardDB.openConn()
    if not conn then return false end

    local MIN_EASE = 1.3
    local DEFAULT_EASE = 2.5

    pcall(function()
        ensureReviewTables(conn)

        local old_interval = tonumber(card.interval_days) or 0
        local old_ease = tonumber(card.ease_factor) or DEFAULT_EASE
        rating = tonumber(rating) or 0
        local is_correct = rating >= 2  -- Hard (2) and above count as "not failed"

        local new_interval, new_ease, new_state
        local is_new = (card.state == "new") or ((card.review_count or 0) == 0)
        if rating >= 3 then
            -- Good (3) or Easy (5): standard SM-2 progression
            new_ease = old_ease + (0.1 - (5 - rating) * (0.08 + (5 - rating) * 0.02))
            new_ease = math.max(MIN_EASE, tonumber(new_ease) or MIN_EASE)

            if is_new then
                -- Graduating intervals for new cards: Good=1d, Easy=4d
                if rating == 5 then
                    new_interval = 4
                else
                    new_interval = 1
                end
            elseif old_interval == 0 then new_interval = 1
            elseif old_interval == 1 then new_interval = 3
            else new_interval = math.floor(tonumber(old_interval * new_ease) or 1) end

            -- Easy bonus for non-new cards: 1.3× multiplier
            if rating == 5 and not is_new and new_interval > 1 then
                new_interval = math.floor(new_interval * 1.3)
            end

            new_state = "review"
        elseif rating == 2 then
            -- Hard: slight ease penalty, shorter interval than Good but still progresses
            new_ease = math.max(MIN_EASE, tonumber(old_ease - 0.15) or MIN_EASE)

            if is_new then
                -- New card + Hard: review again tomorrow (same as Good but with ease penalty)
                new_interval = 1
            elseif old_interval <= 1 then
                new_interval = 2
            else
                new_interval = math.max(2, math.floor(old_interval * 1.2))
            end
            new_state = "review"
        else
            -- Again (0): full reset — review again in 10 minutes
            new_ease = math.max(MIN_EASE, tonumber(old_ease - 0.2) or MIN_EASE)
            new_interval = 0
            new_state = (card.state == "review") and "relearning" or "learning"
        end

        -- For interval=0 (Again), schedule 10 minutes from now
        -- For interval>=1, schedule that many days out
        local next_review
        if new_interval <= 0 then
            next_review = os.date("%Y-%m-%d %H:%M:%S", os.time() + 600)
        else
            next_review = os.date("%Y-%m-%d", os.time() + (new_interval * 86400))
        end

        -- Update card
        local stmt = conn:prepare([[
            UPDATE flashcards SET
                interval_days = ?, ease_factor = ?, next_review = ?,
                last_reviewed = datetime('now', 'localtime'),
                review_count = review_count + 1,
                correct_count = correct_count + ?,
                state = ?
            WHERE id = ?
        ]])
        stmt:bind(new_interval, new_ease, next_review, is_correct and 1 or 0, new_state, card_id)
        stmt:step(); stmt:close()

        -- Log to review_history
        local h = conn:prepare([[
            INSERT INTO review_history
            (card_id, rating, time_taken_ms, old_interval, new_interval, old_ease, new_ease)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ]])
        h:bind(card_id, rating, time_taken_ms, old_interval, new_interval, old_ease, new_ease)
        h:step(); h:close()

        -- Update daily_stats
        local today = os.date("%Y-%m-%d")
        local correct_val = is_correct and 1 or 0
        local ds = conn:prepare([[
            INSERT INTO daily_stats (date, cards_reviewed, cards_correct)
            VALUES (?, 1, ?)
            ON CONFLICT(date) DO UPDATE SET
                cards_reviewed = cards_reviewed + 1,
                cards_correct = cards_correct + ?
        ]])
        ds:bind(today, correct_val, correct_val)
        ds:step(); ds:close()
    end)

    pcall(function() conn:close() end)
    return true
end

--- Create the flashcard database if it doesn't exist.
-- This bootstraps the DB so users can create cards without
-- needing the Cozy Flashcards plugin installed.
function CardDB.createDB()
    local DataStorage = require("datastorage")
    local SQ3 = require("lua-ljsqlite3/init")
    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok then return false end
    pcall(function()
        conn:exec([[
            CREATE TABLE IF NOT EXISTS flashcards (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                book_path TEXT, book_title TEXT,
                front TEXT NOT NULL, back TEXT NOT NULL,
                source_text TEXT, source_page INTEGER, source_chapter TEXT,
                card_type TEXT DEFAULT 'text', image_path TEXT,
                created_at TEXT DEFAULT (datetime('now', 'localtime')),
                last_reviewed TEXT, next_review TEXT,
                interval_days INTEGER DEFAULT 0,
                ease_factor REAL DEFAULT 2.5,
                review_count INTEGER DEFAULT 0, correct_count INTEGER DEFAULT 0,
                state TEXT DEFAULT 'new', tags TEXT,
                suspended INTEGER DEFAULT 0, deck_id INTEGER DEFAULT 1,
                learning_step INTEGER DEFAULT 0
            );
        ]])
        -- Migration for existing databases: add learning_step if missing
        pcall(function()
            conn:exec("ALTER TABLE flashcards ADD COLUMN learning_step INTEGER DEFAULT 0;")
        end)
        conn:exec([[
            CREATE TABLE IF NOT EXISTS decks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL, description TEXT,
                created_at TEXT DEFAULT (datetime('now', 'localtime')),
                updated_at TEXT DEFAULT (datetime('now', 'localtime')),
                sort_order INTEGER DEFAULT 0
            );
        ]])
        conn:exec("INSERT OR IGNORE INTO decks (id, name, description) VALUES (1, 'General', 'Default deck for all cards')")
        ensureReviewTables(conn)
    end)
    pcall(function() conn:close() end)
    return true
end

--- Get deck name lookup table {[deck_id] = name}.
function CardDB.getDeckNames()
    local names = {}
    local conn = CardDB.openConn()
    if not conn then return names end
    pcall(function()
        local stmt = conn:prepare("SELECT id, name FROM decks")
        if stmt then
            local row = stmt:step()
            while row do
                names[tonumber(row[1])] = row[2]
                row = stmt:step()
            end
            stmt:close()
        end
    end)
    pcall(function() conn:close() end)
    return names
end

-- ============================================
-- MODULE
-- ============================================

local Flashcards = {}
Flashcards._hub_instance = nil

-- ============================================
-- STATUS HELPERS
-- ============================================

local function statusLabel(card)
    if card.suspended == 1 then return "◦" end
    if card.state == "new" then return "○" end
    if card.state == "learning" or card.state == "relearning" then return "◐" end
    if (card.interval_days or 0) >= 21 then return "●" end
    if card.state == "review" then return "◐" end
    return "○"
end

-- ============================================
-- PROGRESS BAR HELPER
-- ============================================

--- Build a text-based progress bar for a deck.
-- Shows mastered vs total proportion.
local function buildProgressBar(deck, bar_w)
    local total = deck.total
    local bar_chars = Config.UI.progress_bar_chars or 12
    if bar_chars < 5 then bar_chars = 5 end
    if bar_chars > 20 then bar_chars = 20 end

    if total == 0 then
        return TextWidget:new{
            face = Font:getFace("smallinfofont"),
            text = string.rep("░", bar_chars),
            fgcolor = LIGHT_GRAY,
            max_width = bar_w,
        }
    end

    local filled_count = deck.mastered_count
    local filled = math.floor((filled_count / total) * bar_chars)
    if filled > bar_chars then filled = bar_chars end

    local bar_str = string.rep("▓", filled) .. string.rep("░", bar_chars - filled)
    return TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = bar_str,
        fgcolor = DARK_GRAY,
        max_width = bar_w,
    }
end

-- ============================================
-- EMBEDDED REVIEW UI
-- ============================================
-- Self-contained study screen so Cozy Home doesn't
-- need the Cozy Flashcards plugin installed to review.

local function sp(h) return VerticalSpan:new{width = h} end

-- ── Shared UI helpers (matching Cozy Flashcards style) ──

local function buildReviewHeader(sw, content_w, title_text, close_callback, stats_callback)
    local title_widget = TextWidget:new{
        face = Font:getFace("tfont", 22),
        text = "☕ " .. _(title_text),
        fgcolor = BLACK,
    }
    local close_btn = Button:new{
        text = _("Close"),
        callback = close_callback,
        bordersize = 0, margin = 0,
        padding = 10, padding_h = 14,
        text_font_face = "cfont", text_font_size = 18,
    }
    local left_widget
    if stats_callback then
        left_widget = HorizontalGroup:new{
            Button:new{
                text = "◌ " .. _("Stats"),
                callback = stats_callback,
                bordersize = 0, margin = 0,
                padding = 10, padding_h = 14,
                text_font_face = "cfont", text_font_size = 18,
            },
        }
    else
        left_widget = HorizontalGroup:new{HorizontalSpan:new{width = 1}}
    end
    local bar_h = math.max(title_widget:getSize().h + 4, close_btn:getSize().h)
    -- Measure left and right, give title the remaining space
    local left_w = left_widget:getSize().w
    local close_w = close_btn:getSize().w
    local title_gap = 8
    local title_max_w = math.max(0, content_w - left_w - close_w - title_gap * 2)
    title_widget.max_width = title_max_w
    local bar = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{w = left_w, h = bar_h},
            left_widget,
        },
        HorizontalSpan:new{width = title_gap},
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

local function buildReviewDots(sw, content_w)
    local dot_count = math.floor(content_w / 8)
    local center = math.floor(dot_count / 2)
    local chars = {}
    for i = 1, dot_count do
        table.insert(chars, (i >= center - 2 and i <= center + 2) and "•" or "·")
    end
    local w = TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = table.concat(chars),
        fgcolor = LIGHT_GRAY,
    }
    return CenterContainer:new{ dimen = Geom:new{w = sw, h = w:getSize().h}, w }
end

local function buildReviewSectionDivider(sw, content_w, label)
    local lw = TextWidget:new{
        face = Font:getFace("smallinfofont"),
        text = "✦ " .. label .. " ✦",
        fgcolor = GRAY,
    }
    local line_w = math.floor((content_w - lw:getSize().w - 20) / 2)
    if line_w < 10 then line_w = 10 end
    return CenterContainer:new{
        dimen = Geom:new{w = sw, h = lw:getSize().h + 4},
        HorizontalGroup:new{
            align = "center",
            LineWidget:new{dimen = Geom:new{w = line_w, h = 1}, background = LIGHT_GRAY},
            HorizontalSpan:new{width = 10},
            lw,
            HorizontalSpan:new{width = 10},
            LineWidget:new{dimen = Geom:new{w = line_w, h = 1}, background = LIGHT_GRAY},
        },
    }
end

local function buildReviewStatRow(sw, content_w, label, value)
    local lw = TextWidget:new{ face = Font:getFace("cfont", 18), text = label, fgcolor = BLACK }
    local vw = TextWidget:new{ face = Font:getFace("cfont", 18), text = tostring(value), fgcolor = BLACK }
    local dot_w = content_w - lw:getSize().w - vw:getSize().w - 20
    local dot_count = math.max(3, math.floor(dot_w / 6))
    local dw = TextWidget:new{ face = Font:getFace("smallinfofont"), text = string.rep("·", dot_count), fgcolor = LIGHT_GRAY }
    return CenterContainer:new{
        dimen = Geom:new{w = sw, h = lw:getSize().h + 4},
        HorizontalGroup:new{
            align = "center", lw, HorizontalSpan:new{width = 8}, dw, HorizontalSpan:new{width = 8}, vw,
        },
    }
end

-- ── Session Complete Screen ──

local CozySessionCompleteScreen = InputContainer:extend{}

function CozySessionCompleteScreen:init()
    self.dimen = Geom:new{x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight()}
    self.covers_fullscreen = true
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    self:buildUI()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

function CozySessionCompleteScreen:buildUI()
    local sw = Screen:getWidth()
    local content_w = math.floor(sw * 0.82)
    local total = (self.correct or 0) + (self.incorrect or 0)
    local accuracy = total > 0 and math.floor(((self.correct or 0) / total) * 100) or 0
    local minutes = math.floor((self.total_time or 0) / 60)
    local seconds = (self.total_time or 0) % 60

    local header = buildReviewHeader(sw, content_w, "Session Complete", function() self:onClose() end)
    local dots = buildReviewDots(sw, content_w)

    local cheer
    if accuracy >= 90 then cheer = _("Outstanding! Nearly perfect!")
    elseif accuracy >= 70 then cheer = _("Great work! Keep it up!")
    elseif total > 0 then cheer = _("Every review strengthens your memory.")
    else cheer = _("Ready for next time!") end

    local cheer_widget = TextWidget:new{ face = Font:getFace("cfont", 20), text = cheer, fgcolor = BLACK }
    local cheer_box = FrameContainer:new{
        padding = 14, margin = 0, bordersize = 1, radius = 10, color = GRAY, background = WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = content_w - 30, h = cheer_widget:getSize().h + 12},
            cheer_widget,
        },
    }

    local done_btn = Button:new{
        text = _("Done"),
        callback = function() self:onClose() end,
        width = math.floor(content_w * 0.5),
        radius = 8, bordersize = 2,
        text_font_face = "cfont", text_font_size = 20, text_font_bold = true,
        padding_v = 10,
    }

    self.layout = VerticalGroup:new{
        align = "center",
        sp(14), header, sp(4), dots,
        sp(24),
        CenterContainer:new{ dimen = Geom:new{w = sw, h = cheer_box:getSize().h}, cheer_box },
        sp(20),
        buildReviewSectionDivider(sw, content_w, _("Results")),
        sp(12),
        buildReviewStatRow(sw, content_w, _("Cards reviewed"), total),
        sp(6),
        buildReviewStatRow(sw, content_w, _("Correct"), self.correct or 0),
        sp(6),
        buildReviewStatRow(sw, content_w, _("Incorrect"), self.incorrect or 0),
        sp(6),
        buildReviewStatRow(sw, content_w, _("Accuracy"), string.format("%d%%", accuracy)),
        sp(6),
        buildReviewStatRow(sw, content_w, _("Time"), string.format("%d:%02d", minutes, seconds)),
        sp(28),
        CenterContainer:new{ dimen = Geom:new{w = sw, h = done_btn:getSize().h}, done_btn },
        sp(14),
    }
    self[1] = self.layout
end

function CozySessionCompleteScreen:onClose()
    UIManager:close(self)
    UIManager:setDirty("all", "full")
    if self.on_close then self.on_close() end
end

function CozySessionCompleteScreen:paintTo(bb, x, y)
    self.dimen.x = x; self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self.layout then
        local sz = self.layout:getSize()
        self.layout:paintTo(bb, x + math.floor((self.dimen.w - sz.w) / 2), y)
    end
end

-- ── Study Screen (flashcard review) ──

local CozyStudyScreen = InputContainer:extend{}

function CozyStudyScreen:init()
    self.dimen = Geom:new{x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight()}
    self.covers_fullscreen = true
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self.cards = self.cards or {}
    self.current_index = 1
    self.showing_back = false
    self.start_time = os.time()
    self.card_start_time = os.time()
    self.correct = 0
    self.incorrect = 0
    self.deck_names = CardDB.getDeckNames()

    self:buildFrontLayout()
    self:buildBackLayout()
    self:loadNextCard()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

function CozyStudyScreen:buildFrontLayout()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local card_font_size = 22
    local card_inner_w = content_w - 40
    local card_h = math.floor(sh * 0.50)
    local card_inner_h = card_h - 40

    self.front_text_widget = TextBoxWidget:new{
        face = Font:getFace("cfont", card_font_size), text = "",
        width = card_inner_w, height = card_inner_h,
        alignment = "center", height_overflow_show_ellipsis = true,
    }
    self.front_card_frame = FrameContainer:new{
        padding = 18, margin = 0, bordersize = 1, radius = 12, color = GRAY, background = WHITE,
        CenterContainer:new{ dimen = Geom:new{w = card_inner_w, h = card_inner_h}, self.front_text_widget },
    }
    self.progress_widget = TextWidget:new{ face = Font:getFace("smallinfofont"), text = "", fgcolor = GRAY }
    self.show_answer_btn = Button:new{
        text = _("Show Answer"),
        callback = function() self:onShowAnswer() end,
        width = math.floor(content_w * 0.7),
        radius = 8, bordersize = 2,
        text_font_face = "cfont", text_font_size = 20, text_font_bold = true, padding_v = 10,
    }
    self.front_layout = VerticalGroup:new{
        align = "center",
        sp(14),
        buildReviewHeader(sw, content_w, "Review",
            function() self:onClose() end,
            function() self:showSessionStats() end),
        sp(4),
        buildReviewDots(sw, content_w),
        sp(6),
        CenterContainer:new{ dimen = Geom:new{w = sw, h = self.progress_widget:getSize().h + 4}, self.progress_widget },
        sp(10),
        CenterContainer:new{ dimen = Geom:new{w = sw, h = self.front_card_frame:getSize().h}, self.front_card_frame },
        sp(14),
        CenterContainer:new{ dimen = Geom:new{w = sw, h = self.show_answer_btn:getSize().h}, self.show_answer_btn },
        sp(10),
    }
end

function CozyStudyScreen:buildBackLayout()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local card_font_size = 22
    local card_inner_w = content_w - 40
    local card_h = math.floor(sh * 0.45)
    local card_inner_h = card_h - 40

    self.back_text_widget = TextBoxWidget:new{
        face = Font:getFace("cfont", card_font_size), text = "",
        width = card_inner_w, height = card_inner_h,
        alignment = "center", height_overflow_show_ellipsis = true,
    }
    self.back_card_frame = FrameContainer:new{
        padding = 18, margin = 0, bordersize = 1, radius = 12, color = GRAY, background = WHITE,
        CenterContainer:new{ dimen = Geom:new{w = card_inner_w, h = card_inner_h}, self.back_text_widget },
    }
    self.back_progress_widget = TextWidget:new{ face = Font:getFace("smallinfofont"), text = "", fgcolor = GRAY }

    -- Rating buttons
    local btn_w = math.floor(sw * 0.20)
    local h_gap = HorizontalSpan:new{width = 6}

    self.interval_again = TextWidget:new{face = Font:getFace("smallinfofont"), text = "", fgcolor = GRAY}
    self.interval_hard  = TextWidget:new{face = Font:getFace("smallinfofont"), text = "", fgcolor = GRAY}
    self.interval_good  = TextWidget:new{face = Font:getFace("smallinfofont"), text = "", fgcolor = GRAY}
    self.interval_easy  = TextWidget:new{face = Font:getFace("smallinfofont"), text = "", fgcolor = GRAY}

    self.again_button = Button:new{ text = _("Again"), callback = function() self:onRate(0) end, width = btn_w, radius = 8, bordersize = 1, text_font_face = "cfont", text_font_size = 16 }
    self.hard_button  = Button:new{ text = _("Hard"),  callback = function() self:onRate(2) end, width = btn_w, radius = 8, bordersize = 1, text_font_face = "cfont", text_font_size = 16 }
    self.good_button  = Button:new{ text = _("Good"),  callback = function() self:onRate(3) end, width = btn_w, radius = 8, bordersize = 1, text_font_face = "cfont", text_font_size = 16 }
    self.easy_button  = Button:new{ text = _("Easy"),  callback = function() self:onRate(5) end, width = btn_w, radius = 8, bordersize = 1, text_font_face = "cfont", text_font_size = 16 }

    local function ratingCol(lbl, btn)
        return VerticalGroup:new{
            align = "center",
            CenterContainer:new{dimen = Geom:new{w = btn_w, h = lbl:getSize().h}, lbl},
            VerticalSpan:new{width = 3},
            btn,
        }
    end
    local col_again = ratingCol(self.interval_again, self.again_button)
    local col_hard  = ratingCol(self.interval_hard, self.hard_button)
    local col_good  = ratingCol(self.interval_good, self.good_button)
    local col_easy  = ratingCol(self.interval_easy, self.easy_button)

    local rating_row = CenterContainer:new{
        dimen = Geom:new{w = sw, h = col_again:getSize().h},
        HorizontalGroup:new{
            align = "center",
            col_again, h_gap,
            col_hard, HorizontalSpan:new{width = 6},
            col_good, HorizontalSpan:new{width = 6},
            col_easy,
        },
    }

    self.back_layout = VerticalGroup:new{
        align = "center",
        sp(14),
        buildReviewHeader(sw, content_w, "Review",
            function() self:onClose() end,
            function() self:showSessionStats() end),
        sp(4),
        buildReviewDots(sw, content_w),
        sp(6),
        CenterContainer:new{ dimen = Geom:new{w = sw, h = self.back_progress_widget:getSize().h + 4}, self.back_progress_widget },
        sp(8),
        CenterContainer:new{ dimen = Geom:new{w = sw, h = self.back_card_frame:getSize().h}, self.back_card_frame },
        sp(12),
        rating_row,
        sp(10),
    }
end

function CozyStudyScreen:previewIntervals(card)
    local previews = {}
    local ratings = {again = 0, hard = 2, good = 3, easy = 5}
    local is_new = (card.state == "new") or ((card.review_count or 0) == 0)
    for name, rating in pairs(ratings) do
        local old_interval = card.interval_days or 0
        local old_ease = card.ease_factor or 2.5
        local new_interval
        if rating >= 3 then
            -- Good (3) or Easy (5): standard SM-2 progression
            local new_ease = old_ease + (0.1 - (5 - rating) * (0.08 + (5 - rating) * 0.02))
            new_ease = math.max(1.3, new_ease)
            if is_new then
                -- Graduating intervals for new cards: Good=1d, Easy=4d
                if rating == 5 then
                    new_interval = 4
                else
                    new_interval = 1
                end
            elseif old_interval == 0 then new_interval = 1
            elseif old_interval == 1 then new_interval = 3
            else new_interval = math.floor(old_interval * new_ease) end
            -- Easy bonus for non-new cards: 1.3× multiplier
            if rating == 5 and not is_new and new_interval > 1 then
                new_interval = math.floor(new_interval * 1.3)
            end
        elseif rating == 2 then
            -- Hard: slight ease penalty, shorter interval but still progresses
            if is_new then
                -- New card + Hard: review again tomorrow
                new_interval = 1
            elseif old_interval <= 1 then
                new_interval = 2
            else
                new_interval = math.max(2, math.floor(old_interval * 1.2))
            end
        else
            -- Again: full reset — review again in 10 minutes
            new_interval = 0
        end
        local label
        if new_interval <= 0 then label = "10m"
        elseif new_interval == 1 then label = "1d"
        else label = tostring(new_interval) .. "d" end
        previews[name] = {interval = new_interval, label = label}
    end
    return previews
end

function CozyStudyScreen:updateRatingLabels(previews)
    local function set_label(widget, key)
        local label = (previews and previews[key] and previews[key].label) or ""
        if widget then widget:setText(label) end
    end
    set_label(self.interval_again, "again")
    set_label(self.interval_hard,  "hard")
    set_label(self.interval_good,  "good")
    set_label(self.interval_easy,  "easy")
end

function CozyStudyScreen:loadNextCard()
    if self.current_index > #self.cards then
        self:showSessionComplete()
        return
    end
    local card = self.cards[self.current_index]
    if not card then self:showSessionComplete(); return end

    self.showing_back = false
    self.card_start_time = os.time()
    self.front_text_widget:setText(card.front or _("[No question]"))

    local progress_str = string.format(_("Card %d of %d"), self.current_index, #self.cards)
    local deck_name = self.deck_names[card.deck_id]
    if deck_name and deck_name ~= "General" then
        progress_str = progress_str .. " · " .. deck_name
    end
    self.progress_widget:setText(progress_str)
    self.show_answer_btn:enableDisable(true)
    self.active_layout = self.front_layout
    self[1] = self.front_layout
    self:refresh()
end

function CozyStudyScreen:onShowAnswer()
    local card = self.cards[self.current_index]
    if not card then self:loadNextCard(); return end
    self.showing_back = true
    local divider = "\n\n· · · · · · · · · · · · · · · ·\n\n"
    self.back_text_widget:setText((card.front or _("[No question]")) .. divider .. (card.back or _("[No answer]")))

    local back_progress = string.format(_("Card %d of %d"), self.current_index, #self.cards)
    local dn = self.deck_names[card.deck_id]
    if dn and dn ~= "General" then back_progress = back_progress .. " · " .. dn end
    self.back_progress_widget:setText(back_progress)

    self:updateRatingLabels(self:previewIntervals(card))
    self.active_layout = self.back_layout
    self[1] = self.back_layout
    self:refresh()
end

function CozyStudyScreen:onRate(rating)
    local card = self.cards[self.current_index]
    if not card then return end
    local time_taken = (os.time() - self.card_start_time) * 1000
    CardDB.recordReview(card.id, rating, time_taken)
    if rating >= 2 then self.correct = self.correct + 1  -- Hard (2) and above count as correct
    else self.incorrect = self.incorrect + 1 end
    self.current_index = self.current_index + 1
    self:loadNextCard()
end

function CozyStudyScreen:showSessionStats()
    local total_time = os.time() - self.start_time
    local minutes = math.floor(total_time / 60)
    local seconds = total_time % 60
    local reviewed = self.correct + self.incorrect
    local remaining = #self.cards - self.current_index + 1
    UIManager:show(InfoMessage:new{
        text = string.format(_("Session Progress\n\nReviewed: %d of %d\nRemaining: %d\n\nCorrect: %d\nIncorrect: %d\n\nTime: %d:%02d"),
            reviewed, #self.cards, remaining, self.correct, self.incorrect, minutes, seconds),
    })
end

function CozyStudyScreen:showSessionComplete()
    local total_time = os.time() - self.start_time
    UIManager:close(self)
    UIManager:setDirty("all", "full")
    UIManager:show(CozySessionCompleteScreen:new{
        correct = self.correct,
        incorrect = self.incorrect,
        total_time = total_time,
        on_close = self.on_session_complete,
    })
end

function CozyStudyScreen:onClose()
    local reviewed = self.correct + self.incorrect
    if reviewed > 0 and self.current_index <= #self.cards then
        UIManager:show(ConfirmBox:new{
            text = string.format(_("End session early?\n\nReviewed: %d of %d cards"), reviewed, #self.cards),
            ok_text = _("End"),
            cancel_text = _("Continue"),
            ok_callback = function()
                UIManager:close(self)
                UIManager:setDirty("all", "full")
                if self.on_session_complete then self.on_session_complete() end
            end,
        })
    else
        UIManager:close(self)
        UIManager:setDirty("all", "full")
        if self.on_session_complete then self.on_session_complete() end
    end
end

function CozyStudyScreen:refresh()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

function CozyStudyScreen:paintTo(bb, x, y)
    self.dimen.x = x; self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    local layout = self.active_layout or self.front_layout
    if layout then
        local sz = layout:getSize()
        layout:paintTo(bb, x + math.floor((self.dimen.w - sz.w) / 2), y)
    end
end

-- ============================================
-- CARD DETAIL SCREEN (full-page view)
-- ============================================
-- Shows a single flashcard's front, back, stats,
-- and action buttons on a full-screen page —
-- matching the Cozy study screen aesthetic.

local CozyCardDetailScreen = InputContainer:extend{
    name = "cozy_card_detail_screen",
    card = nil,          -- card table from CardDB.getCard()
    on_close = nil,      -- callback when back is tapped
    on_edit = nil,       -- callback(card_id)
    on_delete = nil,     -- callback(card_id)
    on_suspend = nil,    -- callback(card_id)
    on_move = nil,       -- callback(card_id)
}

function CozyCardDetailScreen:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    self:buildUI()
end

function CozyCardDetailScreen:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function CozyCardDetailScreen:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function CozyCardDetailScreen:onClose()
    UIManager:close(self)
    if self.on_close then
        UIManager:nextTick(self.on_close)
    end
    return true
end

function CozyCardDetailScreen:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local content_w = math.floor(sw * 0.85)
    local card = self.card
    local detail_screen = self

    local items = {}

    -- ── Header ──
    table.insert(items, sp(14))
    table.insert(items, buildReviewHeader(sw, content_w, "Card Detail",
        function() detail_screen:onClose() end, nil))
    table.insert(items, sp(4))
    table.insert(items, buildReviewDots(sw, content_w))
    table.insert(items, sp(12))

    -- ── Status badge ──
    local status_text = "○ New"
    if card.suspended == 1 then status_text = "◦ Suspended"
    elseif card.state == "learning" or card.state == "relearning" then status_text = "◐ Learning"
    elseif (card.interval_days or 0) >= 21 then status_text = "● Mastered"
    elseif card.state == "review" then status_text = "◐ Review"
    end

    local status_tw = TextWidget:new{
        face = Font:getFace("cfont", 16),
        text = status_text,
        fgcolor = card.suspended == 1 and GRAY or DARK_GRAY,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = status_tw:getSize().h + 4},
        status_tw,
    })
    table.insert(items, sp(10))

    -- ── Front card ──
    table.insert(items, buildReviewSectionDivider(sw, content_w, _("Front")))
    table.insert(items, sp(6))

    local card_inner_w = content_w - 40
    local front_text = card.front or _("[empty]")
    local front_tbw = TextBoxWidget:new{
        face = Font:getFace("cfont", 20),
        text = front_text,
        width = card_inner_w,
        alignment = "center",
        height_overflow_show_ellipsis = true,
    }
    -- Compute height: at least 60px, at most 25% of screen
    local front_h = math.min(
        math.max(front_tbw:getSize().h + 10, Screen:scaleBySize(60)),
        math.floor(sh * 0.25)
    )
    local front_frame = FrameContainer:new{
        padding = 16, margin = 0,
        bordersize = 1, radius = 12,
        color = GRAY, background = WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = card_inner_w, h = front_h},
            front_tbw,
        },
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = front_frame:getSize().h},
        front_frame,
    })
    table.insert(items, sp(12))

    -- ── Back card ──
    table.insert(items, buildReviewSectionDivider(sw, content_w, _("Back")))
    table.insert(items, sp(6))

    local back_text = card.back or _("[empty]")
    local back_tbw = TextBoxWidget:new{
        face = Font:getFace("cfont", 20),
        text = back_text,
        width = card_inner_w,
        alignment = "center",
        height_overflow_show_ellipsis = true,
    }
    local back_h = math.min(
        math.max(back_tbw:getSize().h + 10, Screen:scaleBySize(60)),
        math.floor(sh * 0.25)
    )
    local back_frame = FrameContainer:new{
        padding = 16, margin = 0,
        bordersize = 1, radius = 12,
        color = GRAY, background = WHITE,
        CenterContainer:new{
            dimen = Geom:new{w = card_inner_w, h = back_h},
            back_tbw,
        },
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = back_frame:getSize().h},
        back_frame,
    })
    table.insert(items, sp(14))

    -- ── Stats section ──
    table.insert(items, buildReviewSectionDivider(sw, content_w, _("Stats")))
    table.insert(items, sp(8))

    if card.review_count and card.review_count > 0 then
        table.insert(items, buildReviewStatRow(sw, content_w, _("Reviews"), card.review_count))
        table.insert(items, sp(4))
        table.insert(items, buildReviewStatRow(sw, content_w, _("Correct"), card.correct_count or 0))
        table.insert(items, sp(4))
        table.insert(items, buildReviewStatRow(sw, content_w, _("Interval"), (card.interval_days or 0) .. "d"))
        table.insert(items, sp(4))
        table.insert(items, buildReviewStatRow(sw, content_w, _("Ease"), string.format("%.2f", card.ease_factor or 2.5)))
        table.insert(items, sp(4))
    else
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = 24},
            TextWidget:new{
                face = Font:getFace("smallinfofont", 14),
                text = _("Not yet reviewed"),
                fgcolor = GRAY,
            },
        })
        table.insert(items, sp(4))
    end

    -- Book info
    if card.book_title and card.book_title ~= "" then
        local bt = card.book_title
        if #bt > 40 then bt = bt:sub(1, 37) .. "..." end
        table.insert(items, buildReviewStatRow(sw, content_w, _("Book"), bt))
        table.insert(items, sp(4))
    end

    -- Deck info
    local deck_names = CardDB.getDeckNames()
    local deck_name = deck_names[card.deck_id] or _("General")
    table.insert(items, buildReviewStatRow(sw, content_w, _("Deck"), deck_name))
    table.insert(items, sp(4))

    -- Source highlight (if present)
    if card.source_text and card.source_text ~= "" then
        table.insert(items, sp(4))
        local source_preview = card.source_text:gsub("\n", " ")
        if #source_preview > 80 then source_preview = source_preview:sub(1, 77) .. "..." end
        local source_tw = TextWidget:new{
            face = Font:getFace("smallinfofont", 12),
            text = "📖 " .. source_preview,
            fgcolor = GRAY,
            max_width = content_w,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{w = sw, h = source_tw:getSize().h + 4},
            source_tw,
        })
    end

    table.insert(items, sp(16))

    -- ── Action buttons ──
    local btn_w = math.floor(content_w * 0.40)
    local card_id = card.id

    local edit_btn = Button:new{
        text = _("Edit"),
        callback = function()
            UIManager:close(detail_screen)
            if detail_screen.on_edit then
                UIManager:nextTick(function() detail_screen.on_edit(card_id) end)
            end
        end,
        width = btn_w, radius = 8, bordersize = 1,
        text_font_face = "cfont", text_font_size = 16,
    }
    local suspend_label = card.suspended == 1 and _("Unsuspend") or _("Suspend")
    local suspend_btn = Button:new{
        text = suspend_label,
        callback = function()
            UIManager:close(detail_screen)
            if detail_screen.on_suspend then
                UIManager:nextTick(function() detail_screen.on_suspend(card_id) end)
            end
        end,
        width = btn_w, radius = 8, bordersize = 1,
        text_font_face = "cfont", text_font_size = 16,
    }

    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = edit_btn:getSize().h + 4},
        HorizontalGroup:new{
            align = "center",
            edit_btn,
            HorizontalSpan:new{width = 10},
            suspend_btn,
        },
    })
    table.insert(items, sp(8))

    local move_btn = Button:new{
        text = _("Move to Deck"),
        callback = function()
            UIManager:close(detail_screen)
            if detail_screen.on_move then
                UIManager:nextTick(function() detail_screen.on_move(card_id) end)
            end
        end,
        width = btn_w, radius = 8, bordersize = 1,
        text_font_face = "cfont", text_font_size = 16,
    }
    local delete_btn = Button:new{
        text = _("Delete"),
        callback = function()
            UIManager:show(ConfirmBox:new{
                text = _("Delete this flashcard?\n\nThis cannot be undone."),
                ok_text = _("Delete"),
                ok_callback = function()
                    UIManager:close(detail_screen)
                    if detail_screen.on_delete then
                        UIManager:nextTick(function() detail_screen.on_delete(card_id) end)
                    end
                end,
            })
        end,
        width = btn_w, radius = 8, bordersize = 1,
        text_font_face = "cfont", text_font_size = 16,
    }

    table.insert(items, CenterContainer:new{
        dimen = Geom:new{w = sw, h = move_btn:getSize().h + 4},
        HorizontalGroup:new{
            align = "center",
            move_btn,
            HorizontalSpan:new{width = 10},
            delete_btn,
        },
    })
    table.insert(items, sp(14))

    -- ── Assemble with scroll ──
    local content = VerticalGroup:new{align = "center"}
    for __, item in ipairs(items) do
        table.insert(content, item)
    end

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

function CozyCardDetailScreen:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then self[1]:paintTo(bb, x, y) end
end

-- ============================================
-- FLASHCARDS HUB SCREEN
-- ============================================

local FlashcardsHub = InputContainer:extend{
    name = "cozy_flashcards_hub",
    ui = nil,
    on_close_callback = nil,
    active_tab = TAB_STACKS,
    -- Stacks tab state
    selected_decks = {},       -- set of deck_id = true for multi-select
    select_mode = false,       -- whether checkboxes are visible
    -- All Cards tab state
    current_page = 1,
    book_filter = nil,
    book_filter_title = nil,
    deck_filter = nil,         -- filter card list by deck
    deck_filter_name = nil,
    suspended_filter = nil,    -- nil = active only, "only" = suspended only
}

function FlashcardsHub:init()
    self.dimen = Geom:new{
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.covers_fullscreen = true

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    Flashcards._hub_instance = self
    self:buildUI()
end

function FlashcardsHub:onShow()
    UIManager:setDirty(self, function()
        return "full", self.dimen
    end)
    return true
end

function FlashcardsHub:onCloseWidget()
    Flashcards._hub_instance = nil
    UIManager:setDirty(nil, function()
        return "full", self.dimen
    end)
end

function FlashcardsHub:onClose()
    UIManager:close(self)
    if self.on_close_callback then
        UIManager:nextTick(self.on_close_callback)
    end
    return true
end

-- ============================================
-- HUB UI
-- ============================================

function FlashcardsHub:buildUI()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local pad = Config.UI.content_padding
    local content_w = sw - pad * 2

    local hub = self
    local items = {}

    -- Check if flashcard DB exists
    if not CardDB.isAvailable() then
        self:buildNoDbUI(items, sw, sh, content_w, pad)
        self:assembleUI(items, sw, sh)
        return
    end

    -- ── HEADER ──
    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Flashcards",
        back_callback = function() hub:onClose() end,
        exit_callback = function() hub:onClose() end,
        show_parent = self,
    }))

    -- Thin separator
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 2 },
        LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
    })
    table.insert(items, VerticalSpan:new{ width = 6 })

    -- ── REVIEW ALL DUE BUTTON ──
    local counts = CardDB.getCounts()
    local review_text = counts.due_today > 0
        and string.format("Review All Due (%d)", counts.due_today)
        or "No Cards Due"

    local review_btn = Button:new{
        text = _(review_text),
        enabled = counts.due_today > 0,
        callback = function() hub:launchReview() end,
        bordersize = 2,
        radius = 8,
        text_font_bold = true,
        text_font_size = 16,
        padding_v = 10,
        width = math.floor(content_w * 0.92),
        show_parent = self,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = review_btn:getSize().h + 4 },
        review_btn,
    })
    table.insert(items, VerticalSpan:new{ width = 8 })

    -- ── TAB BAR ──
    local tab_h = Screen:scaleBySize(36)
    local stacks_active = self.active_tab == TAB_STACKS
    local cards_active = self.active_tab == TAB_ALLCARDS

    local stacks_btn = Button:new{
        text = _("Stacks"),
        callback = function()
            hub.active_tab = TAB_STACKS
            hub:refresh()
        end,
        bordersize = stacks_active and 2 or 0,
        radius = 6,
        text_font_bold = stacks_active,
        text_font_size = 16,
        padding = 6,
        width = math.floor(content_w * 0.44),
        show_parent = self,
    }
    local cards_btn = Button:new{
        text = _("All Cards"),
        callback = function()
            hub.active_tab = TAB_ALLCARDS
            hub.current_page = 1
            hub:refresh()
        end,
        bordersize = cards_active and 2 or 0,
        radius = 6,
        text_font_bold = cards_active,
        text_font_size = 16,
        padding = 6,
        width = math.floor(content_w * 0.44),
        show_parent = self,
    }

    local tab_bar = CenterContainer:new{
        dimen = Geom:new{ w = sw, h = tab_h },
        HorizontalGroup:new{
            align = "center",
            stacks_btn,
            HorizontalSpan:new{ width = 8 },
            cards_btn,
        },
    }
    table.insert(items, tab_bar)
    table.insert(items, VerticalSpan:new{ width = 4 })
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 2 },
        LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
    })
    table.insert(items, VerticalSpan:new{ width = 6 })

    -- ── TAB CONTENT ──
    if self.active_tab == TAB_STACKS then
        self:buildStacksTab(items, sw, sh, content_w, pad)
    else
        self:buildAllCardsTab(items, sw, sh, content_w, pad)
    end

    self:assembleUI(items, sw, sh)
end

-- ============================================
-- STACKS TAB
-- ============================================

function FlashcardsHub:buildStacksTab(items, sw, sh, content_w, pad)
    local hub = self
    local decks = CardDB.getAllDecks()

    if #decks == 0 then
        table.insert(items, VerticalSpan:new{ width = 30 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = sw, h = 30 },
            TextWidget:new{
                face = Font:getFace("cfont", 18),
                text = _("No decks yet"),
                fgcolor = DARK_GRAY,
            },
        })
    else
        local progress_bar_w = math.floor(content_w * 0.45)

        for __, deck in ipairs(decks) do
            local deck_id = deck.id
            local is_selected = self.selected_decks[deck_id] == true

            -- ── DECK TILE ──
            -- Line 1: [☐/☑] Deck Name              due count
            -- Line 2: 12 new · 5 learning · 8 due   ▓▓▓░░░
            -- Line 3: total cards · mastered

            -- Checkbox prefix (only in select mode)
            local checkbox = ""
            if self.select_mode then
                checkbox = is_selected and "☑ " or "☐ "
            end

            -- Deck name
            local name_str = checkbox .. (deck.name or "Unnamed")
            if #name_str > 28 then name_str = name_str:sub(1, 25) .. "..." end

            local name_w = TextWidget:new{
                face = Font:getFace("cfont", 18),
                text = name_str,
                fgcolor = BLACK,
                bold = true,
                max_width = math.floor(content_w * 0.65),
            }

            -- Due badge
            local due_str = deck.due_count > 0
                and tostring(deck.due_count) .. " due"
                or "—"
            local due_w = TextWidget:new{
                face = Font:getFace("cfont", 16),
                text = due_str,
                fgcolor = deck.due_count > 0 and BLACK or GRAY,
            }

            local due_actual_w = due_w:getSize().w
            local name_gap = 8
            local name_max_w = math.max(0, content_w - due_actual_w - name_gap)
            name_w.max_width = name_max_w
            local name_spacer = math.max(0, content_w - name_w:getSize().w - due_actual_w - name_gap)
            local top_row = HorizontalGroup:new{
                align = "center",
                name_w,
                HorizontalSpan:new{ width = name_spacer + name_gap },
                due_w,
            }

            -- Counts line
            local counts_str = string.format(
                "%d new · %d learning · %d review",
                deck.new_count, deck.learning_count, deck.total - deck.new_count - deck.learning_count - deck.mastered_count
            )
            local counts_w = TextWidget:new{
                face = Font:getFace("smallinfofont", 14),
                text = counts_str,
                fgcolor = DARK_GRAY,
                max_width = math.floor(content_w * 0.55),
            }

            -- Progress bar
            local prog_bar = buildProgressBar(deck, progress_bar_w)

            local prog_actual_w = prog_bar:getSize().w
            local counts_gap = 8
            local counts_spacer = math.max(0, content_w - counts_w:getSize().w - prog_actual_w - counts_gap)
            local mid_row = HorizontalGroup:new{
                align = "center",
                counts_w,
                HorizontalSpan:new{ width = counts_spacer + counts_gap },
                prog_bar,
            }

            -- Total/mastered line
            local total_str = string.format("%d total · %d mastered", deck.total, deck.mastered_count)
            local total_w = TextWidget:new{
                face = Font:getFace("smallinfofont", 12),
                text = total_str,
                fgcolor = GRAY,
                max_width = content_w,
            }

            -- Assemble tile content
            local tile_content = VerticalGroup:new{
                align = "left",
                top_row,
                VerticalSpan:new{ width = 3 },
                mid_row,
                VerticalSpan:new{ width = 2 },
                total_w,
            }

            -- Wrap in a rounded box
            local tile_box = FrameContainer:new{
                padding = 10,
                margin = 0,
                bordersize = is_selected and 2 or 1,
                radius = 10,
                color = is_selected and BLACK or GRAY,
                background = WHITE,
                tile_content,
            }

            -- Make it tappable
            local TappableTile = InputContainer:extend{}
            function TappableTile:init()
                self.dimen = Geom:new{ w = sw, h = tile_box:getSize().h + 8 }
                self.ges_events = {
                    TapTile = { GestureRange:new{ ges = "tap", range = self.dimen } },
                    HoldTile = { GestureRange:new{ ges = "hold", range = self.dimen } },
                }
                self[1] = CenterContainer:new{
                    dimen = Geom:new{ w = sw, h = tile_box:getSize().h + 8 },
                    tile_box,
                }
            end
            TappableTile.onTapTile = function()
                if hub.select_mode then
                    -- Toggle selection
                    if hub.selected_decks[deck_id] then
                        hub.selected_decks[deck_id] = nil
                    else
                        hub.selected_decks[deck_id] = true
                    end
                    hub:refresh()
                else
                    -- Open deck: switch to All Cards tab filtered to this deck
                    hub.active_tab = TAB_ALLCARDS
                    hub.deck_filter = deck_id
                    hub.deck_filter_name = deck.name
                    hub.current_page = 1
                    hub:refresh()
                end
                return true
            end
            TappableTile.onHoldTile = function()
                if not hub.select_mode then
                    -- Enter select mode with this deck selected
                    hub.select_mode = true
                    hub.selected_decks = { [deck_id] = true }
                    hub:refresh()
                else
                    -- Show deck actions
                    hub:showDeckActions(deck_id, deck.name)
                end
                return true
            end

            table.insert(items, TappableTile:new{})
        end
    end

    -- ── BOTTOM ACTIONS ──
    table.insert(items, VerticalSpan:new{ width = 10 })

    -- "Review Selected" button (only when select_mode and decks are selected)
    local selected_count = 0
    for _ in pairs(self.selected_decks) do selected_count = selected_count + 1 end

    if self.select_mode and selected_count > 0 then
        local review_sel_btn = Button:new{
            text = string.format(_("Review Selected (%d decks)"), selected_count),
            callback = function() hub:launchReviewSelectedDecks() end,
            bordersize = 2,
            radius = 8,
            text_font_bold = true,
            text_font_size = 16,
            padding_v = 10,
            width = math.floor(content_w * 0.92),
            show_parent = self,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = sw, h = review_sel_btn:getSize().h + 4 },
            review_sel_btn,
        })
        table.insert(items, VerticalSpan:new{ width = 6 })

        -- Cancel selection button
        local cancel_btn = Button:new{
            text = _("Cancel Selection"),
            callback = function()
                hub.select_mode = false
                hub.selected_decks = {}
                hub:refresh()
            end,
            bordersize = 0,
            text_font_size = 14,
            padding = 4,
            show_parent = self,
        }
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = sw, h = cancel_btn:getSize().h + 4 },
            cancel_btn,
        })
        table.insert(items, VerticalSpan:new{ width = 6 })
    end

    -- + New Deck button
    local new_deck_btn = Button:new{
        text = _("+ New Deck"),
        callback = function() hub:showCreateDeckDialog() end,
        bordersize = 1,
        radius = 8,
        text_font_size = 14,
        padding = 6,
        show_parent = self,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = new_deck_btn:getSize().h + 4 },
        new_deck_btn,
    })

    -- ── Anki Export / Import buttons ──
    table.insert(items, VerticalSpan:new{ width = 6 })
    local anki_btn_w = math.floor(content_w * 0.42)
    local export_btn = Button:new{
        text = _("Export to Anki"),
        callback = function() hub:showExportMenu() end,
        bordersize = 1,
        radius = 8,
        text_font_size = 14,
        padding = 6,
        width = anki_btn_w,
        show_parent = self,
    }
    local import_btn = Button:new{
        text = _("Import .apkg"),
        callback = function() hub:showImportMenu() end,
        bordersize = 1,
        radius = 8,
        text_font_size = 14,
        padding = 6,
        width = anki_btn_w,
        show_parent = self,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = export_btn:getSize().h + 4 },
        HorizontalGroup:new{
            align = "center",
            export_btn,
            HorizontalSpan:new{ width = 8 },
            import_btn,
        },
    })

    -- Select mode toggle hint
    if not self.select_mode then
        table.insert(items, VerticalSpan:new{ width = 8 })
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = sw, h = 20 },
            TextWidget:new{
                face = Font:getFace("smallinfofont", 12),
                text = _("long-press a deck to select multiple for review"),
                fgcolor = GRAY,
            },
        })
    end

    -- Footer
    table.insert(items, VerticalSpan:new{ width = 10 })
    table.insert(items, CozyUI.buildFooter(sw, "₊ ⊹ ♡ ⋆ ☆ ⋆ ♡ ⋆ ☆ ⋆ ♡ ⊹ ₊"))
end

-- ============================================
-- ALL CARDS TAB
-- ============================================

function FlashcardsHub:buildAllCardsTab(items, sw, sh, content_w, pad)
    local hub = self

    -- Filter bar: Book filter + Deck filter

    -- Deck filter label
    local deck_label = self.deck_filter_name or _("All Decks")
    if #deck_label > 16 then deck_label = deck_label:sub(1, 13) .. "..." end
    local deck_btn = Button:new{
        text = _("Deck: ") .. deck_label,
        callback = function() hub:showDeckFilterMenu() end,
        bordersize = 0,
        text_font_size = 14,
        padding = 4,
        show_parent = self,
    }

    -- Book filter label
    local book_label = self.book_filter_title or _("All Books")
    if #book_label > 16 then book_label = book_label:sub(1, 13) .. "..." end
    local book_btn = Button:new{
        text = _("Book: ") .. book_label,
        callback = function() hub:showBookFilterMenu() end,
        bordersize = 0,
        text_font_size = 14,
        padding = 4,
        show_parent = self,
    }

    -- Suspended filter button
    local susp_count = CardDB.getCounts().suspended
    local susp_label
    if self.suspended_filter == "only" then
        susp_label = string.format(_("✦ Susp (%d)"), susp_count)
    else
        susp_label = string.format(_("Susp (%d)"), susp_count)
    end
    local susp_btn = Button:new{
        text = susp_label,
        callback = function()
            if hub.suspended_filter == "only" then
                hub.suspended_filter = nil
            else
                hub.suspended_filter = "only"
                -- Clear other filters when viewing suspended
                hub.deck_filter = nil
                hub.deck_filter_name = nil
                hub.book_filter = nil
                hub.book_filter_title = nil
            end
            hub.current_page = 1
            hub:refresh()
        end,
        bordersize = self.suspended_filter == "only" and 2 or 0,
        text_font_size = 14,
        padding = 4,
        show_parent = self,
    }

    -- + New Card button
    local new_btn = Button:new{
        text = _("+ New"),
        callback = function() hub:showStandaloneCreateDialog() end,
        bordersize = 0,
        text_font_size = 14,
        padding = 4,
        show_parent = self,
    }

    local left_filters = HorizontalGroup:new{
        align = "center",
        deck_btn,
        HorizontalSpan:new{ width = 8 },
        book_btn,
        HorizontalSpan:new{ width = 8 },
        susp_btn,
    }
    local filters_w = left_filters:getSize().w
    local new_btn_w = new_btn:getSize().w
    local filter_gap = 8
    local filter_spacer = math.max(0, content_w - filters_w - new_btn_w - filter_gap)
    local filter_bar = HorizontalGroup:new{
        align = "center",
        left_filters,
        HorizontalSpan:new{ width = filter_spacer + filter_gap },
        new_btn,
    }
    table.insert(items, FrameContainer:new{
        dimen = Geom:new{ w = sw, h = 36 },
        bordersize = 0, padding = 0, padding_left = pad, padding_right = pad,
        background = WHITE,
        filter_bar,
    })
    table.insert(items, VerticalSpan:new{ width = 2 })
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 2 },
        LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
    })
    table.insert(items, VerticalSpan:new{ width = 4 })

    -- Fetch cards
    -- Dynamic items-per-page calculation (matches learningspace.lua pattern)
    local row_h = Screen:scaleBySize(68)
    local reserved_h = Screen:scaleBySize(260)  -- header + review btn + tabs + filter bar + pagination
    local available_h = sh - reserved_h
    local items_per_page = math.max(3, math.floor(available_h / (row_h + 1)))

    local cards, total_count = CardDB.getCards(
        self.current_page, items_per_page, self.book_filter, self.deck_filter, self.suspended_filter
    )

    if total_count == 0 then
        table.insert(items, VerticalSpan:new{ width = math.floor(sh * 0.06) })
        local empty_msg = _("No flashcards")
        if self.suspended_filter == "only" then empty_msg = _("No suspended cards")
        elseif self.deck_filter then empty_msg = _("No cards in this deck")
        elseif self.book_filter then empty_msg = _("No cards for this book") end
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{ w = sw, h = 30 },
            TextWidget:new{
                face = Font:getFace("cfont", 18),
                text = empty_msg,
                fgcolor = DARK_GRAY,
            },
        })
    else
        local total_pages = math.ceil(total_count / items_per_page)
        local text_area_w = content_w - pad

        for idx, card in ipairs(cards) do
            local status = statusLabel(card)
            local front_preview = (card.front or "[empty]"):gsub("\n", " ")
            if #front_preview > 60 then front_preview = front_preview:sub(1, 57) .. "..." end

            local title_tw = TextWidget:new{
                face = Font:getFace("cfont", 18),
                text = status .. " " .. front_preview,
                fgcolor = card.suspended == 1 and GRAY or BLACK,
                max_width = text_area_w,
            }

            local detail_parts = {}
            if card.book_title and card.book_title ~= "" then
                local bt = card.book_title
                if #bt > 25 then bt = bt:sub(1, 22) .. "..." end
                table.insert(detail_parts, bt)
            end
            if card.review_count > 0 then
                table.insert(detail_parts, card.review_count .. " reviews")
            end
            if card.interval_days > 0 then
                table.insert(detail_parts, card.interval_days .. "d")
            end

            local detail_tw = TextWidget:new{
                face = Font:getFace("smallinfofont", 14),
                text = table.concat(detail_parts, "  ·  "),
                fgcolor = DARK_GRAY,
                max_width = text_area_w,
            }

            local text_col = VerticalGroup:new{
                align = "left",
                title_tw,
                VerticalSpan:new{ width = 4 },
                detail_tw,
            }

            local card_id = card.id
            local TappableRow = InputContainer:extend{}
            function TappableRow:init()
                self.dimen = Geom:new{ w = sw, h = row_h }
                self.ges_events = {
                    TapRow = { GestureRange:new{ ges = "tap", range = self.dimen } },
                    HoldRow = { GestureRange:new{ ges = "hold", range = self.dimen } },
                }
                self[1] = FrameContainer:new{
                    dimen = Geom:new{ w = sw, h = row_h },
                    bordersize = 0, padding = 0, padding_left = pad,
                    background = WHITE,
                    CenterContainer:new{
                        dimen = Geom:new{ w = content_w, h = row_h },
                        LeftContainer:new{
                            dimen = Geom:new{ w = content_w, h = row_h },
                            text_col,
                        },
                    },
                }
            end
            TappableRow.onTapRow = function()
                hub:showCardDetail(card_id)
                return true
            end
            TappableRow.onHoldRow = function()
                hub:showCardActions(card_id)
                return true
            end

            table.insert(items, TappableRow:new{})

            if idx < #cards then
                table.insert(items, FrameContainer:new{
                    dimen = Geom:new{ w = sw, h = 1 },
                    bordersize = 0, padding = 0, padding_left = pad,
                    background = WHITE,
                    LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
                })
            end
        end

        -- Pagination
        if total_pages > 1 then
            table.insert(items, VerticalSpan:new{ width = 8 })

            local nav_btn_w = math.floor(content_w * 0.28)
            local nav_h = Screen:scaleBySize(40)

            local prev_btn = Button:new{
                text = _("< Prev"),
                enabled = self.current_page > 1,
                callback = function() hub.current_page = hub.current_page - 1; hub:refresh() end,
                bordersize = 1,
                radius = 6,
                text_font_size = 16,
                padding_v = 6,
                padding_h = 8,
                width = nav_btn_w,
                show_parent = self,
            }
            local page_label = TextWidget:new{
                face = Font:getFace("cfont", 16),
                text = string.format(_("Page %d of %d"), self.current_page, total_pages),
                fgcolor = DARK_GRAY,
            }
            local next_btn = Button:new{
                text = _("Next >"),
                enabled = self.current_page < total_pages,
                callback = function() hub.current_page = hub.current_page + 1; hub:refresh() end,
                bordersize = 1,
                radius = 6,
                text_font_size = 16,
                padding_v = 6,
                padding_h = 8,
                width = nav_btn_w,
                show_parent = self,
            }

            local prev_w = prev_btn:getSize().w
            local next_w = next_btn:getSize().w
            local nav_gap = 8
            local nav_label_w = math.max(0, content_w - prev_w - next_w - nav_gap * 2)
            page_label.max_width = nav_label_w
            local nav_group = HorizontalGroup:new{
                align = "center",
                CenterContainer:new{ dimen = Geom:new{ w = prev_w, h = nav_h }, prev_btn },
                HorizontalSpan:new{ width = nav_gap },
                CenterContainer:new{ dimen = Geom:new{ w = nav_label_w, h = nav_h }, page_label },
                HorizontalSpan:new{ width = nav_gap },
                CenterContainer:new{ dimen = Geom:new{ w = next_w, h = nav_h }, next_btn },
            }
            table.insert(items, FrameContainer:new{
                dimen = Geom:new{ w = sw, h = nav_h },
                bordersize = 0, padding = 0, padding_left = pad, padding_right = pad,
                background = WHITE,
                nav_group,
            })
        end
    end
end

-- ============================================
-- NO DATABASE UI
-- ============================================

function FlashcardsHub:buildNoDbUI(items, sw, sh, content_w, pad)
    local hub = self

    table.insert(items, CozyUI.buildScreenHeader({
        sw = sw,
        title = "Flashcards",
        back_callback = function() hub:onClose() end,
        exit_callback = function() hub:onClose() end,
        show_parent = self,
    }))
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 2 },
        LineWidget:new{ dimen = Geom:new{ w = content_w, h = 1 }, background = LIGHT_GRAY },
    })

    table.insert(items, VerticalSpan:new{ width = math.floor(sh * 0.15) })
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 30 },
        TextWidget:new{
            face = Font:getFace("cfont", 18),
            text = _("No flashcard database found"),
            fgcolor = DARK_GRAY,
        },
    })
    table.insert(items, VerticalSpan:new{ width = 12 })
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = 24 },
        TextWidget:new{
            face = Font:getFace("cfont", 14),
            text = _("Create your first flashcard to get started"),
            fgcolor = GRAY,
            max_width = content_w,
        },
    })
    table.insert(items, VerticalSpan:new{ width = 20 })

    local create_btn = Button:new{
        text = _("+ Create First Card"),
        callback = function()
            -- Bootstrap the database, then open the card creation dialog
            CardDB.createDB()
            hub:refresh()
            UIManager:nextTick(function()
                if Flashcards._hub_instance then
                    Flashcards._hub_instance:showStandaloneCreateDialog()
                end
            end)
        end,
        bordersize = 2,
        radius = 8,
        text_font_bold = true,
        text_font_size = 16,
        padding_v = 10,
        width = math.floor(content_w * 0.7),
        show_parent = self,
    }
    table.insert(items, CenterContainer:new{
        dimen = Geom:new{ w = sw, h = create_btn:getSize().h + 4 },
        create_btn,
    })
end

-- ============================================
-- ASSEMBLY
-- ============================================

function FlashcardsHub:assembleUI(items, sw, sh)
    local content = VerticalGroup:new{ align = "center" }
    for __, item in ipairs(items) do
        table.insert(content, item)
    end

    local scrollable = ScrollableContainer:new{
        dimen = Geom:new{ w = sw, h = sh },
        show_parent = self,
        content,
    }

    self[1] = FrameContainer:new{
        dimen = Geom:new{ w = sw, h = sh },
        bordersize = 0, padding = 0,
        background = WHITE,
        scrollable,
    }
end

-- ============================================
-- REFRESH
-- ============================================

function FlashcardsHub:refresh()
    local state = {
        ui = self.ui,
        on_close_callback = self.on_close_callback,
        active_tab = self.active_tab,
        selected_decks = self.selected_decks,
        select_mode = self.select_mode,
        current_page = self.current_page,
        book_filter = self.book_filter,
        book_filter_title = self.book_filter_title,
        deck_filter = self.deck_filter,
        deck_filter_name = self.deck_filter_name,
        suspended_filter = self.suspended_filter,
    }

    UIManager:close(self)
    UIManager:nextTick(function()
        local new_hub = FlashcardsHub:new(state)
        UIManager:show(new_hub)
    end)
end

-- ============================================
-- REVIEW ACTIONS (self-contained, no external plugin needed)
-- ============================================

--- Common callback after a review session finishes.
function FlashcardsHub:onReviewDone()
    self.select_mode = false
    self.selected_decks = {}
    self:refresh()
end

--- Launch a review session with all due cards.
function FlashcardsHub:launchReview()
    local due_cards = CardDB.getDueCards(100)
    if #due_cards == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No cards due for review!\n\nGreat job keeping up with your studies."),
            timeout = 4,
        })
        return
    end

    local hub = self
    UIManager:close(self)
    UIManager:nextTick(function()
        UIManager:show(CozyStudyScreen:new{
            cards = due_cards,
            on_session_complete = function()
                Flashcards.show(hub.ui, hub.on_close_callback)
            end,
        })
    end)
end

--- Launch a review session for selected decks.
function FlashcardsHub:launchReviewSelectedDecks()
    local deck_ids = {}
    for id in pairs(self.selected_decks) do
        table.insert(deck_ids, id)
    end

    if #deck_ids == 0 then
        UIManager:show(InfoMessage:new{ text = _("No decks selected."), timeout = 2 })
        return
    end

    local due_cards = CardDB.getDueCardsByDecks(deck_ids, 100)
    if #due_cards == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No cards due in the selected decks!\n\nGreat job keeping up with your studies."),
            timeout = 4,
        })
        return
    end

    local hub = self
    UIManager:close(self)
    UIManager:nextTick(function()
        UIManager:show(CozyStudyScreen:new{
            cards = due_cards,
            on_session_complete = function()
                Flashcards.show(hub.ui, hub.on_close_callback)
            end,
        })
    end)
end

--- Launch review for a single deck (called from deck actions dialog).
function FlashcardsHub:launchReviewForDeck(deck_id)
    local due_cards = CardDB.getDueCardsByDecks({deck_id}, 100)
    if #due_cards == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No cards due in this deck!\n\nGreat job keeping up with your studies."),
            timeout = 4,
        })
        return
    end

    local hub = self
    UIManager:close(self)
    UIManager:nextTick(function()
        UIManager:show(CozyStudyScreen:new{
            cards = due_cards,
            on_session_complete = function()
                Flashcards.show(hub.ui, hub.on_close_callback)
            end,
        })
    end)
end

-- ============================================
-- DECK MANAGEMENT
-- ============================================

function FlashcardsHub:showCreateDeckDialog()
    local hub = self
    local dialog
    dialog = InputDialog:new{
        title = _("✦ New Deck ✦"),
        input = "",
        input_hint = _("Deck name"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText()
                        UIManager:close(dialog)
                        name = CozyUI.sanitizeInput(name, 100)
                        if name ~= "" then
                            local id = CardDB.createDeck(name, nil)
                            if id then
                                UIManager:show(InfoMessage:new{
                                    text = _("Deck created: ") .. name,
                                    timeout = 2,
                                })
                            end
                            hub:refresh()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function FlashcardsHub:showDeckActions(deck_id, deck_name)
    local hub = self
    local is_general = deck_id == 1

    local buttons = {
        {
            {
                text = _("Review This Deck"),
                callback = function()
                    UIManager:close(hub._deck_dialog)
                    hub:launchReviewForDeck(deck_id)
                end,
            },
        },
        {
            {
                text = _("Rename"),
                enabled = not is_general,
                callback = function()
                    UIManager:close(hub._deck_dialog)
                    hub:showRenameDeckDialog(deck_id, deck_name)
                end,
            },
        },
        {
            {
                text = _("Delete"),
                enabled = not is_general,
                callback = function()
                    UIManager:close(hub._deck_dialog)
                    UIManager:show(ConfirmBox:new{
                        text = string.format(
                            _("Delete deck '%s'?\n\nAll cards will be moved to General."),
                            deck_name
                        ),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            local ok = CardDB.deleteDeck(deck_id)
                            if not ok then
                                UIManager:show(InfoMessage:new{
                                    text = _("Failed to delete deck."),
                                    timeout = 3,
                                })
                                return
                            end
                            if hub.selected_decks[deck_id] then
                                hub.selected_decks[deck_id] = nil
                            end
                            hub:refresh()
                        end,
                    })
                end,
            },
        },
        {
            {
                text = _("Cancel"),
                callback = function() UIManager:close(hub._deck_dialog) end,
            },
        },
    }

    hub._deck_dialog = ButtonDialog:new{
        title = "✦ " .. deck_name .. " ✦",
        buttons = buttons,
    }
    UIManager:show(hub._deck_dialog)
end

function FlashcardsHub:showRenameDeckDialog(deck_id, old_name)
    local hub = self
    local dialog
    dialog = InputDialog:new{
        title = _("✦ Rename Deck ✦"),
        input = old_name,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Rename"),
                    is_enter_default = true,
                    callback = function()
                        local raw_name = dialog:getInputText()
                        UIManager:close(dialog)
                        local new_name = CozyUI.sanitizeInput(raw_name, 100)
                        if new_name ~= "" then
                            local ok = CardDB.renameDeck(deck_id, new_name)
                            if not ok then
                                UIManager:show(InfoMessage:new{
                                    text = _("Failed to rename deck."),
                                    timeout = 3,
                                })
                                return
                            end
                            if hub.deck_filter == deck_id then
                                hub.deck_filter_name = new_name
                            end
                            hub:refresh()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================================
-- FILTER MENUS
-- ============================================

function FlashcardsHub:showDeckFilterMenu()
    local hub = self
    local decks = CardDB.getAllDecks()
    local button_rows = {}

    table.insert(button_rows, {
        {
            text = hub.deck_filter == nil and "[x] All Decks" or "[ ] All Decks",
            callback = function()
                UIManager:close(hub._deck_filter_dialog)
                hub.deck_filter = nil
                hub.deck_filter_name = nil
                hub.suspended_filter = nil
                hub.current_page = 1
                hub:refresh()
            end,
        },
    })

    for __, deck in ipairs(decks) do
        local label = deck.name .. " (" .. deck.total .. ")"
        if #label > 35 then label = label:sub(1, 32) .. "..." end
        local is_active = hub.deck_filter == deck.id
        local prefix = is_active and "[x] " or "[ ] "
        local did = deck.id
        local dname = deck.name

        table.insert(button_rows, {
            {
                text = prefix .. label,
                callback = function()
                    UIManager:close(hub._deck_filter_dialog)
                    hub.deck_filter = did
                    hub.deck_filter_name = dname
                    hub.suspended_filter = nil
                    hub.current_page = 1
                    hub:refresh()
                end,
            },
        })
    end

    table.insert(button_rows, {
        { text = _("Cancel"), callback = function() UIManager:close(hub._deck_filter_dialog) end },
    })

    hub._deck_filter_dialog = ButtonDialog:new{
        title = _("✦ Filter by Deck ✦"),
        buttons = button_rows,
    }
    UIManager:show(hub._deck_filter_dialog)
end

function FlashcardsHub:showBookFilterMenu()
    local hub = self
    local button_rows = {}

    table.insert(button_rows, {
        {
            text = hub.book_filter == nil and "[x] All Books" or "[ ] All Books",
            callback = function()
                UIManager:close(hub._book_filter_dialog)
                hub.book_filter = nil
                hub.book_filter_title = nil
                hub.suspended_filter = nil
                hub.current_page = 1
                hub:refresh()
            end,
        },
    })

    local books = CardDB.getBooksWithCards()
    for __, book in ipairs(books) do
        local label = book.book_title
        if #label > 35 then label = label:sub(1, 32) .. "..." end
        label = label .. " (" .. book.card_count .. ")"
        local is_active = hub.book_filter == book.book_path
        local prefix = is_active and "[x] " or "[ ] "

        table.insert(button_rows, {
            {
                text = prefix .. label,
                callback = function()
                    UIManager:close(hub._book_filter_dialog)
                    hub.book_filter = book.book_path
                    hub.book_filter_title = book.book_title
                    hub.suspended_filter = nil
                    hub.current_page = 1
                    hub:refresh()
                end,
            },
        })
    end

    table.insert(button_rows, {
        { text = _("Cancel"), callback = function() UIManager:close(hub._book_filter_dialog) end },
    })

    hub._book_filter_dialog = ButtonDialog:new{
        title = _("✦ Filter by Book ✦"),
        buttons = button_rows,
    }
    UIManager:show(hub._book_filter_dialog)
end

-- ============================================
-- CARD CREATION
-- ============================================

function FlashcardsHub:showStandaloneCreateDialog()
    local hub = self
    local dialog
    dialog = InputDialog:new{
        title = _("✦ New Flashcard — Front ✦"),
        input = "",
        input_hint = _("Question / prompt"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Next >"),
                    is_enter_default = true,
                    callback = function()
                        local front = dialog:getInputText()
                        UIManager:close(dialog)
                        if front and front ~= "" then
                            hub:showStandaloneBackDialog(front)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function FlashcardsHub:showStandaloneBackDialog(front_text)
    local hub = self
    local dialog
    dialog = InputDialog:new{
        title = _("✦ New Flashcard — Back ✦"),
        input = "",
        input_hint = _("Answer"),
        buttons = {
            {
                {
                    text = _("< Back"),
                    callback = function()
                        UIManager:close(dialog)
                        hub:showStandaloneCreateDialog()
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local back = dialog:getInputText()
                        UIManager:close(dialog)
                        if back and back ~= "" then
                            hub:saveNewCard(front_text, back)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function FlashcardsHub:saveNewCard(front, back)
    local hub = self
    local conn = CardDB.openConn()
    if not conn then
        UIManager:show(InfoMessage:new{ text = _("Cannot save — database not available."), timeout = 3 })
        return
    end

    local deck_id = hub.deck_filter or 1  -- save to current deck filter, or General

    pcall(function()
        local stmt = conn:prepare(
            "INSERT INTO flashcards (front, back, state, card_type, deck_id) VALUES (?, ?, 'new', 'text', ?)"
        )
        if stmt then stmt:bind(front, back, deck_id); stmt:step(); stmt:close() end
    end)
    pcall(function() conn:close() end)

    UIManager:show(InfoMessage:new{ text = _("Flashcard created."), timeout = 2 })
    hub:refresh()
end

-- ============================================
-- CARD DETAIL & ACTIONS
-- ============================================

function FlashcardsHub:showCardDetail(card_id)
    local card = CardDB.getCard(card_id)
    if not card then
        UIManager:show(InfoMessage:new{ text = _("Card not found."), timeout = 2 })
        return
    end

    local hub = self
    UIManager:close(self)
    UIManager:nextTick(function()
        UIManager:show(CozyCardDetailScreen:new{
            card = card,
            on_close = function()
                Flashcards.show(hub.ui, hub.on_close_callback)
            end,
            on_edit = function(cid)
                -- Re-open hub then trigger edit
                local new_hub_cb
                new_hub_cb = function()
                    if Flashcards._hub_instance then
                        Flashcards._hub_instance:showEditCard(cid)
                    end
                end
                Flashcards.show(hub.ui, hub.on_close_callback)
                UIManager:nextTick(new_hub_cb)
            end,
            on_delete = function(cid)
                CardDB.deleteCard(cid)
                Flashcards.show(hub.ui, hub.on_close_callback)
            end,
            on_suspend = function(cid)
                CardDB.toggleSuspend(cid)
                -- Re-open detail with refreshed card
                local refreshed = CardDB.getCard(cid)
                if refreshed then
                    UIManager:show(CozyCardDetailScreen:new{
                        card = refreshed,
                        on_close = function()
                            Flashcards.show(hub.ui, hub.on_close_callback)
                        end,
                    })
                else
                    Flashcards.show(hub.ui, hub.on_close_callback)
                end
            end,
            on_move = function(cid)
                Flashcards.show(hub.ui, hub.on_close_callback)
                UIManager:nextTick(function()
                    if Flashcards._hub_instance then
                        Flashcards._hub_instance:showMoveToDeckMenu(cid)
                    end
                end)
            end,
        })
    end)
end

--- Edit a card's front and back text.
function FlashcardsHub:showEditCard(card_id)
    local hub = self
    local card = CardDB.getCard(card_id)
    if not card then
        UIManager:show(InfoMessage:new{ text = _("Card not found."), timeout = 2 })
        return
    end

    -- Build context description from source highlight
    local desc = nil
    if card.source_text and card.source_text ~= "" then
        local st = card.source_text
        if #st > 150 then st = st:sub(1, 147) .. "..." end
        desc = _("Highlight: ") .. st
    end

    -- Step 1: Edit front
    local front_dialog
    front_dialog = InputDialog:new{
        title = _("✦ Edit Front"),
        description = desc,
        input = card.front or "",
        input_hint = _("Question / prompt"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(front_dialog) end,
                },
                {
                    text = _("Next >"),
                    is_enter_default = true,
                    callback = function()
                        local new_front = front_dialog:getInputText()
                        UIManager:close(front_dialog)
                        if not new_front or new_front == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("Front text cannot be empty."),
                                timeout = 2,
                            })
                            return
                        end
                        -- Step 2: Edit back
                        local back_desc = desc
                        if back_desc then
                            back_desc = back_desc .. "\n\n" .. _("Front: ") .. new_front
                        else
                            back_desc = _("Front: ") .. new_front
                        end

                        local back_dialog
                        back_dialog = InputDialog:new{
                            title = _("✦ Edit Back"),
                            description = back_desc,
                            input = card.back or "",
                            input_hint = _("Answer"),
                            buttons = {
                                {
                                    {
                                        text = _("< Back"),
                                        callback = function()
                                            UIManager:close(back_dialog)
                                            -- Re-open front editor with current text
                                            card.front = new_front
                                            hub:showEditCard(card_id)
                                        end,
                                    },
                                    {
                                        text = _("Save"),
                                        is_enter_default = true,
                                        callback = function()
                                            local new_back = back_dialog:getInputText()
                                            UIManager:close(back_dialog)
                                            if not new_back or new_back == "" then
                                                UIManager:show(InfoMessage:new{
                                                    text = _("Back text cannot be empty."),
                                                    timeout = 2,
                                                })
                                                return
                                            end
                                            local ok = CardDB.updateCardText(card_id, new_front, new_back)
                                            if ok then
                                                UIManager:show(InfoMessage:new{
                                                    text = _("Card updated."),
                                                    timeout = 2,
                                                })
                                                hub:refresh()
                                            else
                                                UIManager:show(InfoMessage:new{
                                                    text = _("Failed to update card."),
                                                    timeout = 2,
                                                })
                                            end
                                        end,
                                    },
                                },
                            },
                        }
                        UIManager:show(back_dialog)
                        back_dialog:onShowKeyboard()
                    end,
                },
            },
        },
    }
    UIManager:show(front_dialog)
    front_dialog:onShowKeyboard()
end

function FlashcardsHub:showCardActions(card_id)
    local hub = self
    local card = CardDB.getCard(card_id)
    if not card then return end

    local front_preview = (card.front or ""):gsub("\n", " ")
    if #front_preview > 30 then front_preview = front_preview:sub(1, 27) .. "..." end

    local suspend_text = card.suspended == 1 and _("Unsuspend") or _("Suspend")

    local dialog
    dialog = ButtonDialog:new{
        title = front_preview,
        buttons = {
            {
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(dialog)
                        hub:showEditCard(card_id)
                    end,
                },
                {
                    text = _("View Details"),
                    callback = function()
                        UIManager:close(dialog)
                        -- Use nextTick to allow the dialog to close first
                        UIManager:nextTick(function()
                            hub:showCardDetail(card_id)
                        end)
                    end,
                },
            },
            {
                {
                    text = _("Move to Deck"),
                    callback = function()
                        UIManager:close(dialog)
                        hub:showMoveToDeckMenu(card_id)
                    end,
                },
            },
            {
                {
                    text = suspend_text,
                    callback = function()
                        UIManager:close(dialog)
                        CardDB.toggleSuspend(card_id)
                        hub:refresh()
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(dialog)
                        UIManager:show(ConfirmBox:new{
                            text = _("Delete this flashcard?\n\nThis cannot be undone."),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                local ok = CardDB.deleteCard(card_id)
                                if not ok then
                                    UIManager:show(InfoMessage:new{
                                        text = _("Failed to delete card."),
                                        timeout = 3,
                                    })
                                end
                                hub:refresh()
                            end,
                        })
                    end,
                },
            },
            {
                { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            },
        },
    }
    UIManager:show(dialog)
end

function FlashcardsHub:showMoveToDeckMenu(card_id)
    local hub = self
    local decks = CardDB.getAllDecks()
    local card = CardDB.getCard(card_id)
    local current_deck = card and card.deck_id or 1
    local button_rows = {}

    for __, deck in ipairs(decks) do
        local is_current = deck.id == current_deck
        local prefix = is_current and "● " or "○ "
        local did = deck.id

        table.insert(button_rows, {
            {
                text = prefix .. deck.name,
                callback = function()
                    UIManager:close(hub._move_dialog)
                    CardDB.moveCardToDeck(card_id, did)
                    UIManager:show(InfoMessage:new{
                        text = _("Moved to ") .. deck.name,
                        timeout = 2,
                    })
                    hub:refresh()
                end,
            },
        })
    end

    table.insert(button_rows, {
        { text = _("Cancel"), callback = function() UIManager:close(hub._move_dialog) end },
    })

    hub._move_dialog = ButtonDialog:new{
        title = _("✦ Move to Deck ✦"),
        buttons = button_rows,
    }
    UIManager:show(hub._move_dialog)
end

-- ============================================
-- ANKI EXPORT
-- ============================================

function FlashcardsHub:showExportMenu()
    local hub = self
    local counts = CardDB.getCounts()

    if counts.total == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No flashcards to export."),
            timeout = 3,
        })
        return
    end

    local buttons = {
        {
            {
                text = string.format("Export All (%d cards)", counts.total),
                callback = function()
                    UIManager:close(hub._export_dialog)
                    hub:doExportAll()
                end,
            },
        },
        {
            {
                text = _("Export by Deck"),
                callback = function()
                    UIManager:close(hub._export_dialog)
                    hub:showExportByDeckMenu()
                end,
            },
        },
        {
            {
                text = _("Export by Book"),
                callback = function()
                    UIManager:close(hub._export_dialog)
                    hub:showExportByBookMenu()
                end,
            },
        },
        {
            {
                text = _("Export Current Book"),
                callback = function()
                    UIManager:close(hub._export_dialog)
                    hub:exportCurrentBook()
                end,
            },
        },
        {
            { text = _("Cancel"), callback = function() UIManager:close(hub._export_dialog) end },
        },
    }

    hub._export_dialog = ButtonDialog:new{
        title = _("✦ Export to Anki ✦"),
        buttons = buttons,
    }
    UIManager:show(hub._export_dialog)
end

function FlashcardsHub:doExportAll()
    local AnkiExport = require("lib/anki_export")

    UIManager:show(InfoMessage:new{ text = _("Exporting all cards..."), timeout = 1 })

    UIManager:nextTick(function()
        local ok, path_or_err, count = AnkiExport.exportAll("Cozy Reader")
        if ok then
            UIManager:show(InfoMessage:new{
                text = string.format("Exported %d cards!\n\nSaved to:\n%s", count, path_or_err),
                timeout = 8,
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("Export failed: ") .. tostring(path_or_err),
                timeout = 5,
            })
        end
    end)
end

function FlashcardsHub:showExportByBookMenu()
    local hub = self
    local AnkiExport = require("lib/anki_export")
    local books = AnkiExport.getBooksWithCards()

    if #books == 0 then
        UIManager:show(InfoMessage:new{ text = _("No books with flashcards found."), timeout = 3 })
        return
    end

    local button_rows = {}
    for __, book in ipairs(books) do
        local label = (book.book_title or "Unknown")
        if #label > 35 then label = label:sub(1, 32) .. "..." end
        label = label .. string.format(" (%d)", book.card_count)
        local bp = book.book_path
        local bt = book.book_title or "Unknown"

        table.insert(button_rows, {
            {
                text = label,
                callback = function()
                    UIManager:close(hub._book_export_dialog)
                    UIManager:show(InfoMessage:new{ text = _("Exporting..."), timeout = 1 })
                    UIManager:nextTick(function()
                        local ok, path_or_err, count = AnkiExport.exportByBook(bp, bt)
                        if ok then
                            UIManager:show(InfoMessage:new{
                                text = string.format("Exported %d cards!\n\n%s", count, path_or_err),
                                timeout = 8,
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Export failed: ") .. tostring(path_or_err), timeout = 5,
                            })
                        end
                    end)
                end,
            },
        })
    end

    table.insert(button_rows, {
        { text = _("Cancel"), callback = function() UIManager:close(hub._book_export_dialog) end },
    })

    hub._book_export_dialog = ButtonDialog:new{
        title = _("✦ Export by Book ✦"),
        buttons = button_rows,
    }
    UIManager:show(hub._book_export_dialog)
end

function FlashcardsHub:showExportByDeckMenu()
    local hub = self
    local AnkiExport = require("lib/anki_export")
    local decks = CardDB.getAllDecks()

    if #decks == 0 then
        UIManager:show(InfoMessage:new{ text = _("No decks found."), timeout = 3 })
        return
    end

    local button_rows = {}
    for __, deck in ipairs(decks) do
        local label = deck.name .. string.format(" (%d)", deck.total)
        local did = deck.id
        local dname = deck.name

        table.insert(button_rows, {
            {
                text = label,
                callback = function()
                    UIManager:close(hub._deck_export_dialog)
                    UIManager:show(InfoMessage:new{ text = _("Exporting..."), timeout = 1 })
                    UIManager:nextTick(function()
                        local ok, path_or_err, count = AnkiExport.exportByDeck(did, dname)
                        if ok then
                            UIManager:show(InfoMessage:new{
                                text = string.format("Exported %d cards!\n\n%s", count, path_or_err),
                                timeout = 8,
                            })
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Export failed: ") .. tostring(path_or_err), timeout = 5,
                            })
                        end
                    end)
                end,
            },
        })
    end

    table.insert(button_rows, {
        { text = _("Cancel"), callback = function() UIManager:close(hub._deck_export_dialog) end },
    })

    hub._deck_export_dialog = ButtonDialog:new{
        title = _("✦ Export by Deck ✦"),
        buttons = button_rows,
    }
    UIManager:show(hub._deck_export_dialog)
end

function FlashcardsHub:exportCurrentBook()
    if not self.ui or not self.ui.document then
        UIManager:show(InfoMessage:new{
            text = _("No book is currently open."),
            timeout = 2,
        })
        return
    end

    local AnkiExport = require("lib/anki_export")
    local book_path = self.ui.document.file
    local props = self.ui.document:getProps()
    local book_title = props.title or book_path:match("([^/]+)%..+$") or "Unknown"

    UIManager:show(InfoMessage:new{ text = _("Exporting..."), timeout = 1 })
    UIManager:nextTick(function()
        local ok, path_or_err, count = AnkiExport.exportByBook(book_path, book_title)
        if ok then
            UIManager:show(InfoMessage:new{
                text = string.format("Exported %d cards!\n\n%s", count, path_or_err),
                timeout = 8,
            })
        else
            UIManager:show(InfoMessage:new{
                text = _("Export failed: ") .. tostring(path_or_err),
                timeout = 5,
            })
        end
    end)
end

-- ============================================
-- ANKI IMPORT
-- ============================================

function FlashcardsHub:showImportMenu()
    local hub = self
    local AnkiImport = require("lib/anki_import")
    local import_dir = AnkiImport.getImportDir()
    local files = AnkiImport.listApkgFiles()

    if #files == 0 then
        UIManager:show(InfoMessage:new{
            text = string.format(_("No .apkg files found.\n\nPlace Anki export files in:\n%s\n\nOr in:\n  /mnt/onboard/\n  /mnt/onboard/imports/\n  /mnt/onboard/Anki/"), import_dir),
            timeout = 8,
        })
        return
    end

    local button_rows = {}
    for __, f in ipairs(files) do
        local label = f.filename
        if #label > 35 then label = label:sub(1, 32) .. "..." end
        local size_str = ""
        if f.size_kb then
            if f.size_kb > 1024 then
                size_str = string.format(" (%.1f MB)", f.size_kb / 1024)
            else
                size_str = string.format(" (%d KB)", f.size_kb)
            end
        end
        label = label .. size_str
        local fpath = f.path

        table.insert(button_rows, {
            {
                text = label,
                callback = function()
                    UIManager:close(hub._import_dialog)
                    hub:confirmImport({ path = fpath, filename = f.filename })
                end,
            },
        })
    end

    table.insert(button_rows, {
        { text = _("Cancel"), callback = function() UIManager:close(hub._import_dialog) end },
    })

    hub._import_dialog = ButtonDialog:new{
        title = _("✦ Import .apkg ✦"),
        buttons = button_rows,
    }
    UIManager:show(hub._import_dialog)
end

function FlashcardsHub:confirmImport(file)
    local hub = self
    local AnkiImport = require("lib/anki_import")

    -- Try to get file info first
    local info = AnkiImport.getApkgInfo(file.path)
    local info_text = file.filename .. "\n\n"
    if info then
        info_text = info_text .. string.format("Cards: %d\nNotes: %d\n", info.card_count or 0, info.note_count or 0)
        if info.decks and #info.decks > 0 then
            info_text = info_text .. "\nDecks:\n"
            for i, deck in ipairs(info.decks) do
                if i <= 5 then
                    info_text = info_text .. "  · " .. deck .. "\n"
                elseif i == 6 then
                    info_text = info_text .. "  ... and " .. (#info.decks - 5) .. " more\n"
                end
            end
        end
    else
        info_text = info_text .. "(Could not read file info)"
    end

    UIManager:show(ConfirmBox:new{
        text = _("Import this file?\n\n") .. info_text,
        ok_text = _("Choose Deck"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            hub:showImportDeckPicker(file)
        end,
    })
end

function FlashcardsHub:showImportDeckPicker(file)
    local hub = self
    local decks = CardDB.getAllDecks()
    local buttons = {}

    -- Existing decks
    for __, deck in ipairs(decks) do
        table.insert(buttons, {{
            text = deck.name .. " (" .. deck.total .. " cards)",
            callback = function()
                UIManager:close(hub._import_deck_dialog)
                hub:doImport(file.path, deck.id)
            end,
        }})
    end

    -- Create new deck option
    table.insert(buttons, {{
        text = _("✦ Create New Deck"),
        callback = function()
            UIManager:close(hub._import_deck_dialog)
            hub:showImportNewDeckDialog(file)
        end,
    }})

    -- Cancel
    table.insert(buttons, {{
        text = _("Cancel"),
        callback = function()
            UIManager:close(hub._import_deck_dialog)
        end,
    }})

    hub._import_deck_dialog = ButtonDialog:new{
        title = _("Import to which deck?"),
        buttons = buttons,
    }
    UIManager:show(hub._import_deck_dialog)
end

function FlashcardsHub:showImportNewDeckDialog(file)
    local hub = self
    local dialog
    dialog = InputDialog:new{
        title = _("New Deck Name"),
        input = file.filename:gsub("%.apkg$", ""),
        input_hint = _("Enter deck name"),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Create & Import"),
                is_enter_default = true,
                callback = function()
                    local name = dialog:getInputText()
                    name = CozyUI.sanitizeInput(name, 100)
                    if name == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please enter a deck name."),
                            timeout = 2,
                        })
                        return
                    end
                    UIManager:close(dialog)
                    local deck_id = CardDB.createDeck(name)
                    if not deck_id then
                        UIManager:show(InfoMessage:new{
                            text = _("Failed to create deck."),
                            timeout = 3,
                        })
                        return
                    end
                    hub:doImport(file.path, deck_id)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function FlashcardsHub:doImport(apkg_path, deck_id)
    local hub = self
    local AnkiImport = require("lib/anki_import")

    UIManager:show(InfoMessage:new{ text = _("Importing cards..."), timeout = 1 })

    UIManager:scheduleIn(0.1, function()
        local opts = {}
        if deck_id then opts.deck_id = deck_id end
        local ok, message, count = AnkiImport.importFromApkg(apkg_path, opts)
        if ok then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Import Complete!\n\n%s\n\nYour cards are ready for review."), message),
                timeout = 5,
            })
            hub:refresh()
        else
            UIManager:show(InfoMessage:new{
                text = _("Import failed: ") .. tostring(message),
                timeout = 5,
            })
        end
    end)
end

-- ============================================
-- PAINT
-- ============================================

function FlashcardsHub:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, WHITE)
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

-- ============================================
-- PUBLIC API
-- ============================================

function Flashcards.show(ui, on_close_callback)
    if Flashcards._hub_instance then
        UIManager:close(Flashcards._hub_instance)
        Flashcards._hub_instance = nil
    end

    local screen = FlashcardsHub:new{
        ui = ui,
        on_close_callback = on_close_callback,
    }
    UIManager:show(screen)
end

return Flashcards
