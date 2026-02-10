-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         lib/database.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-05
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       SQLite database wrapper for Cozy Home. Stores
--       hidden folders, preferences, notebooks, strokes,
--       learning spaces, and other persistent data.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local DataStorage = require("datastorage")
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")

local Config = require("config")

local Database = {}
Database._conn = nil
Database._db_path = nil

-- ============================================
-- CONNECTION MANAGEMENT
-- ============================================

function Database:getDbPath()
    if not self._db_path then
        self._db_path = DataStorage:getSettingsDir() .. "/" .. Config.DATABASE.filename
    end
    return self._db_path
end

function Database:open()
    if self._conn then return self._conn end

    local db_path = self:getDbPath()
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok then
        logger.warn("CozyHome DB: failed to open", db_path, conn)
        return nil
    end

    self._conn = conn
    self:createTables()
    return self._conn
end

function Database:close()
    if self._conn then
        self._conn:close()
        self._conn = nil
    end
end

function Database:getConn()
    if not self._conn then
        self:open()
    end
    return self._conn
end

-- ============================================
-- SCHEMA
-- ============================================

function Database:createTables()
    local conn = self._conn
    if not conn then return end

    conn:exec([[
        CREATE TABLE IF NOT EXISTS hidden_folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folder_path TEXT UNIQUE NOT NULL
        );

        CREATE TABLE IF NOT EXISTS preferences (
            key TEXT PRIMARY KEY,
            value TEXT
        );

        CREATE TABLE IF NOT EXISTS homepage_tiles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tile_key TEXT UNIQUE NOT NULL,
            display_order INTEGER DEFAULT 0,
            visible BOOLEAN DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS notebooks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            template TEXT DEFAULT 'grid',
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            page_count INTEGER DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS notebook_pages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            notebook_id INTEGER NOT NULL,
            page_number INTEGER NOT NULL,
            stroke_data BLOB,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (notebook_id) REFERENCES notebooks(id)
        );

        CREATE TABLE IF NOT EXISTS classes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            icon TEXT,
            color TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS class_books (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            book_path TEXT NOT NULL,
            book_title TEXT,
            book_author TEXT,
            added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            last_position TEXT,
            FOREIGN KEY (class_id) REFERENCES classes(id),
            UNIQUE(class_id, book_path)
        );

        CREATE TABLE IF NOT EXISTS class_notebooks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            notebook_id INTEGER NOT NULL,
            FOREIGN KEY (class_id) REFERENCES classes(id),
            FOREIGN KEY (notebook_id) REFERENCES notebooks(id),
            UNIQUE(class_id, notebook_id)
        );

        CREATE TABLE IF NOT EXISTS class_cards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            card_id INTEGER NOT NULL,
            added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (class_id) REFERENCES classes(id),
            UNIQUE(class_id, card_id)
        );

        CREATE TABLE IF NOT EXISTS game_saves (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            game_type TEXT NOT NULL,
            difficulty TEXT,
            state_data BLOB,
            started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS notecard_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            class_id INTEGER,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (class_id) REFERENCES classes(id)
        );

        CREATE TABLE IF NOT EXISTS notecard_category_links (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            card_id INTEGER NOT NULL,
            category_id INTEGER NOT NULL,
            UNIQUE(card_id, category_id),
            FOREIGN KEY (category_id) REFERENCES notecard_categories(id)
        );
    ]])
end

-- ============================================
-- HIDDEN FOLDERS
-- ============================================

