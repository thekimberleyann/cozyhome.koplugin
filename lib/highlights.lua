-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊
--
--   ⊹  File:         lib/highlights.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-01-30
--   ⊹  Modified:     2026-02-08
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Reads highlights and annotations from KOReader's
--       sidecar files (.sdr/metadata.*.lua). Supports
--       EPUB, KEPUB, and PDF formats.
--       (Ported from Cozy Notes — standalone copy)
--
--   🎀 License:      MIT
--
-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊

-- ============================================
-- IMPORTS
-- ============================================
local DocSettings = require("docsettings")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

-- ============================================
-- MODULE SETUP
-- ============================================

local Highlights = {}

-- ============================================
-- DEBUG FUNCTIONS
-- ============================================

--- Gets debug information about a book's sidecar files
-- @param book_path string: Full path to the book file
-- @return table: Debug info table
function Highlights.getDebugInfo(book_path)
    local info = {
        book_path = book_path,
        book_exists = false,
        sidecar_dir = nil,
        sidecar_exists = false,
        metadata_files = {},
        doc_settings_path = nil,
        annotations_count = 0,
        bookmarks_count = 0,
        highlight_count = 0,
        raw_data = nil,
        errors = {},
    }
    
    if not book_path then
        table.insert(info.errors, "No book path provided")
        return info
    end
    
    local attr = lfs.attributes(book_path)
    info.book_exists = (attr ~= nil)
    if not info.book_exists then
        table.insert(info.errors, "Book file does not exist: " .. book_path)
    end
    
    local sidecar_dir = DocSettings:getSidecarDir(book_path)
    info.sidecar_dir = sidecar_dir
    
    local sidecar_attr = lfs.attributes(sidecar_dir)
    info.sidecar_exists = (sidecar_attr ~= nil and sidecar_attr.mode == "directory")
    
    if not info.sidecar_exists then
        table.insert(info.errors, "Sidecar directory does not exist: " .. sidecar_dir)
    else
        for file in lfs.dir(sidecar_dir) do
            if file ~= "." and file ~= ".." then
                table.insert(info.metadata_files, file)
            end
        end
    end
    
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, book_path)
    
    if not ok then
        table.insert(info.errors, "DocSettings.open failed: " .. tostring(doc_settings))
        return info
    end
    
    if not doc_settings then
        table.insert(info.errors, "DocSettings.open returned nil")
        return info
    end
    
    info.doc_settings_path = doc_settings.sidecar_file or "unknown"
    
    local data = doc_settings.data
    if not data then
        table.insert(info.errors, "DocSettings.data is nil")
        return info
    end
    
    if data.annotations then
        info.annotations_count = #data.annotations
    end
    if data.bookmarks then
        info.bookmarks_count = #data.bookmarks
    end
    if data.highlight then
        for _, page_highlights in pairs(data.highlight) do
            info.highlight_count = info.highlight_count + #page_highlights
        end
    end
    
    local keys = {}
    for k, v in pairs(data) do
        local type_str = type(v)
        if type_str == "table" then
            if v[1] then
                type_str = "array[" .. #v .. "]"
            else
                local count = 0
                for _ in pairs(v) do count = count + 1 end
                type_str = "table{" .. count .. "}"
            end
        end
        table.insert(keys, k .. ":" .. type_str)
    end
    info.raw_data = table.concat(keys, ", ")
    
    return info
end

--- Formats debug info as a string for display
-- @param info table: Debug info from getDebugInfo
-- @return string: Formatted debug info
function Highlights.formatDebugInfo(info)
    local lines = {}
    
    table.insert(lines, "=== Highlight Debug Info ===\n")
    table.insert(lines, "Book: " .. (info.book_path or "nil"))
    table.insert(lines, "Book exists: " .. (info.book_exists and "yes" or "NO"))
    table.insert(lines, "\nSidecar dir: " .. (info.sidecar_dir or "nil"))
    table.insert(lines, "Sidecar exists: " .. (info.sidecar_exists and "yes" or "NO"))
    
    if #info.metadata_files > 0 then
        table.insert(lines, "Files in sidecar:")
        for _, f in ipairs(info.metadata_files) do
            table.insert(lines, "  - " .. f)
        end
    end
    
    table.insert(lines, "\nDocSettings file: " .. (info.doc_settings_path or "nil"))
    
    table.insert(lines, "\nData found:")
    table.insert(lines, "  annotations: " .. info.annotations_count)
    table.insert(lines, "  bookmarks: " .. info.bookmarks_count)
    table.insert(lines, "  highlight pages: " .. info.highlight_count)
    
    if info.raw_data and info.raw_data ~= "" then
        table.insert(lines, "\nAll data keys: " .. info.raw_data)
    end
    
    if #info.errors > 0 then
        table.insert(lines, "\n=== ERRORS ===")
        for _, err in ipairs(info.errors) do
            table.insert(lines, "[X] " .. err)
        end
    else
        table.insert(lines, "\n[OK] No errors")
    end
    
    return table.concat(lines, "\n")
