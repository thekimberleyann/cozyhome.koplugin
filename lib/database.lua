-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         lib/database.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-19
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       SQLite database wrapper for Cozy Home.
--       Manages classes (learning spaces), class-book
--       associations, class-card links, focus sessions,
--       focus game data, hidden folders, and user
--       preferences. All functions open/close their own
--       connections or reuse the shared connection.
--
--   🎀 License:      MIT
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local SQ3 = require("lua-ljsqlite3/init")
local DataStorage = require("datastorage")
local Device = require("device")
local logger = require("logger")

-- Config may already be loaded by home.lua or main.lua.
-- If it's missing the DATABASE field, clear and re-require to get our plugin's config.
local Config = require("config")
if not Config.DATABASE then
    package.loaded["config"] = nil
    Config = require("config")
end

local Database = {}

-- Shared connection (opened once, reused)
local _conn = nil
local _tables_created = false

-- ============================================
-- CONNECTION MANAGEMENT
-- ============================================

local function getDatabasePath()
    return DataStorage:getSettingsDir() .. "/" .. Config.DATABASE.filename
end

-- Forward declaration
local createTables

--- Open or return the shared database connection.
-- Creates tables on first open.
local function ensureConn()
    if _conn then return _conn end

    local db_path = getDatabasePath()
    logger.dbg("CozyHome DB: opening database at:", db_path)
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok or not conn then
        logger.warn("CozyHome DB: Failed to open database:", tostring(conn))
        return nil
    end

    -- Performance pragmas for slow Kobo storage
    if Device:canUseWAL() then
        pcall(function() conn:exec("PRAGMA journal_mode=WAL;") end)
    end
    pcall(function() conn:exec("PRAGMA synchronous=NORMAL;") end)
    pcall(function() conn:exec("PRAGMA busy_timeout=3000;") end)
    -- Enable foreign key enforcement
    pcall(function() conn:exec("PRAGMA foreign_keys=ON;") end)

    _conn = conn

    -- Create tables on first connection
    if not _tables_created then
        local tok, terr = pcall(createTables, conn)
        if tok then
            _tables_created = true
            logger.dbg("CozyHome DB: tables initialized")
        else
            logger.warn("CozyHome DB: Failed to create tables:", terr)
        end
    end

    return conn
end

--- Create all required tables. Called once on first open.
createTables = function(conn)
    -- Preferences (key-value store)
    conn:exec([[
        CREATE TABLE IF NOT EXISTS preferences (
            key TEXT PRIMARY KEY,
            value TEXT
        );
    ]])

    -- Classes (learning spaces)
    conn:exec([[
        CREATE TABLE IF NOT EXISTS classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            icon TEXT,
            color TEXT,
            created_at TEXT DEFAULT (datetime('now', 'localtime')),
            sort_order INTEGER DEFAULT 0
        );
    ]])

    -- Class-book associations
    conn:exec([[
        CREATE TABLE IF NOT EXISTS class_books (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            book_path TEXT NOT NULL,
            book_title TEXT,
            book_author TEXT,
            added_at TEXT DEFAULT (datetime('now', 'localtime')),
            UNIQUE(class_id, book_path),
            FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
        );
    ]])

    -- Class-card links (link flashcard IDs from cozy_flashcards.db to a class)
    conn:exec([[
        CREATE TABLE IF NOT EXISTS class_cards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            card_id INTEGER NOT NULL,
            added_at TEXT DEFAULT (datetime('now', 'localtime')),
            UNIQUE(class_id, card_id),
            FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
        );
    ]])

    -- Class last-opened book (quick resume)
    conn:exec([[
        CREATE TABLE IF NOT EXISTS class_last_book (
            class_id INTEGER PRIMARY KEY,
            book_path TEXT NOT NULL,
            updated_at TEXT DEFAULT (datetime('now', 'localtime')),
            FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
        );
    ]])

    -- Focus sessions
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

    -- Focus game data (single-row JSON blob)
    conn:exec([[
        CREATE TABLE IF NOT EXISTS focus_game_data (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            data TEXT NOT NULL,
            updated_at TEXT DEFAULT (datetime('now', 'localtime'))
        );
    ]])

    -- Hidden folders (for library scanner)
    conn:exec([[
        CREATE TABLE IF NOT EXISTS hidden_folders (
            path TEXT PRIMARY KEY
        );
    ]])

    -- Indexes
    pcall(function()
        conn:exec("CREATE INDEX IF NOT EXISTS idx_class_books_class ON class_books(class_id);")
        conn:exec("CREATE INDEX IF NOT EXISTS idx_class_books_path ON class_books(book_path);")
        conn:exec("CREATE INDEX IF NOT EXISTS idx_class_cards_class ON class_cards(class_id);")
        conn:exec("CREATE INDEX IF NOT EXISTS idx_focus_sessions_date ON focus_sessions(started_at);")
    end)

    -- Migrations: add columns that may be missing from older schemas
    pcall(function()
        conn:exec("ALTER TABLE classes ADD COLUMN sort_order INTEGER DEFAULT 0;")
    end)  -- silently fails if column already exists, which is fine