--- Get all hidden folder paths as a set (table with path keys, true values).
function Database:getHiddenFolders()
    local result = {}
    local conn = self:getConn()
    if not conn then return result end

    local ok, err = pcall(function()
        local stmt = conn:prepare("SELECT folder_path FROM hidden_folders")
        if stmt then
            for row in stmt:rows() do
                result[row[1]] = true
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getHiddenFolders error:", err)
    end

    return result
end

--- Add a folder path to the hidden list.
function Database:addHiddenFolder(path)
    local conn = self:getConn()
    if not conn then return false end

    -- Normalize: strip trailing slashes for consistent storage
    path = path:gsub("/+$", "")

    local ok, err = pcall(function()
        local stmt = conn:prepare("INSERT OR IGNORE INTO hidden_folders (folder_path) VALUES (?)")
        if stmt then
            stmt:bind(path)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: addHiddenFolder error:", err)
        return false
    end
    return true
end

--- Remove a folder path from the hidden list.
function Database:removeHiddenFolder(path)
    local conn = self:getConn()
    if not conn then return false end

    -- Normalize: strip trailing slashes to match storage format
    path = path:gsub("/+$", "")

    local ok, err = pcall(function()
        local stmt = conn:prepare("DELETE FROM hidden_folders WHERE folder_path = ?")
        if stmt then
            stmt:bind(path)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: removeHiddenFolder error:", err)
        return false
    end
    return true
end

--- Check if a path is hidden.
function Database:isFolderHidden(path)
    local hidden = self:getHiddenFolders()
    return hidden[path] == true or hidden[path:gsub("/$", "")] == true
end

-- ============================================
-- PREFERENCES (key-value)
-- ============================================

--- Get a preference value by key.
function Database:getPref(key, default)
    local conn = self:getConn()
    if not conn then return default end

    local result = default
    local ok, err = pcall(function()
        local stmt = conn:prepare("SELECT value FROM preferences WHERE key = ?")
        if stmt then
            stmt:bind(key)
            local row = stmt:step()
            if row then
                result = row[1]
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getPref error:", err)
    end

    return result
end

--- Set a preference value.
function Database:setPref(key, value)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare("INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)")
        if stmt then
            stmt:bind(key, tostring(value))
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: setPref error:", err)
        return false
    end
    return true
end

-- ============================================
-- NOTEBOOKS
-- ============================================

--- Get all notebooks, ordered by most recently updated.
-- Returns an array of tables: { id, name, template, page_count, created_at, updated_at }
function Database:getNotebooks()
    local result = {}
    local conn = self:getConn()
    if not conn then return result end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT id, name, template, page_count, created_at, updated_at "
            .. "FROM notebooks ORDER BY updated_at DESC"
        )
        if stmt then
            for row in stmt:rows() do
                table.insert(result, {
                    id = row[1],
                    name = row[2],
                    template = row[3],
                    page_count = row[4],
                    created_at = row[5],
                    updated_at = row[6],
                })
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getNotebooks error:", err)
    end

    return result
end

--- Create a new notebook. Returns the new notebook ID, or nil on failure.
function Database:createNotebook(name, template)
    local conn = self:getConn()
    if not conn then return nil end

    template = template or "grid"
    local nb_id = nil

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT INTO notebooks (name, template, page_count) VALUES (?, ?, 1)"
        )
        if stmt then
            stmt:bind(name, template)
            stmt:step()
            stmt:close()
            -- Get the ID of the row we just inserted
            local id_stmt = conn:prepare("SELECT last_insert_rowid()")
            if id_stmt then
                local row = id_stmt:step()
                if row then
                    nb_id = row[1]
                end
                id_stmt:close()
            end
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: createNotebook error:", err)
        return nil
    end

    return nb_id
end

--- Rename a notebook.
function Database:renameNotebook(notebook_id, new_name)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "UPDATE notebooks SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?"
        )
        if stmt then
            stmt:bind(new_name, notebook_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: renameNotebook error:", err)
        return false
    end
    return true
end

--- Delete a notebook and all its pages.
function Database:deleteNotebook(notebook_id)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        -- Delete pages first
        local stmt1 = conn:prepare("DELETE FROM notebook_pages WHERE notebook_id = ?")
        if stmt1 then
            stmt1:bind(notebook_id)
            stmt1:step()
            stmt1:close()
        end
        -- Delete notebook
        local stmt2 = conn:prepare("DELETE FROM notebooks WHERE id = ?")
        if stmt2 then
            stmt2:bind(notebook_id)
            stmt2:step()
            stmt2:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: deleteNotebook error:", err)
        return false
    end
    return true
end

--- Update the timestamp of a notebook to mark it as recently modified.
function Database:updateNotebookTimestamp(notebook_id)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "UPDATE notebooks SET updated_at = CURRENT_TIMESTAMP WHERE id = ?"
        )
        if stmt then
            stmt:bind(notebook_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: updateNotebookTimestamp error:", err)
        return false
    end
    return true
end

--- Set the page count for a notebook.
function Database:setNotebookPageCount(notebook_id, count)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "UPDATE notebooks SET page_count = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?"
        )
        if stmt then
            stmt:bind(count, notebook_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: setNotebookPageCount error:", err)
        return false
    end
    return true
end

-- ============================================
-- NOTEBOOK PAGES (stroke persistence)
-- ============================================

--- Get stroke data for a specific page of a notebook.
-- Returns a deserialized Lua table (array of strokes), or nil if no data exists.
function Database:getPageStrokes(notebook_id, page_number)
    local conn = self:getConn()
    if not conn then return nil end

    local result = nil
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT stroke_data FROM notebook_pages WHERE notebook_id = ? AND page_number = ?"
        )
        if stmt then
            stmt:bind(notebook_id, page_number)
            local row = stmt:step()
            if row and row[1] then
                -- Deserialize the stroke data safely (no loadstring)
                local data_str = row[1]
                if data_str and data_str ~= "" then
                    result = self:deserializeStrokes(data_str)
                end
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getPageStrokes error:", err)
    end

    return result
end

--- Save stroke data for a specific page of a notebook.
-- Strokes is a Lua table (array of stroke objects) that will be serialized.
function Database:savePageStrokes(notebook_id, page_number, strokes)
    local conn = self:getConn()
    if not conn then return false end

    -- Serialize strokes to a Lua table string
    local data_str = self:serializeStrokes(strokes)

    local ok, err = pcall(function()
        -- Upsert: insert or replace
        local stmt = conn:prepare(
            "INSERT OR REPLACE INTO notebook_pages "
            .. "(notebook_id, page_number, stroke_data, updated_at) "
            .. "VALUES (?, ?, ?, CURRENT_TIMESTAMP)"
        )
        if stmt then
            stmt:bind(notebook_id, page_number, data_str)
            stmt:step()
            stmt:close()
        end

        -- We need a unique constraint for the upsert to work.
        -- Create it if it does not exist (safe to call multiple times).
        pcall(function()
            conn:exec(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_notebook_page "
                .. "ON notebook_pages (notebook_id, page_number)"
            )
        end)
    end)
    if not ok then
        logger.warn("CozyHome DB: savePageStrokes error:", err)
        return false
    end
    return true
end

--- Delete a page and renumber subsequent pages.
-- Uses a transaction to keep page numbers consistent if interrupted.
function Database:deleteNotebookPage(notebook_id, page_number, total_pages)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        conn:exec("BEGIN")

        -- Delete the page
        local stmt1 = conn:prepare(
            "DELETE FROM notebook_pages WHERE notebook_id = ? AND page_number = ?"
        )
        if stmt1 then
            stmt1:bind(notebook_id, page_number)
            stmt1:step()
            stmt1:close()
        end

        -- Renumber subsequent pages (shift down by 1), reusing one statement
        if page_number < total_pages then
            local stmt2 = conn:prepare(
                "UPDATE notebook_pages SET page_number = ? WHERE notebook_id = ? AND page_number = ?"
            )
            if stmt2 then
                for pg = page_number + 1, total_pages do
                    stmt2:bind(pg - 1, notebook_id, pg)
                    stmt2:step()
                    stmt2:clearbind():reset()
                end
                stmt2:close()
            end
        end

        conn:exec("COMMIT")
    end)
    if not ok then
        -- Roll back if anything failed mid-transaction
        pcall(function() conn:exec("ROLLBACK") end)
        logger.warn("CozyHome DB: deleteNotebookPage error:", err)
        return false
    end
    return true
