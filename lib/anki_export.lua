-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         lib/anki_export.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Exports flashcards from cozy_flashcards.db to
--       Anki-compatible .apkg files. An .apkg is a ZIP
--       containing a SQLite database (collection.anki21)
--       and a media mapping file.
--
--       Ported from cozy.koplugin/lib/anki_export.lua
--       with CardDB bridge pattern (reads cozy_flashcards.db
--       directly, no dependency on flashcards plugin).
--
--   🎀 License:      MIT
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

-- ============================================
-- IMPORTS
-- ============================================

local SQ3 = require("lua-ljsqlite3/init")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

-- ============================================
-- MODULE SETUP
-- ============================================

local AnkiExport = {}

-- ============================================
-- CONSTANTS
-- ============================================

-- Anki model ID (must be unique per note type)
local COZY_MODEL_ID = 1609876543210

-- Anki deck ID
local COZY_DECK_ID = 1609876543211

-- ============================================
-- SECURE HELPER FUNCTIONS
-- ============================================

-- shellEscape removed — os.execute fallbacks eliminated for security

--- Safely removes a directory and all its contents using pure Lua.
local function safeRemoveDirectory(dir_path)
    if not dir_path or dir_path == "" or dir_path == "/" or dir_path == "/mnt" then
        logger.warn("CozyHome AnkiExport: Refusing to remove suspicious path:", dir_path)
        return false
    end

    local attr = lfs.attributes(dir_path)
    if not attr then return true end

    if attr.mode ~= "directory" then
        local ok, err = os.remove(dir_path)
        if not ok then logger.warn("CozyHome AnkiExport: Failed to remove file:", dir_path, err) end
        return ok
    end

    local ok, iter, dir_obj = pcall(lfs.dir, dir_path)
    if not ok then return false end

    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local full_path = dir_path .. "/" .. entry
            local entry_attr = lfs.attributes(full_path)
            if entry_attr then
                if entry_attr.mode == "directory" then
                    safeRemoveDirectory(full_path)
                else
                    os.remove(full_path)
                end
            end
        end
    end

    return lfs.rmdir(dir_path) ~= nil
end

--- Generates a unique Anki-style ID (millisecond timestamp).
local function generateAnkiId()
    return os.time() * 1000 + math.random(0, 999)
end

--- Escapes HTML special characters.
local function htmlEscape(text)
    if not text then return "" end
    text = text:gsub("&", "&amp;")
    text = text:gsub("<", "&lt;")
    text = text:gsub(">", "&gt;")
    text = text:gsub('"', "&quot;")
    text = text:gsub("\n", "<br>")
    return text
end

--- Gets the export directory path, creating it if needed.
local function getExportDir()
    local export_dir = DataStorage:getSettingsDir() .. "/cozy_exports"
    if not lfs.attributes(export_dir) then
        lfs.mkdir(export_dir)
    end
    return export_dir
end

--- Gets a clean temporary directory for building the .apkg.
local function getTempDir()
    local temp_dir = DataStorage:getSettingsDir() .. "/cozy_temp_apkg"
    safeRemoveDirectory(temp_dir)
    lfs.mkdir(temp_dir)
    return temp_dir
end

--- Cleans up temporary files.
local function cleanupTemp(temp_dir)
    safeRemoveDirectory(temp_dir)
end

