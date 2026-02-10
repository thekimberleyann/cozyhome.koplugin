-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊
--
--   ⊹  File:         lib/kobo.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-01-30
--   ⊹  Modified:     2026-02-08
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Reads highlights from Kobo's native SQLite database
--       (KoboReader.sqlite). Captures highlights made in
--       Kobo's stock reader. Read-only access.
--       (Ported from Cozy Notes — standalone copy)
--
--   🎀 License:      MIT
--
-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊

-- ============================================
-- IMPORTS
-- ============================================
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local Kobo = {}

-- ============================================
-- CONSTANTS
-- ============================================
local KOBO_DB_PATH = "/mnt/onboard/.kobo/KoboReader.sqlite"

-- ============================================
-- PRIVATE HELPER FUNCTIONS
-- ============================================

--- Checks if Kobo database exists
-- @return boolean: true if database file exists
local function databaseExists()
    local attr = lfs.attributes(KOBO_DB_PATH)
    return attr ~= nil and attr.mode == "file"
end

--- Opens the Kobo database (read-only)
-- @return database handle or nil
local function openDatabase()
    if not databaseExists() then
        logger.dbg("Kobo: Database not found at", KOBO_DB_PATH)
        return nil
    end
    
    local ok, db = pcall(function()
        return SQ3.open(KOBO_DB_PATH, "ro")  
    end)
    
    if not ok or not db then
        logger.warn("Kobo: Failed to open database:", db)
        return nil
    end
    
    return db
end

--- Converts Kobo's date format to readable format
-- Kobo uses ISO format: 2026-01-30T18:49:34.000
-- @param kobo_date string: Date from Kobo database
-- @return string: Formatted date
local function formatKoboDate(kobo_date)
    if not kobo_date then return nil end
    local formatted = kobo_date:gsub("T", " "):gsub("%.%d+$", "")
    return formatted
end

--- Extracts the book filename from a Kobo ContentID
-- Kobo uses paths like "file:///mnt/onboard/Books/MyBook.epub"
-- @param content_id string: Kobo's ContentID
-- @return string: Just the filename
local function extractFilename(content_id)
    if not content_id then return nil end
    
    local path = content_id:gsub("^file://", "")
    local filename = path:match("([^/]+)$")
    return filename
end

--- Extracts the full path from a Kobo ContentID
-- @param content_id string: Full file path
-- @return string: Full file path
local function extractPath(content_id)
    if not content_id then return nil end
    
    -- Remove "file://" prefix if present
    return content_id:gsub("^file://", "")
end

-- ============================================
-- PUBLIC FUNCTIONS
-- ============================================

--- Checks if Kobo database is available
-- @return boolean: true if we can read from Kobo's database
function Kobo.isAvailable()
    return databaseExists()
end