end

-- ============================================
-- STROKE SERIALIZATION
-- ============================================

-- ============================================
-- LEARNING SPACE CLASSES
-- ============================================

--- Get all classes, ordered by most recently updated.
function Database:getClasses()
    local result = {}
    local conn = self:getConn()
    if not conn then return result end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT id, name, icon, color, created_at, updated_at "
            .. "FROM classes ORDER BY updated_at DESC"
        )
        if stmt then
            for row in stmt:rows() do
                table.insert(result, {
                    id = row[1],
                    name = row[2],
                    icon = row[3],
                    color = row[4],
                    created_at = row[5],
                    updated_at = row[6],
                })
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClasses error:", err)
    end

    return result
end

--- Get a single class by ID.
function Database:getClass(class_id)
    local conn = self:getConn()
    if not conn then return nil end

    local result = nil
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT id, name, icon, color, created_at, updated_at "
            .. "FROM classes WHERE id = ?"
        )
        if stmt then
            stmt:bind(class_id)
            local row = stmt:step()
            if row then
                result = {
                    id = row[1],
                    name = row[2],
                    icon = row[3],
                    color = row[4],
                    created_at = row[5],
                    updated_at = row[6],
                }
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClass error:", err)
    end

    return result
end

--- Create a new class. Returns the new class ID, or nil on failure.
function Database:createClass(name, icon, color)
    local conn = self:getConn()
    if not conn then return nil end

    local class_id = nil
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT INTO classes (name, icon, color) VALUES (?, ?, ?)"
        )
        if stmt then
            stmt:bind(name, icon, color)
            stmt:step()
            stmt:close()
            local id_stmt = conn:prepare("SELECT last_insert_rowid()")
            if id_stmt then
                local row = id_stmt:step()
                if row then
                    class_id = row[1]
                end
                id_stmt:close()
            end
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: createClass error:", err)
        return nil
    end

    return class_id