end

-- ============================================
-- INITIALIZATION
-- ============================================

--- Initialize the database. Opens connection and creates tables.
function Database:init()
    ensureConn()
end

--- Open the database connection (alias for init, called by settings).
function Database:open()
    ensureConn()
end

--- Get the raw SQLite connection (for advanced/direct queries).
-- @return connection or nil
function Database:getConn()
    self:init()
    return _conn
end

--- Close the database connection.
function Database:close()
    if _conn then
        pcall(function() _conn:close() end)
        _conn = nil
        _tables_created = false
        logger.dbg("CozyHome DB: closed")
    end
end

-- ============================================
-- PREFERENCES
-- ============================================

--- Get a preference value.
-- @param key string
-- @param default any: returned if key not found
-- @return string value or default
function Database:getPref(key, default)
    local conn = ensureConn()
    if not conn then return default end

    local value = default
    local ok, err = pcall(function()
        local stmt = conn:prepare("SELECT value FROM preferences WHERE key = ?")
        if stmt then
            stmt:bind(key)
            local row = stmt:step()
            if row then value = row[1] end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getPref failed:", err)
    end
    return value
end

--- Set a preference value.
-- @param key string
-- @param value string
-- @return boolean success
function Database:setPref(key, value)
    local conn = ensureConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)"
        )
        if stmt then
            stmt:bind(key, tostring(value))
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: setPref failed:", err)
        return false
    end
    return true
end

-- ============================================
-- CLASSES (Learning Spaces)
-- ============================================

--- Get all classes, ordered by sort_order then name.
-- @return table: array of {id, name, icon, color, created_at, sort_order}
function Database:getClasses()
    local conn = ensureConn()
    if not conn then return {} end

    local classes = {}
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT id, name, icon, color, created_at, sort_order "
            .. "FROM classes ORDER BY sort_order ASC, name ASC"
        )
        if stmt then
            for row in stmt:rows() do
                table.insert(classes, {
                    id = tonumber(row[1]),
                    name = row[2] or "",
                    icon = row[3],
                    color = row[4],
                    created_at = row[5],
                    sort_order = tonumber(row[6]) or 0,
                })
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClasses failed:", err)
    end
    return classes
end

--- Get a single class by ID.
-- @param id number
-- @return table or nil
function Database:getClass(id)
    local conn = ensureConn()
    if not conn or not id then return nil end

    local cls = nil
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT id, name, icon, color, created_at, sort_order "
            .. "FROM classes WHERE id = ?"
        )
        if stmt then
            stmt:bind(id)
            local row = stmt:step()
            if row then
                cls = {
                    id = tonumber(row[1]),
                    name = row[2] or "",
                    icon = row[3],
                    color = row[4],
                    created_at = row[5],
                    sort_order = tonumber(row[6]) or 0,
                }
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClass failed:", err)
    end
    return cls
end

--- Create a new class.
-- @param name string
-- @param icon string (single character)
-- @param color string or nil
-- @return number class_id or nil on failure
function Database:createClass(name, icon, color)
    local conn = ensureConn()
    if not conn or not name or name == "" then return nil end

    local class_id = nil
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT INTO classes (name, icon, color) VALUES (?, ?, ?)"
        )
        if stmt then
            stmt:bind(name, icon, color)
            stmt:step()
            stmt:close()
        end
        -- Get the last inserted ID
        local id_stmt = conn:prepare("SELECT last_insert_rowid()")
        if id_stmt then
            local row = id_stmt:step()
            if row then class_id = tonumber(row[1]) end
            id_stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: createClass failed:", err)
        return nil
    end
    return class_id
end