--- Gets all highlights from Kobo's database for a specific book
-- SECURITY: Uses prepared statements to prevent SQL injection
-- @param book_path string: Full path to the book file
-- @return table: Array of highlight entries
-- @return number: Count of highlights
function Kobo.getBookHighlights(book_path)
    local db = openDatabase()
    
    if not db then
        return {}, 0
    end
    
    local highlights = {}
    
    local content_id = "file://" .. book_path
    local filename = book_path:match("([^/]+)$") or ""
    local filename_pattern = "%" .. filename .. "%" 
    local stmt = db:prepare([[
        SELECT 
            BookmarkID,
            VolumeID,
            ContentID,
            Text,
            Annotation,
            ExtraAnnotationData,
            DateCreated,
            DateModified,
            ChapterProgress,
            Type,
            StartContainerPath,
            EndContainerPath
        FROM Bookmark
        WHERE (VolumeID = ? OR VolumeID = ? OR VolumeID LIKE ?)
        AND (Type = 'highlight' OR Type = 'note' OR Type = 'dogear')
        ORDER BY ChapterProgress ASC, DateCreated ASC
    ]])
    
    if not stmt then
        logger.warn("Kobo: Failed to prepare getBookHighlights statement")
        db:close()
        return {}, 0
    end
    
    stmt:bind(book_path, content_id, filename_pattern)
    
    local ok, err = pcall(function()
        local row = stmt:step()
        while row do
            local highlight = {
                id = row[1],
                volume_id = row[2],
                content_id = row[3],
                text = row[4],
                note = row[5],
                extra_data = row[6],
                datetime = formatKoboDate(row[7]),
                modified = formatKoboDate(row[8]),
                progress = row[9],
                type = row[10],
                start_path = row[11],
                end_path = row[12],
                
                page = nil,  
                chapter = nil,  
                source = "kobo",  
            }

            if highlight.progress then
                highlight.progress_percent = math.floor(tonumber(highlight.progress) * 100)
            end
            

            if highlight.text and highlight.text ~= "" then
                table.insert(highlights, highlight)
            end
            
            row = stmt:step()
        end
    end)
    
    stmt:clearbind():reset()
    db:close()
    
    if not ok then
        logger.warn("Kobo: Query error in getBookHighlights:", err)
        return {}, 0
    end
    
    logger.dbg("Kobo: Found", #highlights, "highlights for", book_path)
    
    return highlights, #highlights
end

--- Gets all books with highlights from Kobo's database
-- SECURITY: Uses static SQL (no user input) - safe
-- @return table: Array of {path, filename, highlight_count}
function Kobo.getAllBooksWithHighlights()
    local db = openDatabase()
    
    if not db then
        return {}
    end
    
    local books = {}
    
    local sql = [[
        SELECT 
            VolumeID,
            COUNT(*) as highlight_count
        FROM Bookmark
        WHERE Type = 'highlight' OR Type = 'note'
        GROUP BY VolumeID
        ORDER BY highlight_count DESC
    ]]
    
    local ok, results_or_err = pcall(function()
        return db:exec(sql)
    end)
    
    db:close()
    
    if not ok then
        logger.warn("Kobo: Query error in getAllBooksWithHighlights:", results_or_err)
        return {}
    end
    
    local results = results_or_err
    
    if not results or not results.VolumeID then
        return {}
    end
    
    for i = 1, #results.VolumeID do
        local volume_id = results.VolumeID[i]
        local count = tonumber(results.highlight_count[i]) or 0
        
        if volume_id and count > 0 then
            table.insert(books, {
                path = extractPath(volume_id),
                filename = extractFilename(volume_id),
                highlight_count = count,
                source = "kobo",
            })
        end
    end
    
    logger.dbg("Kobo: Found", #books, "books with highlights")
    
    return books
end

--- Gets book metadata from Kobo's content table
-- SECURITY: Uses prepared statements to prevent SQL injection
-- @param book_path string: Full path to the book
-- @return table or nil: {title, author, publisher, etc.}
function Kobo.getBookMetadata(book_path)
    local db = openDatabase()
    
    if not db then
        return nil
    end
    
    local content_id = "file://" .. book_path
    local filename = book_path:match("([^/]+)$") or ""
    local filename_pattern = "%" .. filename .. "%"
    
    local stmt = db:prepare([[
        SELECT 
            Title,
            Attribution,
            Publisher,
            Description,
            ContentType,
            MimeType,
            BookTitle,
            NumPages
        FROM content
        WHERE (ContentID = ? OR ContentID = ? OR ContentID LIKE ?)
        AND ContentType = 6
        LIMIT 1
    ]])
    
    if not stmt then
        logger.warn("Kobo: Failed to prepare getBookMetadata statement")
        db:close()
        return nil
    end
    
    stmt:bind(book_path, content_id, filename_pattern)
    
    local metadata = nil
    local ok, err = pcall(function()
        local row = stmt:step()
        if row then
            metadata = {
                title = row[1] or row[7],  
                author = row[2],           
                publisher = row[3],
                description = row[4],
                content_type = row[5],
                mime_type = row[6],
                total_pages = row[8],
            }
        end
    end)
    
    stmt:clearbind():reset()
    db:close()
    
    if not ok then
        logger.warn("Kobo: Query error in getBookMetadata:", err)
        return nil
    end
    
    return metadata
end

--- Gets total highlight count across all books
-- SECURITY: Uses static SQL (no user input) - safe
-- @return number: Total highlights in Kobo database
function Kobo.getTotalHighlightCount()
    local db = openDatabase()
    
    if not db then
        return 0
    end
    
    local count = 0
    
    local ok, result = pcall(function()
        return db:rowexec([[
            SELECT COUNT(*) FROM Bookmark 
            WHERE Type = 'highlight' OR Type = 'note'
        ]])
    end)
    
    db:close()
    
    if ok and result then
        count = tonumber(result) or 0
    else
        logger.warn("Kobo: Count query error:", result)
    end
    
    return count
end

--- Searches highlights across all books in Kobo database
-- SECURITY: Uses prepared statements to prevent SQL injection
-- @param query string: Search text
-- @return table: Matching highlights
function Kobo.searchAllHighlights(query)
    local db = openDatabase()
    
    if not db then
        return {}
    end
    
    local results_list = {}
    if #query > 200 then query = query:sub(1, 200) end
    local search_pattern = "%" .. query .. "%"
    
    local stmt = db:prepare([[
        SELECT 
            BookmarkID,
            VolumeID,
            Text,
            Annotation,
            DateCreated,
            ChapterProgress,
            Type
        FROM Bookmark
        WHERE (Text LIKE ? OR Annotation LIKE ?)
        AND (Type = 'highlight' OR Type = 'note')
        ORDER BY DateCreated DESC
        LIMIT 100
    ]])
    
    if not stmt then
        logger.warn("Kobo: Failed to prepare searchAllHighlights statement")
        db:close()
        return {}
    end
    
    stmt:bind(search_pattern, search_pattern)
    
    local ok, err = pcall(function()
        local row = stmt:step()
        while row do
            table.insert(results_list, {
                id = row[1],
                volume_id = row[2],
                path = extractPath(row[2]),
                filename = extractFilename(row[2]),
                text = row[3],
                note = row[4],
                datetime = formatKoboDate(row[5]),
                progress = row[6],
                type = row[7],
                source = "kobo",
            })
            row = stmt:step()
        end
    end)
    
    stmt:clearbind():reset()
    db:close()
    
    if not ok then
        logger.warn("Kobo: Query error in searchAllHighlights:", err)
        return {}
    end
    
    return results_list
end

return Kobo