end

--- Rename a class.
function Database:renameClass(class_id, new_name)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "UPDATE classes SET name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?"
        )
        if stmt then
            stmt:bind(new_name, class_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: renameClass error:", err)
        return false
    end
    return true
end

--- Delete a class and all its book/notebook associations.
function Database:deleteClass(class_id)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt1 = conn:prepare("DELETE FROM class_books WHERE class_id = ?")
        if stmt1 then stmt1:bind(class_id); stmt1:step(); stmt1:close() end

        local stmt2 = conn:prepare("DELETE FROM class_notebooks WHERE class_id = ?")
        if stmt2 then stmt2:bind(class_id); stmt2:step(); stmt2:close() end

        local stmt3 = conn:prepare("DELETE FROM classes WHERE id = ?")
        if stmt3 then stmt3:bind(class_id); stmt3:step(); stmt3:close() end
    end)
    if not ok then
        logger.warn("CozyHome DB: deleteClass error:", err)
        return false
    end
    return true
end

--- Update the timestamp of a class.
function Database:updateClassTimestamp(class_id)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "UPDATE classes SET updated_at = CURRENT_TIMESTAMP WHERE id = ?"
        )
        if stmt then
            stmt:bind(class_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: updateClassTimestamp error:", err)
    end
    return true
end

-- ============================================
-- CLASS BOOKS
-- ============================================

--- Get all books assigned to a class.
function Database:getClassBooks(class_id)
    local result = {}
    local conn = self:getConn()
    if not conn then return result end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT id, class_id, book_path, book_title, book_author, added_at, last_position "
            .. "FROM class_books WHERE class_id = ? ORDER BY added_at DESC"
        )
        if stmt then
            stmt:bind(class_id)
            for row in stmt:rows() do
                table.insert(result, {
                    id = row[1],
                    class_id = row[2],
                    book_path = row[3],
                    book_title = row[4],
                    book_author = row[5],
                    added_at = row[6],
                    last_position = row[7],
                })
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClassBooks error:", err)
    end

    return result
end

--- Add a book to a class.
function Database:addBookToClass(class_id, book_path, book_title, book_author)
    local conn = self:getConn()
    if not conn then return false end

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
        -- Touch the class timestamp
        local stmt2 = conn:prepare(
            "UPDATE classes SET updated_at = CURRENT_TIMESTAMP WHERE id = ?"
        )
        if stmt2 then
            stmt2:bind(class_id)
            stmt2:step()
            stmt2:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: addBookToClass error:", err)
        return false
    end
    return true