--- Rename a class.
-- @param id number
-- @param new_name string
-- @return boolean success
function Database:renameClass(id, new_name)
    local conn = ensureConn()
    if not conn or not id or not new_name or new_name == "" then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare("UPDATE classes SET name = ? WHERE id = ?")
        if stmt then
            stmt:bind(new_name, id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: renameClass failed:", err)
        return false
    end
    return true
end

--- Delete a class and all its associations.
-- @param id number
-- @return boolean success
function Database:deleteClass(id)
    local conn = ensureConn()
    if not conn or not id then return false end

    local ok, err = pcall(function()
        -- Delete associations first (in case FOREIGN KEY CASCADE isn't enabled)
        local stmt1 = conn:prepare("DELETE FROM class_books WHERE class_id = ?")
        if stmt1 then stmt1:bind(id); stmt1:step(); stmt1:close() end

        local stmt2 = conn:prepare("DELETE FROM class_cards WHERE class_id = ?")
        if stmt2 then stmt2:bind(id); stmt2:step(); stmt2:close() end

        local stmt3 = conn:prepare("DELETE FROM class_last_book WHERE class_id = ?")
        if stmt3 then stmt3:bind(id); stmt3:step(); stmt3:close() end

        local stmt4 = conn:prepare("DELETE FROM classes WHERE id = ?")
        if stmt4 then stmt4:bind(id); stmt4:step(); stmt4:close() end
    end)
    if not ok then
        logger.warn("CozyHome DB: deleteClass failed:", err)
        return false
    end
    return true
end

-- ============================================
-- CLASS-BOOK ASSOCIATIONS
-- ============================================

--- Get all books in a class.
-- @param class_id number
-- @return table: array of {book_path, book_title, book_author, added_at}
function Database:getClassBooks(class_id)
    local conn = ensureConn()
    if not conn or not class_id then return {} end

    local books = {}
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT book_path, book_title, book_author, added_at "
            .. "FROM class_books WHERE class_id = ? ORDER BY added_at ASC"
        )
        if stmt then
            stmt:bind(class_id)
            for row in stmt:rows() do
                table.insert(books, {
                    book_path = row[1],
                    book_title = row[2],
                    book_author = row[3],
                    added_at = row[4],
                })
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClassBooks failed:", err)
    end
    return books
end

--- Get the count of books in a class.
-- @param class_id number
-- @return number
function Database:getClassBookCount(class_id)
    local conn = ensureConn()
    if not conn or not class_id then return 0 end

    local count = 0
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT COUNT(*) FROM class_books WHERE class_id = ?"
        )
        if stmt then
            stmt:bind(class_id)
            local row = stmt:step()
            if row then count = tonumber(row[1]) or 0 end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClassBookCount failed:", err)
    end
    return count
end

--- Add a book to a class.
-- @param class_id number
-- @param book_path string
-- @param book_title string or nil
-- @param book_author string or nil
-- @return boolean success
function Database:addBookToClass(class_id, book_path, book_title, book_author)
    local conn = ensureConn()
    if not conn or not class_id or not book_path then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT OR IGNORE INTO class_books (class_id, book_path, book_title, book_author) "
            .. "VALUES (?, ?, ?, ?)"
        )
        if stmt then
            stmt:bind(class_id, book_path, book_title, book_author)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: addBookToClass failed:", err)
        return false
    end
    return true
end

--- Remove a book from a class.
-- @param class_id number
-- @param book_path string
-- @return boolean success
function Database:removeBookFromClass(class_id, book_path)
    local conn = ensureConn()
    if not conn or not class_id or not book_path then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "DELETE FROM class_books WHERE class_id = ? AND book_path = ?"
        )
        if stmt then
            stmt:bind(class_id, book_path)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: removeBookFromClass failed:", err)
        return false
    end
    return true
end

--- Check if a book is in a class.
-- @param class_id number
-- @param book_path string
-- @return boolean
function Database:isBookInClass(class_id, book_path)
    local conn = ensureConn()
    if not conn or not class_id or not book_path then return false end

    local found = false
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT 1 FROM class_books WHERE class_id = ? AND book_path = ? LIMIT 1"
        )
        if stmt then
            stmt:bind(class_id, book_path)
            local row = stmt:step()
            found = (row ~= nil)
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: isBookInClass failed:", err)
    end
    return found
end

-- ============================================
-- CLASS-CARD LINKS
-- ============================================

