-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         lib/anki_import.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Imports cards from Anki .apkg files into
--       cozy_flashcards.db. Reads the Anki SQLite
--       database inside the archive, extracts notes,
--       and creates flashcards.
--
--       Ported from cozy.koplugin/lib/anki_import.lua
--       with CardDB bridge pattern (writes to
--       cozy_flashcards.db directly).
--
--   🎀 Limitations:
--       - Text-only (no images/audio)
--       - Basic + cloze card types
--       - Imported cards start fresh (no schedule transfer)
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

local AnkiImport = {}

-- ============================================
-- CONSTANTS
-- ============================================

local FIELD_SEPARATOR = string.char(31)  -- 0x1F — Anki's field delimiter
local MAX_IMPORT_SIZE_MB = 100           -- Safety limit for .apkg file size

-- ============================================
-- SECURE HELPER FUNCTIONS
-- ============================================

-- shellEscape removed — os.execute fallbacks eliminated for security

local function safeRemoveDirectory(dir_path)
    if not dir_path or dir_path == "" or dir_path == "/" or dir_path == "/mnt" then
        logger.warn("CozyHome AnkiImport: Refusing to remove suspicious path:", dir_path)
        return false
    end
    local attr = lfs.attributes(dir_path)
    if not attr then return true end
    if attr.mode ~= "directory" then
        os.remove(dir_path)
        return true
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
    lfs.rmdir(dir_path)
    return true
end

local function getTempDir()
    local temp_dir = DataStorage:getSettingsDir() .. "/cozy_temp_import"
    safeRemoveDirectory(temp_dir)
    lfs.mkdir(temp_dir)
    return temp_dir
end

local function cleanupTemp(temp_dir)
    safeRemoveDirectory(temp_dir)
end

local function fileExists(path)
    local attr = lfs.attributes(path)
    return attr ~= nil and attr.mode == "file"
end

-- ============================================
-- HTML / CLOZE HELPERS
-- ============================================

--- Strips HTML tags from text, preserving line breaks.
local function stripHtml(html)
    if not html then return "" end
    local text = html:gsub("<br%s*/?>", "\n")
    text = text:gsub("</p>", "\n"):gsub("</div>", "\n")
    text = text:gsub("<[^>]+>", "")
    text = text:gsub("&nbsp;", " "):gsub("&amp;", "&")
    text = text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
    text = text:gsub("&#(%d+);", function(n)
        local num = tonumber(n)
        return (num and num < 256) and string.char(num) or ""
    end)
    text = text:gsub("\n\n+", "\n\n")
    return text:match("^%s*(.-)%s*$") or text
end

--- Converts Anki cloze deletion to Q/A format.
local function processCloze(text, cloze_num)
    if not text then return "", "" end
    local front, back = text, text

    front = front:gsub("{{c" .. cloze_num .. "::([^:}]+)::([^}]+)}}", "[%2]")
    front = front:gsub("{{c" .. cloze_num .. "::([^}]+)}}", "[...]")

    back = back:gsub("{{c" .. cloze_num .. "::([^:}]+)::([^}]+)}}", "%1")
    back = back:gsub("{{c" .. cloze_num .. "::([^}]+)}}", "%1")

    -- Reveal other clozes in both
    front = front:gsub("{{c%d+::([^:}]+)::([^}]+)}}", "%1")
    front = front:gsub("{{c%d+::([^}]+)}}", "%1")
    back  = back:gsub("{{c%d+::([^:}]+)::([^}]+)}}", "%1")
    back  = back:gsub("{{c%d+::([^}]+)}}", "%1")

    return front, back
end

--- Counts highest cloze number in text.
local function countClozes(text)
    if not text then return 0 end
    local max_cloze = 0
    for num in text:gmatch("{{c(%d+)::") do
        local n = tonumber(num)
        if n and n > max_cloze then max_cloze = n end
    end
    return max_cloze
end

-- ============================================
-- ZIP EXTRACTION
-- ============================================