end

--- Remove a book from a class.
function Database:removeBookFromClass(class_id, book_path)
    local conn = self:getConn()
    if not conn then return false end

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
        logger.warn("CozyHome DB: removeBookFromClass error:", err)
        return false
    end
    return true
end

--- Check if a book is in a class.
function Database:isBookInClass(class_id, book_path)
    local conn = self:getConn()
    if not conn then return false end

    local found = false
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT 1 FROM class_books WHERE class_id = ? AND book_path = ?"
        )
        if stmt then
            stmt:bind(class_id, book_path)
            local row = stmt:step()
            found = row ~= nil
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: isBookInClass error:", err)
    end

    return found
end

--- Get count of books in a class.
function Database:getClassBookCount(class_id)
    local conn = self:getConn()
    if not conn then return 0 end

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
        logger.warn("CozyHome DB: getClassBookCount error:", err)
    end

    return count
end

-- ============================================
-- CLASS NOTEBOOKS
-- ============================================

--- Get all notebooks assigned to a class.
function Database:getClassNotebooks(class_id)
    local result = {}
    local conn = self:getConn()
    if not conn then return result end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT cn.notebook_id, n.name, n.template, n.page_count, n.updated_at "
            .. "FROM class_notebooks cn "
            .. "JOIN notebooks n ON cn.notebook_id = n.id "
            .. "WHERE cn.class_id = ? "
            .. "ORDER BY n.updated_at DESC"
        )
        if stmt then
            stmt:bind(class_id)
            for row in stmt:rows() do
                table.insert(result, {
                    notebook_id = row[1],
                    name = row[2],
                    template = row[3],
                    page_count = row[4],
                    updated_at = row[5],
                })
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClassNotebooks error:", err)
    end

    return result
end

--- Link a notebook to a class.
function Database:addNotebookToClass(class_id, notebook_id)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT OR IGNORE INTO class_notebooks (class_id, notebook_id) VALUES (?, ?)"
        )
        if stmt then
            stmt:bind(class_id, notebook_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: addNotebookToClass error:", err)
        return false
    end
    return true
end

--- Unlink a notebook from a class.
function Database:removeNotebookFromClass(class_id, notebook_id)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "DELETE FROM class_notebooks WHERE class_id = ? AND notebook_id = ?"
        )
        if stmt then
            stmt:bind(class_id, notebook_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: removeNotebookFromClass error:", err)
        return false
    end
    return true
end

--- Update the last-opened book position for a class.
function Database:setClassLastBook(class_id, book_path)
    local key = "class_last_book:" .. tostring(class_id)
    return self:setPref(key, book_path)
end

--- Get the last-opened book path for a class.
function Database:getClassLastBook(class_id)
    return self:getPref("class_last_book:" .. tostring(class_id), nil)
end

--- Get count of notebooks in a class.
function Database:getClassNotebookCount(class_id)
    local conn = self:getConn()
    if not conn then return 0 end

    local count = 0
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT COUNT(*) FROM class_notebooks WHERE class_id = ?"
        )
        if stmt then
            stmt:bind(class_id)
            local row = stmt:step()
            if row then count = tonumber(row[1]) or 0 end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getClassNotebookCount error:", err)
    end

    return count
end

-- ============================================
-- CLASS CARDS (extra flashcards linked to a class)
-- ============================================

--- Get all extra card IDs linked to a class.
function Database:getClassCardIds(class_id)
    local ids = {}
    local conn = self:getConn()
    if not conn then return ids end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT card_id FROM class_cards WHERE class_id = ? ORDER BY added_at DESC"
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
        logger.warn("CozyHome DB: getClassCardIds error:", err)
    end
    return ids
end

--- Add a card to a class.
function Database:addCardToClass(class_id, card_id)
    local conn = self:getConn()
    if not conn then return false end

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
        logger.warn("CozyHome DB: addCardToClass error:", err)
    end
    return ok
end