end

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

--- Safely gets highlights from a book's sidecar file
-- @param book_path string: Full path to the book file
-- @return table: Array of highlight objects, or empty table
local function readSidecarHighlights(book_path)
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, book_path)
    
    if not ok or not doc_settings then
        logger.info("CozyHome: Could not open doc settings for", book_path)
        return {}
    end
    
    local data = doc_settings.data
    if not data then
        logger.info("CozyHome: No data in doc settings for", book_path)
        return {}
    end
    
    local highlights = {}
    
    if data.annotations and #data.annotations > 0 then
        logger.dbg("CozyHome: Found", #data.annotations, "annotations")
        for _, annotation in ipairs(data.annotations) do
            if annotation.text and annotation.text ~= "" then
                table.insert(highlights, {
                    text = annotation.text,           
                    note = annotation.note,           
                    chapter = annotation.chapter,     
                    pageno = annotation.pageno,       
                    datetime = annotation.datetime,   
                    drawer = annotation.drawer,       
                    page = annotation.page,           
                    pos0 = annotation.pos0,           
                    pos1 = annotation.pos1,
                })
            end
        end
        return highlights
    end
    
    if data.bookmarks and #data.bookmarks > 0 then
        logger.dbg("CozyHome: Found", #data.bookmarks, "bookmarks (legacy)")
        for _, bookmark in ipairs(data.bookmarks) do
            if bookmark.notes or bookmark.text then
                local highlight_text = bookmark.notes or ""
                local user_note = bookmark.notes and bookmark.text or nil
                
                if highlight_text ~= "" then
                    table.insert(highlights, {
                        text = highlight_text,
                        note = user_note,
                        chapter = bookmark.chapter,
                        pageno = bookmark.page,       
                        page = bookmark.page,         
                        datetime = bookmark.datetime,
                        pos0 = bookmark.pos0,
                        pos1 = bookmark.pos1,
                    })
                end
            end
        end
        return highlights
    end
    
    logger.info("CozyHome: No annotations or bookmarks found in", book_path)
    return highlights
end

-- ============================================
-- PUBLIC FUNCTIONS
-- ============================================

--- Gets all highlights from a book
-- @param book_path string: Full path to the book file
-- @return table: Array of highlight objects
function Highlights.getHighlights(book_path)
    if not book_path then
        return {}
    end
    
    return readSidecarHighlights(book_path)
end

Highlights.getBookHighlights = Highlights.getHighlights

--- Gets highlight count for a book
-- @param book_path string: Full path to the book file
-- @return integer: Number of highlights
function Highlights.getHighlightCount(book_path)
    local items = Highlights.getHighlights(book_path)
    return #items
end

--- Checks if a book has any highlights
-- @param book_path string: Full path to the book file
-- @return boolean: true if book has highlights
function Highlights.hasHighlights(book_path)
    return Highlights.getHighlightCount(book_path) > 0
end

--- Gets highlights organized by chapter
-- @param book_path string: Full path to the book file
-- @return table: {chapter_name = {highlights...}, ...}
function Highlights.getHighlightsByChapter(book_path)
    local highlights = Highlights.getHighlights(book_path)
    local by_chapter = {}
    
    for _, hl in ipairs(highlights) do
        local chapter = hl.chapter or "Unknown Chapter"
        
        if not by_chapter[chapter] then
            by_chapter[chapter] = {}
        end
        
        table.insert(by_chapter[chapter], hl)
    end
    
    return by_chapter
end

--- Gets highlights sorted by page number
-- @param book_path string: Full path to the book file
-- @return table: Array of highlights sorted by page
function Highlights.getHighlightsSorted(book_path)
    local highlights = Highlights.getHighlights(book_path)
    
    table.sort(highlights, function(a, b)
        local page_a = a.pageno or 0
        local page_b = b.pageno or 0
        return page_a < page_b
    end)
    
    return highlights
end

--- Searches highlights for text
-- @param book_path string: Full path to the book file
-- @param query string: Text to search for (case insensitive)
-- @return table: Matching highlights
function Highlights.searchHighlights(book_path, query)
    if not query or query == "" then
        return {}
    end
    
    local highlights = Highlights.getHighlights(book_path)
    local results = {}
    local query_lower = query:lower()
    
    for _, hl in ipairs(highlights) do
        local text_lower = (hl.text or ""):lower()
        local note_lower = (hl.note or ""):lower()
        
        if text_lower:find(query_lower, 1, true) or 
           note_lower:find(query_lower, 1, true) then
            table.insert(results, hl)
        end
    end
    
    return results
end

return Highlights