--- Pure-Lua extraction of uncompressed ZIP files.
local function extractSimpleZip(zip_path, output_dir)
    local file = io.open(zip_path, "rb")
    if not file then return false end
    local content = file:read("*all")
    file:close()

    if not content or #content < 4 or content:sub(1, 4) ~= "PK\x03\x04" then
        return false
    end

    local pos = 1
    local extracted = 0

    while pos <= #content - 30 do
        if content:sub(pos, pos + 3) ~= "PK\x03\x04" then break end

        local function readLE16(off) local b1, b2 = content:byte(off, off + 1); return b1 + b2 * 256 end
        local function readLE32(off)
            local b1, b2, b3, b4 = content:byte(off, off + 3)
            return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        end

        local compression = readLE16(pos + 8)
        local compressed_size = readLE32(pos + 18)
        local uncompressed_size = readLE32(pos + 22)
        local filename_len = readLE16(pos + 26)
        local extra_len = readLE16(pos + 28)

        local filename = content:sub(pos + 30, pos + 29 + filename_len)
        local data_start = pos + 30 + filename_len + extra_len

        if compression == 0 and compressed_size == uncompressed_size then
            local file_data = content:sub(data_start, data_start + compressed_size - 1)
            -- Sanitize filename (prevent path traversal)
            local safe_name = filename:gsub("^/+", "")
            -- Reject any filename containing ".." (path traversal)
            if safe_name:find("..", 1, true) then goto next_entry end
            if not safe_name:match("/$") and #safe_name > 0 then
                local out = io.open(output_dir .. "/" .. safe_name, "wb")
                if out then out:write(file_data); out:close(); extracted = extracted + 1 end
            end
        end

        ::next_entry::
        pos = data_start + compressed_size
    end

    return extracted > 0
end

--- Extracts the .apkg archive using available methods.
local function extractApkg(apkg_path, temp_dir)
    -- Method 1: KOReader's ffi/zipfile
    local zipfile_ok, ZipFile = pcall(require, "ffi/zipfile")
    if zipfile_ok and ZipFile then
        local zip = ZipFile:new{}
        if zip:open(apkg_path) then
            local entries = zip:list()
            if entries then
                for _, entry in ipairs(entries) do
                    local content = zip:read(entry)
                    if content then
                        local safe_name = entry:gsub("^/+", "")
                        -- Reject filenames with path traversal
                        if not safe_name:find("..", 1, true) and #safe_name > 0 and not safe_name:match("/$") then
                            local out = io.open(temp_dir .. "/" .. safe_name, "wb")
                            if out then out:write(content); out:close() end
                        end
                    end
                end
            end
            zip:close()
            if fileExists(temp_dir .. "/collection.anki21") or fileExists(temp_dir .. "/collection.anki2") then
                return true
            end
        end
    end

    -- Method 2: Pure-Lua
    -- (os.execute shell fallback removed for security — shell injection risk)
    return extractSimpleZip(apkg_path, temp_dir)
end

--- Finds the collection database in extracted files.
local function findCollectionDb(temp_dir)
    for _, name in ipairs({"collection.anki21", "collection.anki2", "collection"}) do
        local path = temp_dir .. "/" .. name
        if fileExists(path) then return path end
    end
    return nil
end

-- ============================================
-- ANKI METADATA HELPERS
-- ============================================

local function getDeckName(decks_json, deck_id)
    if not decks_json or not deck_id then return "Imported" end
    local id_str = tostring(deck_id)
    local name = decks_json:match('"' .. id_str .. '":%s*{[^}]*"name"%s*:%s*"([^"]+)"')
    return name and name:gsub('\\"', '"') or "Imported"
end

local function getModelInfo(models_json, model_id)
    local info = { name = "Basic", field_names = {"Front", "Back"}, is_cloze = false }
    if not models_json or not model_id then return info end
    local id_str = tostring(model_id)

    local model_type = models_json:match('"' .. id_str .. '":%s*{[^}]*"type"%s*:%s*(%d)')
    if model_type == "1" then info.is_cloze = true end

    local name = models_json:match('"' .. id_str .. '":%s*{[^}]*"name"%s*:%s*"([^"]+)"')
    if name then info.name = name:gsub('\\"', '"') end

    local fields = {}
    local flds_section = models_json:match('"' .. id_str .. '":%s*{[^}]*"flds"%s*:%s*%[(.-)%]')
    if flds_section then
        for field_name in flds_section:gmatch('"name"%s*:%s*"([^"]+)"') do
            table.insert(fields, field_name:gsub('\\"', '"'))
        end
    end
    if #fields > 0 then info.field_names = fields end

    return info
end

-- ============================================
-- FLASHCARD DATABASE BRIDGE (WRITE)
-- ============================================
-- Writes new cards into cozy_flashcards.db.

local function openFlashcardConnRW()
    local db_path = DataStorage:getSettingsDir() .. "/cozy_flashcards.db"
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok then return nil end

    -- Ensure the flashcards table exists (in case DB is brand new)
    pcall(function()
        conn:exec([[
            CREATE TABLE IF NOT EXISTS flashcards (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                book_path TEXT,
                book_title TEXT,
                front TEXT NOT NULL,
                back TEXT NOT NULL,
                source_text TEXT,
                source_page INTEGER,
                source_chapter TEXT,
                state TEXT DEFAULT 'new',
                interval_days INTEGER DEFAULT 0,
                ease_factor REAL DEFAULT 2.5,
                review_count INTEGER DEFAULT 0,
                correct_count INTEGER DEFAULT 0,
                suspended INTEGER DEFAULT 0,
                next_review TEXT,
                last_reviewed TEXT,
                created_at TEXT DEFAULT (datetime('now', 'localtime')),
                tags TEXT,
                deck_id INTEGER DEFAULT 1
            );
        ]])
    end)

    return conn