--- Remove a card from a class.
function Database:removeCardFromClass(class_id, card_id)
    local conn = self:getConn()
    if not conn then return false end

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
        logger.warn("CozyHome DB: removeCardFromClass error:", err)
    end
    return ok
end

--- Check if a card is linked to a class.
function Database:isCardInClass(class_id, card_id)
    local conn = self:getConn()
    if not conn then return false end

    local found = false
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT 1 FROM class_cards WHERE class_id = ? AND card_id = ? LIMIT 1"
        )
        if stmt then
            stmt:bind(class_id, card_id)
            local row = stmt:step()
            found = row ~= nil
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: isCardInClass error:", err)
    end
    return found
end

-- ============================================
-- NOTECARD CATEGORIES
-- ============================================

--- Get all notecard categories.
function Database:getCategories()
    local result = {}
    local conn = self:getConn()
    if not conn then return result end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT id, name, class_id, created_at FROM notecard_categories ORDER BY name ASC"
        )
        if stmt then
            for row in stmt:rows() do
                table.insert(result, {
                    id = row[1],
                    name = row[2],
                    class_id = row[3],
                    created_at = row[4],
                })
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getCategories error:", err)
    end

    return result
end

--- Create a new notecard category. Returns the new category ID, or nil on failure.
function Database:createCategory(name, class_id)
    local conn = self:getConn()
    if not conn then return nil end

    local cat_id = nil
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT INTO notecard_categories (name, class_id) VALUES (?, ?)"
        )
        if stmt then
            stmt:bind(name, class_id)
            stmt:step()
            stmt:close()
            local id_stmt = conn:prepare("SELECT last_insert_rowid()")
            if id_stmt then
                local row = id_stmt:step()
                if row then
                    cat_id = row[1]
                end
                id_stmt:close()
            end
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: createCategory error:", err)
        return nil
    end

    return cat_id
end

--- Rename a notecard category.
function Database:renameCategory(category_id, new_name)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "UPDATE notecard_categories SET name = ? WHERE id = ?"
        )
        if stmt then
            stmt:bind(new_name, category_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: renameCategory error:", err)
        return false
    end
    return true
end

--- Delete a notecard category and all its card links.
function Database:deleteCategory(category_id)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt1 = conn:prepare("DELETE FROM notecard_category_links WHERE category_id = ?")
        if stmt1 then stmt1:bind(category_id); stmt1:step(); stmt1:close() end

        local stmt2 = conn:prepare("DELETE FROM notecard_categories WHERE id = ?")
        if stmt2 then stmt2:bind(category_id); stmt2:step(); stmt2:close() end
    end)
    if not ok then
        logger.warn("CozyHome DB: deleteCategory error:", err)
        return false
    end
    return true
end

--- Get card IDs in a category.
function Database:getCategoryCardIds(category_id)
    local result = {}
    local conn = self:getConn()
    if not conn then return result end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT card_id FROM notecard_category_links WHERE category_id = ?"
        )
        if stmt then
            stmt:bind(category_id)
            for row in stmt:rows() do
                table.insert(result, row[1])
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getCategoryCardIds error:", err)
    end

    return result
end

--- Get the count of cards in a category.
function Database:getCategoryCardCount(category_id)
    local conn = self:getConn()
    if not conn then return 0 end

    local count = 0
    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT COUNT(*) FROM notecard_category_links WHERE category_id = ?"
        )
        if stmt then
            stmt:bind(category_id)
            local row = stmt:step()
            if row then count = tonumber(row[1]) or 0 end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getCategoryCardCount error:", err)
    end

    return count
end

--- Add a card to a category.
function Database:addCardToCategory(card_id, category_id)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "INSERT OR IGNORE INTO notecard_category_links (card_id, category_id) VALUES (?, ?)"
        )
        if stmt then
            stmt:bind(card_id, category_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: addCardToCategory error:", err)
        return false
    end
    return true
end

--- Remove a card from a category.
function Database:removeCardFromCategory(card_id, category_id)
    local conn = self:getConn()
    if not conn then return false end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "DELETE FROM notecard_category_links WHERE card_id = ? AND category_id = ?"
        )
        if stmt then
            stmt:bind(card_id, category_id)
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: removeCardFromCategory error:", err)
        return false
    end
    return true