--- Get all card IDs linked to a class (extra cards not from class books).
-- @param class_id number
-- @return table: array of card ID numbers
function Database:getClassCardIds(class_id)
    local conn = ensureConn()
    if not conn or not class_id then return {} end

    local ids = {}
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT card_id FROM class_cards WHERE class_id = ? ORDER BY added_at ASC"
        )
        if stmt then
            stmt:bind(class_id)
            for row in stmt:rows() do
                table.insert(ids, tonumber(row[1]))
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClassCardIds failed:", err)
    end
    return ids
end

--- Add a card to a class.
-- @param class_id number
-- @param card_id number
-- @return boolean success
function Database:addCardToClass(class_id, card_id)
    local conn = ensureConn()
    if not conn or not class_id or not card_id then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT OR IGNORE INTO class_cards (class_id, card_id) VALUES (?, ?)"
        )
        if stmt then
            stmt:bind(class_id, card_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: addCardToClass failed:", err)
        return false
    end
    return true
end

--- Remove a card from a class.
-- @param class_id number
-- @param card_id number
-- @return boolean success
function Database:removeCardFromClass(class_id, card_id)
    local conn = ensureConn()
    if not conn or not class_id or not card_id then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "DELETE FROM class_cards WHERE class_id = ? AND card_id = ?"
        )
        if stmt then
            stmt:bind(class_id, card_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: removeCardFromClass failed:", err)
        return false
    end
    return true
end

--- Check if a card is linked to a class.
-- @param class_id number
-- @param card_id number
-- @return boolean
function Database:isCardInClass(class_id, card_id)
    local conn = ensureConn()
    if not conn or not class_id or not card_id then return false end

    local found = false
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT 1 FROM class_cards WHERE class_id = ? AND card_id = ? LIMIT 1"
        )
        if stmt then
            stmt:bind(class_id, card_id)
            local row = stmt:step()
            found = (row ~= nil)
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: isCardInClass failed:", err)
    end
    return found
end

-- ============================================
-- CLASS LAST BOOK (Quick Resume)
-- ============================================

--- Get the last-opened book path for a class.
-- @param class_id number
-- @return string book_path or nil
function Database:getClassLastBook(class_id)
    local conn = ensureConn()
    if not conn or not class_id then return nil end

    local path = nil
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT book_path FROM class_last_book WHERE class_id = ?"
        )
        if stmt then
            stmt:bind(class_id)
            local row = stmt:step()
            if row then path = row[1] end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClassLastBook failed:", err)
    end
    return path
end

--- Set the last-opened book path for a class.
-- @param class_id number
-- @param book_path string
-- @return boolean success
function Database:setClassLastBook(class_id, book_path)
    local conn = ensureConn()
    if not conn or not class_id or not book_path then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT OR REPLACE INTO class_last_book (class_id, book_path, updated_at) "
            .. "VALUES (?, ?, datetime('now', 'localtime'))"
        )
        if stmt then
            stmt:bind(class_id, book_path)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: setClassLastBook failed:", err)
        return false
    end
    return true
end

-- ============================================
-- FOCUS SESSIONS
-- ============================================

--- Record a completed focus session.
-- @param session_data table: {book_path, book_title, duration_minutes, pages_read, xp_earned, completed}
-- @return boolean success
function Database:addFocusSession(session_data)
    local conn = ensureConn()
    if not conn or not session_data then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT INTO focus_sessions (book_path, book_title, duration_minutes, pages_read, xp_earned, completed) "
            .. "VALUES (?, ?, ?, ?, ?, ?)"
        )
        if stmt then
            stmt:bind(
                session_data.book_path,
                session_data.book_title,
                session_data.duration_minutes or 0,
                session_data.pages_read or 0,
                session_data.xp_earned or 0,
                session_data.completed and 1 or 0
            )
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: addFocusSession failed:", err)
        return false
    end
    return true
end