end

--- Inserts a single flashcard into cozy_flashcards.db.
-- @param conn: open DB connection
-- @param card table: {front, back, book_title, source_chapter}
-- @return integer or nil: new card ID
local function insertFlashcard(conn, card)
    local stmt = conn:prepare([[
        INSERT INTO flashcards (front, back, book_title, source_chapter, state, deck_id)
        VALUES (?, ?, ?, ?, 'new', 1)
    ]])
    if not stmt then return nil end

    stmt:bind(
        (card.front or ""):sub(1, 5000),
        (card.back or ""):sub(1, 5000),
        card.book_title,
        card.source_chapter
    )

    local ok = pcall(function() stmt:step() end)
    stmt:close()

    if ok then
        local id = tonumber(conn:rowexec("SELECT last_insert_rowid()"))
        return id
    end
    return nil
end

-- ============================================
-- MAIN IMPORT FUNCTION
-- ============================================

--- Imports cards from an Anki .apkg file into cozy_flashcards.db.
-- @param apkg_path string: Path to the .apkg file
-- @param options table: {tag_prefix}
-- @return boolean, string, number: success, message, imported_count
function AnkiImport.importFromApkg(apkg_path, options)
    options = options or {}

    if not apkg_path or not fileExists(apkg_path) then
        return false, "File not found: " .. tostring(apkg_path), 0
    end

    -- Check file size
    local file_attr = lfs.attributes(apkg_path)
    if file_attr and file_attr.size > MAX_IMPORT_SIZE_MB * 1024 * 1024 then
        return false, string.format("File too large (%.1f MB, max %d MB)",
            file_attr.size / (1024 * 1024), MAX_IMPORT_SIZE_MB), 0
    end

    logger.info("CozyHome AnkiImport: Starting import from", apkg_path)

    -- Extract archive
    local temp_dir = getTempDir()
    if not extractApkg(apkg_path, temp_dir) then
        cleanupTemp(temp_dir)
        return false, "Failed to extract .apkg file. Ensure file is valid.", 0
    end

    -- Find collection database
    local db_path = findCollectionDb(temp_dir)
    if not db_path then
        cleanupTemp(temp_dir)
        return false, "No collection database found in .apkg", 0
    end

    -- Open the Anki database (read-only)
    local ok, anki_conn_or_err = pcall(SQ3.open, db_path, "ro")
    if not ok then
        cleanupTemp(temp_dir)
        return false, "Failed to open Anki database: " .. tostring(anki_conn_or_err), 0
    end
    local anki_conn = anki_conn_or_err

    -- Get collection metadata
    local col_data = anki_conn:exec("SELECT decks, models FROM col LIMIT 1")
    local decks_json = col_data and col_data.decks and col_data.decks[1]
    local models_json = col_data and col_data.models and col_data.models[1]

    -- Query notes joined with cards
    local query_ok, results_or_err = pcall(function()
        return anki_conn:exec([[
            SELECT
                n.id as note_id, n.mid as model_id, n.flds as fields, n.tags as tags,
                c.id as card_id, c.did as deck_id, c.type as card_type,
                c.queue as queue, c.ivl as interval, c.factor as factor,
                c.reps as reps, c.ord as card_ord
            FROM notes n
            JOIN cards c ON c.nid = n.id
            ORDER BY n.id, c.ord
        ]])
    end)

    if not query_ok then
        anki_conn:close(); cleanupTemp(temp_dir)
        return false, "Failed to query Anki database: " .. tostring(results_or_err), 0
    end

    local results = results_or_err
    anki_conn:close()

    if not results or not results.note_id then
        cleanupTemp(temp_dir)
        return false, "No cards found in .apkg file", 0
    end

    -- Open our flashcard DB for writing
    local flash_conn = openFlashcardConnRW()
    if not flash_conn then
        cleanupTemp(temp_dir)
        return false, "Failed to open flashcard database for writing", 0
    end

    -- Process and import cards
    local imported, errors = 0, 0

    for i = 1, #results.note_id do
        local model_id = tonumber(results.model_id[i])
        local fields_raw = results.fields[i] or ""
        local deck_id = tonumber(results.deck_id[i])
        local card_ord = tonumber(results.card_ord[i]) or 0

        local model_info = getModelInfo(models_json, model_id)

        -- Split fields by separator
        local fields = {}
        for field in (fields_raw .. FIELD_SEPARATOR):gmatch("([^" .. FIELD_SEPARATOR .. "]*)" .. FIELD_SEPARATOR) do
            table.insert(fields, stripHtml(field))
        end

        local deck_name = getDeckName(decks_json, deck_id)

        -- Build card(s) from this note
        local cards_to_create = {}

        if model_info.is_cloze then
            local cloze_text = fields[1] or ""
            local num_clozes = countClozes(cloze_text)
            local cloze_num = card_ord + 1
            if cloze_num <= num_clozes then
                local front, back = processCloze(cloze_text, cloze_num)
                if front ~= "" and back ~= "" then
                    table.insert(cards_to_create, { front = front, back = back })
                end
            end
        else
            local front = fields[1] or ""
            local back = fields[2] or ""
            if card_ord == 1 and #fields >= 2 then front, back = back, front end
            if front ~= "" and back ~= "" then
                table.insert(cards_to_create, { front = front, back = back })
            end
        end

        -- Insert each card
        for _, card_data in ipairs(cards_to_create) do
            local new_card = {
                front = card_data.front,
                back = card_data.back,
                book_title = "Anki Import: " .. deck_name,
                source_chapter = model_info.name,
            }

            local card_id = insertFlashcard(flash_conn, new_card)
            if card_id then
                imported = imported + 1
            else
                errors = errors + 1
            end
        end
    end

    pcall(function() flash_conn:close() end)
    cleanupTemp(temp_dir)

    -- Build result message
    local message = string.format("Imported %d cards", imported)
    if errors > 0 then
        message = message .. string.format(", %d errors", errors)
    end

    logger.info("CozyHome AnkiImport:", message)
    return true, message, imported