end

--- Get all categories a card belongs to (returns array of {id, name}).
function Database:getCardCategories(card_id)
    local result = {}
    local conn = self:getConn()
    if not conn then return result end

    local ok, err = pcall(function()
        local stmt = conn:prepare(
            "SELECT nc.id, nc.name FROM notecard_categories nc "
            .. "JOIN notecard_category_links ncl ON nc.id = ncl.category_id "
            .. "WHERE ncl.card_id = ? ORDER BY nc.name ASC"
        )
        if stmt then
            stmt:bind(card_id)
            for row in stmt:rows() do
                table.insert(result, {
                    id = row[1],
                    name = row[2],
                })
            end
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: getCardCategories error:", err)
    end

    return result
end

-- ============================================
-- STROKE SERIALIZATION
-- ============================================

--- Safely deserialize a stroke data string using JSON.
-- Expects the format produced by serializeStrokes (JSON array).
-- Falls back to legacy Lua table format for old data (character-validated).
-- @param data_str string: serialized stroke data
-- @return table or nil: deserialized strokes array
function Database:deserializeStrokes(data_str)
    if not data_str or data_str == "" or data_str == "{}" or data_str == "[]" then
        return {}
    end

    -- Try JSON first (new format)
    local json = require("json")
    local json_ok, json_data = pcall(json.decode, data_str)
    if json_ok and type(json_data) == "table" then
        return json_data
    end

    -- Legacy fallback: validate character-by-character before using loadstring.
    -- Only allow: digits, braces, commas, equals, spaces, minus, dots,
    -- and the identifiers x/y/points/width.
    -- Reject anything else (function calls, require, os, io, etc.)
    if data_str:match("[%a_][%a%d_]*%s*%(") then
        logger.warn("CozyHome DB: rejected legacy stroke data containing function call pattern")
        return nil
    end

    -- Check all alphabetic words are in the whitelist
    local safe = true
    local allowed = {x=true, y=true, points=true, width=true}
    data_str:gsub("[%a]+", function(word)
        if not allowed[word] then safe = false end
    end)
    if not safe then
        logger.warn("CozyHome DB: rejected legacy stroke data with unexpected identifiers")
        return nil
    end

    -- Reject any characters that aren't part of a simple table literal
    if data_str:match("[^%d%s{},=xypointswidth%-%.]") then
        logger.warn("CozyHome DB: rejected legacy stroke data with unexpected characters")
        return nil
    end

    local func = loadstring("return " .. data_str)
    if not func then
        logger.warn("CozyHome DB: failed to compile legacy stroke data")
        return nil
    end
    setfenv(func, {})
    local ok, data = pcall(func)
    if ok and type(data) == "table" then
        return data
    end
    logger.warn("CozyHome DB: failed to deserialize legacy stroke data")
    return nil
end

--- Serialize a strokes table to a JSON string.
-- Each stroke is { points = { {x=N, y=N}, ... }, width = N }
-- Uses JSON for safe, portable serialization.
function Database:serializeStrokes(strokes)
    if not strokes or #strokes == 0 then
        return "[]"
    end

    local json = require("json")
    local ok, result = pcall(json.encode, strokes)
    if ok and result then
        return result
    end

    -- Fallback: manual JSON construction if json.encode fails
    local parts = {}
    for _, stroke in ipairs(strokes) do
        local point_strs = {}
        if stroke.points then
            for _, pt in ipairs(stroke.points) do
                table.insert(point_strs,
                    string.format('{"x":%d,"y":%d}', pt.x, pt.y))
            end
        end
        local width = stroke.width or 3
        table.insert(parts,
            string.format('{"points":[%s],"width":%d}',
                table.concat(point_strs, ","), width))
    end

    return "[" .. table.concat(parts, ",") .. "]"
end

-- ============================================
-- FOCUS MODE / GAMIFICATION
-- ============================================

local FOCUS_DATA_FILE = "cozyhome_focus_data.json"

--- Gets the path to the focus game data file
local function getFocusDataPath()
    return DataStorage:getSettingsDir() .. "/" .. FOCUS_DATA_FILE
end

--- Load focus mode gamification data from JSON file.
-- @return table or nil
function Database:getFocusGameData()
    local json = require("json")
    local path = getFocusDataPath()
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*all")
    file:close()
    local ok, data = pcall(json.decode, content)
    if not ok or not data then
        logger.warn("CozyHome DB: failed to parse focus data")
        return nil
    end
    return data
end

--- Save focus mode gamification data to JSON file.
function Database:saveFocusGameData(data)
    local json = require("json")
    local path = getFocusDataPath()
    data.updated_at = os.time()
    local content = json.encode(data)
    if not content then
        logger.warn("CozyHome DB: failed to encode focus data")
        return false
    end
    local file = io.open(path, "w")
    if not file then
        logger.warn("CozyHome DB: failed to open focus data file")
        return false
    end
    file:write(content)
    file:close()
    return true
end

--- Create focus_sessions table if it doesn't exist.
local function ensureFocusSessionsTable(conn)
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
    pcall(function()
        conn:exec("CREATE INDEX IF NOT EXISTS idx_focus_sessions_started ON focus_sessions(started_at);")
    end)
end

--- Add a completed focus session record.
function Database:addFocusSession(session)
    local conn = self:getConn()
    if not conn then
        logger.warn("CozyHome DB: no connection for focus session")
        return false
    end
    ensureFocusSessionsTable(conn)
    local ok, err = pcall(function()
        local stmt = conn:prepare([[
            INSERT INTO focus_sessions
            (book_path, book_title, duration_minutes, pages_read, xp_earned, completed)
            VALUES (?, ?, ?, ?, ?, ?)
        ]])
        if stmt then
            stmt:bind(
                session.book_path,
                session.book_title,
                session.duration_minutes or 0,
                session.pages_read or 0,
                session.xp_earned or 0,
                session.completed and 1 or 0
            )
            stmt:step()
            stmt:close()
        end
    end)
    if not ok then
        logger.warn("CozyHome DB: addFocusSession error:", err)
    end
    return ok
end

--- Get focus session statistics.
function Database:getFocusSessionStats()
    local conn = self:getConn()
    local stats = {
        today_sessions = 0, today_minutes = 0,
        week_sessions = 0, week_minutes = 0,
        total_sessions = 0, total_minutes = 0,
    }
    if not conn then return stats end
    ensureFocusSessionsTable(conn)

    local today = os.date("%Y-%m-%d")
    local week_ago = os.date("%Y-%m-%d", os.time() - 7 * 86400)

    pcall(function()
        local stmt = conn:prepare(
            "SELECT COUNT(*), COALESCE(SUM(duration_minutes),0) FROM focus_sessions WHERE date(started_at) = ? AND completed = 1"
        )
        if stmt then
            stmt:bind(today)
            local row = stmt:step()
            if row then
                stats.today_sessions = tonumber(row[1]) or 0
                stats.today_minutes = tonumber(row[2]) or 0
            end
            stmt:close()
        end
    end)

    pcall(function()
        local stmt = conn:prepare(
            "SELECT COUNT(*), COALESCE(SUM(duration_minutes),0) FROM focus_sessions WHERE date(started_at) >= ? AND completed = 1"
        )
        if stmt then
            stmt:bind(week_ago)
            local row = stmt:step()
            if row then
                stats.week_sessions = tonumber(row[1]) or 0
                stats.week_minutes = tonumber(row[2]) or 0
            end
            stmt:close()
        end
    end)

    pcall(function()
        local stmt = conn:prepare(
            "SELECT COUNT(*), COALESCE(SUM(duration_minutes),0) FROM focus_sessions WHERE completed = 1"
        )
        if stmt then
            local row = stmt:step()
            if row then
                stats.total_sessions = tonumber(row[1]) or 0
                stats.total_minutes = tonumber(row[2]) or 0
            end
            stmt:close()
        end
    end)

    return stats
end

return Database