--- Creates a simple uncompressed ZIP file (store method).
-- Pure-Lua fallback when zip command / ffi/zipwriter are unavailable.
local function createSimpleZip(output_path, files)
    local file = io.open(output_path, "wb")
    if not file then return false end

    local function writeLE16(n)
        file:write(string.char(n % 256, math.floor(n / 256) % 256))
    end
    local function writeLE32(n)
        file:write(string.char(
            n % 256,
            math.floor(n / 256) % 256,
            math.floor(n / 65536) % 256,
            math.floor(n / 16777216) % 256
        ))
    end

    local function crc32(data)
        local crc = 0xFFFFFFFF
        local poly = 0xEDB88320
        for i = 1, #data do
            local b = string.byte(data, i)
            crc = bit.bxor(crc, b)
            for _ = 1, 8 do
                if bit.band(crc, 1) == 1 then
                    crc = bit.bxor(bit.rshift(crc, 1), poly)
                else
                    crc = bit.rshift(crc, 1)
                end
            end
        end
        return bit.bxor(crc, 0xFFFFFFFF)
    end

    local entries = {}
    local offset = 0

    local now = os.date("*t")
    local dos_time = bit.bor(bit.lshift(now.hour, 11), bit.lshift(now.min, 5), math.floor(now.sec / 2))
    local dos_date = bit.bor(bit.lshift(now.year - 1980, 9), bit.lshift(now.month, 5), now.day)

    for _, entry in ipairs(files) do
        local content
        if entry.content then
            content = entry.content
        elseif entry.path then
            local f = io.open(entry.path, "rb")
            content = f and f:read("*all") or ""
            if f then f:close() end
        else
            content = ""
        end

        local name = entry.name
        local crc = crc32(content)
        local size = #content

        table.insert(entries, { name = name, crc = crc, size = size, offset = offset })

        file:write("PK\x03\x04")  -- Local file header signature
        writeLE16(20)              -- Version needed
        writeLE16(0)               -- Flags
        writeLE16(0)               -- Compression (store)
        writeLE16(dos_time)
        writeLE16(dos_date)
        writeLE32(crc)
        writeLE32(size)            -- Compressed size
        writeLE32(size)            -- Uncompressed size
        writeLE16(#name)
        writeLE16(0)               -- Extra field length
        file:write(name)
        file:write(content)

        offset = offset + 30 + #name + size
    end

    -- Central directory
    local cd_offset = offset
    local cd_size = 0

    for _, entry in ipairs(entries) do
        file:write("PK\x01\x02")
        writeLE16(20); writeLE16(20); writeLE16(0); writeLE16(0)
        writeLE16(dos_time); writeLE16(dos_date)
        writeLE32(entry.crc); writeLE32(entry.size); writeLE32(entry.size)
        writeLE16(#entry.name); writeLE16(0); writeLE16(0)
        writeLE16(0); writeLE16(0); writeLE32(0); writeLE32(entry.offset)
        file:write(entry.name)
        cd_size = cd_size + 46 + #entry.name
    end

    -- End of central directory
    file:write("PK\x05\x06")
    writeLE16(0); writeLE16(0)
    writeLE16(#entries); writeLE16(#entries)
    writeLE32(cd_size); writeLE32(cd_offset)
    writeLE16(0)

    file:close()
    return true
end

-- ============================================
-- JSON HELPERS
-- ============================================

local function tableToJson(tbl)
    if type(tbl) ~= "table" then
        if type(tbl) == "string" then
            local s = tbl
            s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
            return '"' .. s .. '"'
        elseif type(tbl) == "boolean" then
            return tbl and "true" or "false"
        elseif tbl == nil then
            return "null"
        else
            return tostring(tbl)
        end
    end

    local is_array = true
    local max_idx = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" then is_array = false; break end
        max_idx = math.max(max_idx, k)
    end
    if is_array and max_idx > 0 then
        local count = 0
        for _ in pairs(tbl) do count = count + 1 end
        if count ~= max_idx then is_array = false end
    end

    local parts = {}
    if is_array and max_idx > 0 then
        for i = 1, max_idx do table.insert(parts, tableToJson(tbl[i])) end
        return "[" .. table.concat(parts, ",") .. "]"
    else
        for k, v in pairs(tbl) do
            local key = type(k) == "string" and k or tostring(k)
            table.insert(parts, '"' .. key .. '":' .. tableToJson(v))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
end

-- ============================================
-- ANKI JSON STRUCTURES
-- ============================================

local function createModelsJson(deck_name)
    local model_name = "Cozy Reader - " .. (deck_name or "Cards")
    local model = {
        [tostring(COZY_MODEL_ID)] = {
            id = COZY_MODEL_ID, name = model_name, type = 0, mod = os.time(), usn = -1,
            sortf = 0, did = COZY_DECK_ID,
            tmpls = {{ name = "Card 1", ord = 0,
                qfmt = "{{Front}}", afmt = "{{FrontSide}}<hr id=answer>{{Back}}",
                bqfmt = "", bafmt = "", bfont = "", bsize = 0 }},
            flds = {
                { name = "Front", ord = 0, sticky = false, rtl = false, font = "Arial", size = 20 },
                { name = "Back",  ord = 1, sticky = false, rtl = false, font = "Arial", size = 20 },
            },
            css = ".card { font-family: arial; font-size: 20px; text-align: center; color: black; background-color: white; }",
            latexPre = "", latexPost = "", latexsvg = false, req = {{0, "any", {0}}},
        }
    }
    return tableToJson(model)
end

local function createDecksJson(deck_name)
    local now = os.time()
    local zeros = {0, 0}
    local deck = {
        [tostring(COZY_DECK_ID)] = {
            id = COZY_DECK_ID, name = deck_name or "Cozy Reader", mod = now, usn = -1,
            lrnToday = zeros, revToday = zeros, newToday = zeros, timeToday = zeros,
            collapsed = false, browserCollapsed = false,
            desc = "Cards exported from Cozy Home", dyn = 0, conf = 1,
            extendNew = 10, extendRev = 50,
        },
        ["1"] = {
            id = 1, name = "Default", mod = now, usn = -1,
            lrnToday = zeros, revToday = zeros, newToday = zeros, timeToday = zeros,
            collapsed = true, browserCollapsed = true, desc = "", dyn = 0, conf = 1,
            extendNew = 10, extendRev = 50,
        }
    }
    return tableToJson(deck)
end

local function createDconfJson()
    return tableToJson({
        ["1"] = {
            id = 1, name = "Default", mod = 0, usn = 0, maxTaken = 60,
            autoplay = true, timer = 0, replayq = true,
            new  = { bury = false, delays = {1, 10}, initialFactor = 2500, ints = {1, 4, 0}, order = 1, perDay = 20 },
            rev  = { bury = false, ease4 = 1.3, ivlFct = 1, maxIvl = 36500, perDay = 200, hardFactor = 1.2 },
            lapse = { delays = {10}, leechAction = 1, leechFails = 8, minInt = 1, mult = 0 },
        }
    })
end

local function createConfJson()
    return tableToJson({
        activeDecks = {1}, curDeck = COZY_DECK_ID, newSpread = 0,
        collapseTime = 1200, timeLim = 0, estTimes = true, dueCounts = true,
        curModel = tostring(COZY_MODEL_ID), nextPos = 1,
        sortType = "noteFld", sortBackwards = false, addToCur = true,
        dayLearnFirst = false, schedVer = 2,
    })
end

local function generateGuid()
    local chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    local guid = ""
    for _ = 1, 10 do
        local idx = math.random(1, #chars)
        guid = guid .. chars:sub(idx, idx)
    end
    return guid
end

local function calculateChecksum(text)
    if not text or text == "" then return 0 end
    local sum = 0
    local check_text = text:sub(1, math.min(#text, 8))
    for i = 1, #check_text do sum = sum + string.byte(check_text, i) end
    return sum
end

-- ============================================
-- ANKI DATABASE CREATION
-- ============================================

local function createAnkiSchema(conn)
    conn:exec([[
        CREATE TABLE IF NOT EXISTS col (
            id INTEGER PRIMARY KEY, crt INTEGER NOT NULL, mod INTEGER NOT NULL,
            scm INTEGER NOT NULL, ver INTEGER NOT NULL, dty INTEGER NOT NULL,
            usn INTEGER NOT NULL, ls INTEGER NOT NULL, conf TEXT NOT NULL,
            models TEXT NOT NULL, decks TEXT NOT NULL, dconf TEXT NOT NULL, tags TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY, guid TEXT NOT NULL, mid INTEGER NOT NULL,
            mod INTEGER NOT NULL, usn INTEGER NOT NULL, tags TEXT NOT NULL,
            flds TEXT NOT NULL, sfld TEXT NOT NULL, csum INTEGER NOT NULL,
            flags INTEGER NOT NULL, data TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS cards (
            id INTEGER PRIMARY KEY, nid INTEGER NOT NULL, did INTEGER NOT NULL,
            ord INTEGER NOT NULL, mod INTEGER NOT NULL, usn INTEGER NOT NULL,
            type INTEGER NOT NULL, queue INTEGER NOT NULL, due INTEGER NOT NULL,
            ivl INTEGER NOT NULL, factor INTEGER NOT NULL, reps INTEGER NOT NULL,
            lapses INTEGER NOT NULL, left INTEGER NOT NULL, odue INTEGER NOT NULL,
            odid INTEGER NOT NULL, flags INTEGER NOT NULL, data TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS revlog (
            id INTEGER PRIMARY KEY, cid INTEGER NOT NULL, usn INTEGER NOT NULL,
            ease INTEGER NOT NULL, ivl INTEGER NOT NULL, lastIvl INTEGER NOT NULL,
            factor INTEGER NOT NULL, time INTEGER NOT NULL, type INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS graves (
            usn INTEGER NOT NULL, oid INTEGER NOT NULL, type INTEGER NOT NULL
        );
    ]])
    pcall(function()
        conn:exec("CREATE INDEX IF NOT EXISTS ix_notes_usn ON notes (usn);")
        conn:exec("CREATE INDEX IF NOT EXISTS ix_cards_usn ON cards (usn);")
        conn:exec("CREATE INDEX IF NOT EXISTS ix_cards_nid ON cards (nid);")
    end)
end

-- ============================================
-- FLASHCARD DATABASE BRIDGE
-- ============================================
-- Reads directly from cozy_flashcards.db (same pattern as notecards.lua CardDB)

local function openFlashcardConn()
    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
    local attr = lfs.attributes(db_path)
    if not attr then return nil end
    local ok, conn = pcall(SQ3.open, db_path, "ro")
    if not ok then return nil end
    return conn
end

--- Fetches all cards from cozy_flashcards.db, optionally filtered.
-- @param options table: {book_path, deck_id, include_suspended}
-- @return table: Array of card records
local function getAllCards(options)
    options = options or {}
    local cards = {}
    local conn = openFlashcardConn()
    if not conn then return cards end

    pcall(function()
        local where_parts = {}
        local bind_vals = {}

        if options.book_path then
            table.insert(where_parts, "book_path = ?")
            table.insert(bind_vals, options.book_path)
        end
        if options.deck_id then
            table.insert(where_parts, "deck_id = ?")
            table.insert(bind_vals, options.deck_id)
        end
        if not options.include_suspended then
            table.insert(where_parts, "suspended = 0")
        end

        local where = ""
        if #where_parts > 0 then
            where = "WHERE " .. table.concat(where_parts, " AND ")
        end

        local stmt = conn:prepare(
            "SELECT id, book_path, book_title, front, back, source_text, source_page, "
            .. "source_chapter, state, interval_days, ease_factor, review_count, "
            .. "correct_count, suspended, next_review, created_at, deck_id "
            .. "FROM flashcards " .. where .. " ORDER BY created_at DESC"
        )
        if stmt then
            if #bind_vals > 0 then stmt:bind(unpack(bind_vals)) end
            for row in stmt:rows() do
                table.insert(cards, {
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
                    created_at = row[16],
                    deck_id = tonumber(row[17]) or 1,
                })
            end
            stmt:close()
        end
    end)

    pcall(function() conn:close() end)
    return cards
end

-- ============================================
-- MAIN EXPORT FUNCTION
-- ============================================

--- Exports flashcards to an Anki .apkg file.
-- @param cards table: Array of flashcard records (or nil to export all)
-- @param deck_name string: Name for the Anki deck
-- @param filename string: Output filename (without .apkg extension)
-- @return boolean, string, number: success, path_or_error, card_count
function AnkiExport.exportToApkg(cards, deck_name, filename)
    -- If no cards passed, fetch all from DB
    if not cards then
        cards = getAllCards({ include_suspended = true })
    end
    if not cards or #cards == 0 then
        return false, "No cards to export", 0
    end

    deck_name = deck_name or "Cozy Reader"
    filename = filename or ("cozy_export_" .. os.date("%Y%m%d_%H%M%S"))
    -- Sanitize filename: strip path separators, .., and non-printable chars
    filename = filename:gsub("[/\\]", "_")
    filename = filename:gsub("[%c]", "")  -- strip control characters
    -- Remove path traversal sequences (use plain find to avoid Lua pattern issues)
    while filename:find("..", 1, true) do
        filename = filename:gsub("%%.%.", "_")
    end
    if filename == "" then filename = "cozy_export_" .. os.date("%Y%m%d_%H%M%S") end

    local temp_dir = getTempDir()
    local db_path = temp_dir .. "/collection.anki21"
    local export_dir = getExportDir()
    local output_path = export_dir .. "/" .. filename .. ".apkg"

    logger.info("CozyHome AnkiExport: Exporting", #cards, "cards to", output_path)

    -- Create the Anki database
    local ok, conn_or_err = pcall(SQ3.open, db_path)
    if not ok then
        cleanupTemp(temp_dir)
        return false, "Failed to create database: " .. tostring(conn_or_err), 0
    end
    local conn = conn_or_err

    createAnkiSchema(conn)

    -- Insert collection metadata
    local now = os.time()
    local col_stmt = conn:prepare([[
        INSERT INTO col (id, crt, mod, scm, ver, dty, usn, ls, conf, models, decks, dconf, tags)
        VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, '{}')
    ]])
    if not col_stmt then
        conn:close(); cleanupTemp(temp_dir)
        return false, "Failed to prepare collection statement", 0
    end
    col_stmt:bind(now, now * 1000, now * 1000,
        createConfJson(), createModelsJson(deck_name), createDecksJson(deck_name), createDconfJson())
    pcall(function() col_stmt:step() end)
    col_stmt:clearbind():reset()

    -- Prepare note and card insert statements
    local note_stmt = conn:prepare([[
        INSERT INTO notes (id, guid, mid, mod, usn, tags, flds, sfld, csum, flags, data)
        VALUES (?, ?, ?, ?, -1, '', ?, ?, ?, 0, '')
    ]])
    local card_stmt = conn:prepare([[
        INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data)
        VALUES (?, ?, ?, 0, ?, -1, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, 0, '')
    ]])
    if not note_stmt or not card_stmt then
        conn:close(); cleanupTemp(temp_dir)
        return false, "Failed to prepare note/card statements", 0
    end

    -- Insert each flashcard as an Anki note + card
    local card_count = 0
    for _, card in ipairs(cards) do
        local note_id = generateAnkiId()
        local card_id = generateAnkiId() + 1

        -- Build Anki fields (front + back separated by 0x1f)
        local sep = string.char(31)
        local front_html = htmlEscape(card.front or "")
        local back_html = htmlEscape(card.back or "")

        -- Append source info to back
        local source_parts = {}
        if card.book_title and card.book_title ~= "" then
            table.insert(source_parts, "Book: " .. card.book_title)
        end
        if card.source_page then
            table.insert(source_parts, "Page: " .. card.source_page)
        end
        if #source_parts > 0 then
            back_html = back_html .. "<br><br><small>" .. table.concat(source_parts, " | ") .. "</small>"
        end

        local flds = front_html .. sep .. back_html
        local sfld = (card.front or ""):sub(1, 100)

        -- Insert note
        note_stmt:bind(note_id, generateGuid(), COZY_MODEL_ID, now, flds, sfld, calculateChecksum(sfld))
        local note_ok = pcall(function() note_stmt:step() end)
        note_stmt:clearbind():reset()
        if not note_ok then goto continue end

        -- Map card state to Anki type/queue
        local anki_type, anki_queue, anki_due, anki_ivl, anki_factor = 0, 0, card_count, 0, 2500
        if card.state == "review" then
            anki_type = 2; anki_queue = 2
            anki_ivl = card.interval_days or 1
            anki_due = math.floor(now / 86400) + (card.interval_days or 1)
            anki_factor = math.floor((card.ease_factor or 2.5) * 1000)
        elseif card.state == "learning" or card.state == "relearning" then
            anki_type = card.state == "relearning" and 3 or 1
            anki_queue = 1; anki_due = now
        end
        if card.suspended == 1 then anki_queue = -1 end

        -- Insert card
        card_stmt:bind(card_id, note_id, COZY_DECK_ID, now,
            anki_type, anki_queue, anki_due, anki_ivl, anki_factor, card.review_count or 0)
        local card_ok = pcall(function() card_stmt:step() end)
        card_stmt:clearbind():reset()
        if card_ok then card_count = card_count + 1 end

        ::continue::
    end

    conn:close()

    if card_count == 0 then
        cleanupTemp(temp_dir)
        return false, "No cards were exported", 0
    end

    -- Create empty media file
    local media_file = io.open(temp_dir .. "/media", "w")
    if media_file then media_file:write("{}"); media_file:close() end

    -- Create the .apkg (ZIP) archive — try multiple methods
    local archive_ok = false

    -- Method 1: KOReader's built-in ZipWriter
    local zip_ok, ZipWriter = pcall(require, "ffi/zipwriter")
    if zip_ok and ZipWriter then
        local writer = ZipWriter:new{}
        if writer:open(output_path) then
            local db_file = io.open(db_path, "rb")
            if db_file then
                writer:add("collection.anki21", db_file:read("*all"))
                db_file:close()
            end
            writer:add("media", "{}")
            writer:close()
            archive_ok = true
        end
    end

    -- Method 2: Pure-Lua uncompressed ZIP
    -- (os.execute shell fallback removed for security — shell injection risk)
    if not archive_ok then
        archive_ok = createSimpleZip(output_path, {
            { name = "collection.anki21", path = db_path },
            { name = "media", content = "{}" },
        })
    end

    cleanupTemp(temp_dir)

    if not archive_ok then
        return false, "Failed to create .apkg archive", 0
    end

    if not lfs.attributes(output_path) then
        return false, "Failed to create .apkg file", 0
    end

    logger.info("CozyHome AnkiExport: Exported", card_count, "cards to", output_path)
    return true, output_path, card_count
end

--- Convenience: export all cards.
function AnkiExport.exportAll(deck_name, filename)
    local cards = getAllCards({ include_suspended = true })
    return AnkiExport.exportToApkg(cards, deck_name, filename)
end

--- Convenience: export cards for a specific book.
function AnkiExport.exportByBook(book_path, deck_name, filename)
    local cards = getAllCards({ book_path = book_path, include_suspended = true })
    return AnkiExport.exportToApkg(cards, deck_name, filename)
end

--- Convenience: export cards for a specific deck.
function AnkiExport.exportByDeck(deck_id, deck_name, filename)
    local cards = getAllCards({ deck_id = deck_id, include_suspended = true })
    return AnkiExport.exportToApkg(cards, deck_name, filename)
end

--- Gets books that have flashcards (for the export-by-book menu).
function AnkiExport.getBooksWithCards()
    local books = {}
    local conn = openFlashcardConn()
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

--- Gets the export directory path (useful for showing user where files go).
function AnkiExport.getExportDir()
    return getExportDir()
end

return AnkiExport