end

--- Lists .apkg files in common locations on the device.
-- @param dir_path string: Specific directory to scan (nil = scan defaults)
-- @return table: Array of {path, filename, size, modified, size_kb}
function AnkiImport.listApkgFiles(dir_path)
    local files = {}

    local dirs_to_check = {}
    if dir_path then
        table.insert(dirs_to_check, dir_path)
    else
        table.insert(dirs_to_check, "/mnt/onboard")
        table.insert(dirs_to_check, "/mnt/onboard/imports")
        table.insert(dirs_to_check, "/mnt/onboard/Anki")
        table.insert(dirs_to_check, DataStorage:getSettingsDir() .. "/cozy_exports")
    end

    for _, dir in ipairs(dirs_to_check) do
        local ok, iter, dir_obj = pcall(lfs.dir, dir)
        if ok then
            for entry in iter, dir_obj do
                if entry:match("%.apkg$") then
                    local full_path = dir .. "/" .. entry
                    local attr = lfs.attributes(full_path)
                    if attr and attr.mode == "file" then
                        table.insert(files, {
                            path = full_path,
                            filename = entry,
                            size = attr.size,
                            modified = attr.modification,
                            size_kb = math.floor(attr.size / 1024),
                        })
                    end
                end
            end
        end
    end

    table.sort(files, function(a, b) return (a.modified or 0) > (b.modified or 0) end)
    return files
end

--- Gets info about an .apkg file without importing.
-- @param apkg_path string: Path to .apkg file
-- @return table or nil: {deck_count, card_count, note_count, decks}
function AnkiImport.getApkgInfo(apkg_path)
    if not fileExists(apkg_path) then return nil end

    local temp_dir = getTempDir()
    if not extractApkg(apkg_path, temp_dir) then
        cleanupTemp(temp_dir); return nil
    end

    local db_path = findCollectionDb(temp_dir)
    if not db_path then cleanupTemp(temp_dir); return nil end

    local ok, conn_or_err = pcall(SQ3.open, db_path, "ro")
    if not ok then cleanupTemp(temp_dir); return nil end
    local conn = conn_or_err

    local info = { deck_count = 0, card_count = 0, note_count = 0, decks = {} }

    pcall(function()
        info.note_count = tonumber(conn:rowexec("SELECT COUNT(*) FROM notes")) or 0
        info.card_count = tonumber(conn:rowexec("SELECT COUNT(*) FROM cards")) or 0

        local col_data = conn:exec("SELECT decks FROM col LIMIT 1")
        if col_data and col_data.decks and col_data.decks[1] then
            for name in col_data.decks[1]:gmatch('"name"%s*:%s*"([^"]+)"') do
                if name ~= "Default" then
                    table.insert(info.decks, name:gsub('\\"', '"'))
                    info.deck_count = info.deck_count + 1
                end
            end
        end
    end)

    conn:close()
    cleanupTemp(temp_dir)
    return info
end

return AnkiImport