--- Get aggregate focus session statistics.
-- @return table: {total_sessions, total_minutes, today_sessions, today_minutes, week_sessions, week_minutes}
function Database:getFocusSessionStats()
    local conn = ensureConn()
    local stats = {
        total_sessions = 0, total_minutes = 0,
        today_sessions = 0, today_minutes = 0,
        week_sessions = 0, week_minutes = 0,
    }
    if not conn then return stats end

    local ok, err = pcall(function()
        -- All time
        local stmt = conn:prepare(
            "SELECT COUNT(*), COALESCE(SUM(duration_minutes), 0) "
            .. "FROM focus_sessions WHERE completed = 1"
        )
        if stmt then
            local row = stmt:step()
            if row then
                stats.total_sessions = tonumber(row[1]) or 0
                stats.total_minutes = tonumber(row[2]) or 0
            end
            stmt:close()
        end

        -- Today
        local stmt2 = conn:prepare(
            "SELECT COUNT(*), COALESCE(SUM(duration_minutes), 0) "
            .. "FROM focus_sessions WHERE completed = 1 "
            .. "AND date(started_at) = date('now', 'localtime')"
        )
        if stmt2 then
            local row = stmt2:step()
            if row then
                stats.today_sessions = tonumber(row[1]) or 0
                stats.today_minutes = tonumber(row[2]) or 0
            end
            stmt2:close()
        end

        -- This week (last 7 days)
        local stmt3 = conn:prepare(
            "SELECT COUNT(*), COALESCE(SUM(duration_minutes), 0) "
            .. "FROM focus_sessions WHERE completed = 1 "
            .. "AND date(started_at) >= date('now', 'localtime', '-7 days')"
        )
        if stmt3 then
            local row = stmt3:step()
            if row then
                stats.week_sessions = tonumber(row[1]) or 0
                stats.week_minutes = tonumber(row[2]) or 0
            end
            stmt3:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getFocusSessionStats failed:", err)
    end
    return stats
end

-- ============================================
-- FOCUS GAME DATA (XP, level, streak, achievements)
-- ============================================

--- Load the focus game data JSON blob.
-- @return table or nil
function Database:getFocusGameData()
    local conn = ensureConn()
    if not conn then return nil end

    local data = nil
    local ok, err = pcall(function()
        local stmt = conn:prepare("SELECT data FROM focus_game_data WHERE id = 1")
        if stmt then
            local row = stmt:step()
            if row and row[1] then
                -- Decode JSON
                local json_ok, json_data = pcall(function()
                    local JSON = require("json")
                    return JSON.decode(row[1])
                end)
                if json_ok and type(json_data) == "table" then
                    data = json_data
                end
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getFocusGameData failed:", err)
    end
    return data
end

--- Save the focus game data JSON blob.
-- @param game_data table
-- @return boolean success
function Database:saveFocusGameData(game_data)
    local conn = ensureConn()
    if not conn or not game_data then return false end

    local ok, err = pcall(function()
        local JSON = require("json")
        local json_str = JSON.encode(game_data)

        local stmt = conn:prepare(
            "INSERT OR REPLACE INTO focus_game_data (id, data, updated_at) "
            .. "VALUES (1, ?, datetime('now', 'localtime'))"
        )
        if stmt then
            stmt:bind(json_str)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: saveFocusGameData failed:", err)
        return false
    end
    return true
end

-- ============================================
-- HIDDEN FOLDERS
-- ============================================

--- Get list of hidden folder paths.
-- @return table: array of path strings
function Database:getHiddenFolders()
    local conn = ensureConn()
    if not conn then return {} end

    local folders = {}
    local ok, err = pcall(function()
        local stmt = conn:prepare("SELECT path FROM hidden_folders ORDER BY path ASC")
        if stmt then
            for row in stmt:rows() do
                table.insert(folders, row[1])
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getHiddenFolders failed:", err)
    end
    return folders
end

--- Set the list of hidden folders (replaces all existing).
-- @param folders table: array of path strings
-- @return boolean success
function Database:setHiddenFolders(folders)
    local conn = ensureConn()
    if not conn then return false end

    local ok, err = pcall(function()
        conn:exec("DELETE FROM hidden_folders")
        if folders and #folders > 0 then
            local stmt = conn:prepare("INSERT INTO hidden_folders (path) VALUES (?)")
            if stmt then
                for _, path in ipairs(folders) do
                    stmt:reset()
                    stmt:bind(path)
                    stmt:step()
                end
                stmt:close()
            end
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: setHiddenFolders failed:", err)
        return false
    end
    return true
end

-- ============================================
-- CLEANUP
-- ============================================

-- Initialize on first require (deferred — tables created on first ensureConn call)
-- We don't auto-init here because the DB path depends on DataStorage being ready.
-- Instead, init() is called explicitly by home.lua and settings.lua via Database:open().

return Database
