-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         lib/bookscanner.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-06
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Library scanner. Recursively finds supported
--       book files on device, reads metadata (title,
--       author, progress) from DocSettings and
--       CoverBrowser's BookInfoManager cache.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - config.lua
--       - lib/database.lua
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Device = require("device")
local ReadHistory = require("readhistory")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local BookScanner = {}

-- Supported book extensions (lowercase).
-- We check DocumentRegistry too, but this gives us a fast pre-filter.
BookScanner.EXTENSIONS = {
    epub = true,
    pdf = true,
    fb2 = true,
    djvu = true,
    cbz = true,
    cbr = true,
    mobi = true,
    azw = true,
    azw3 = true,
    doc = true,
    docx = true,
    rtf = true,
    txt = true,
    htm = true,
    html = true,
    md = true,
    pdb = true,
    chm = true,
    kepub = true,
    ["fb2.zip"] = true,
}

--- Check if a filename has a supported book extension.
-- @string filename
-- @treturn bool
function BookScanner.isBookFile(filename)
    if not filename then return false end
    local suffix = util.getFileNameSuffix(filename)
    if suffix then
        suffix = suffix:lower()
        if BookScanner.EXTENSIONS[suffix] then
            return true
        end
        -- Check compound extensions like fb2.zip
        local base = filename:match("^(.+)%." .. suffix .. "$")
        if base then
            local sub_suffix = util.getFileNameSuffix(base)
            if sub_suffix then
                local compound = sub_suffix:lower() .. "." .. suffix
                if BookScanner.EXTENSIONS[compound] then
                    return true
                end
            end
        end
    end
    -- Fall back to DocumentRegistry
    return DocumentRegistry:hasProvider(filename)
end

--- Read metadata and reading progress for a single book file.
-- Returns a table with: path, filename, title, authors, series,
-- series_index, pages, percent_finished, has_cover, filesize, filemtime
-- @string filepath full path to book
-- @treturn table book info, or nil on error
function BookScanner.getBookMeta(filepath)
    local directory, filename = util.splitFilePathName(filepath)
    local name_no_ext = filename:gsub("%.%w+$", "")

    local info = {
        path = filepath,
        directory = directory,
        filename = filename,
        title = name_no_ext,
        authors = "",
        series = nil,
        series_index = nil,
        pages = nil,
        percent_finished = nil,
        has_cover = false,
        filesize = 0,
        filemtime = 0,
    }

    -- File attributes
    local attr = lfs.attributes(filepath)
    if attr then
        info.filesize = attr.size or 0
        info.filemtime = attr.modification or 0
    end

    -- Try DocSettings for metadata and progress
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, filepath)
    if ok and doc_settings then
        local doc_props = doc_settings:readSetting("doc_props")
        if doc_props then
            if doc_props.title and doc_props.title ~= "" then
                info.title = doc_props.title
            end
            if doc_props.authors and doc_props.authors ~= "" then
                info.authors = doc_props.authors
            end
            if doc_props.series and doc_props.series ~= "" then
                info.series = doc_props.series
            end
            if doc_props.series_index then
                info.series_index = doc_props.series_index
            end
        end

        local pct = doc_settings:readSetting("percent_finished")
        if pct then
            info.percent_finished = pct
        else
            local page = doc_settings:readSetting("last_page")
            local total = doc_settings:readSetting("doc_pages")
            if page and total and total > 0 then
                info.percent_finished = page / total
            end
        end

        local pages = doc_settings:readSetting("doc_pages")
        if pages then
            info.pages = pages
        end
    end

    -- Try CoverBrowser's BookInfoManager cache for richer metadata.
    -- We only request metadata here (get_cover=false) to keep scanning fast.
    -- Cover images are loaded on demand by the Library screen.
    local bim_ok, BookInfoManager = pcall(require, "bookinfomanager")
    if bim_ok and BookInfoManager then
        -- Ensure BookInfoManager is initialized
        if not BookInfoManager.db_created and BookInfoManager.init then
            pcall(BookInfoManager.init, BookInfoManager)
        end
        local binfo_ok, binfo = pcall(
            BookInfoManager.getBookInfo, BookInfoManager, filepath, false -- false = no cover
        )
        if binfo_ok and binfo then
            if binfo.title and binfo.title ~= "" and not binfo.ignore_meta then
                info.title = binfo.title
            end
            if binfo.authors and binfo.authors ~= "" and not binfo.ignore_meta then
                info.authors = binfo.authors
            end
            if binfo.series and binfo.series ~= "" then
                info.series = binfo.series
            end
            if binfo.series_index then
                info.series_index = binfo.series_index
            end
            if binfo.pages then
                info.pages = binfo.pages
            end
            if binfo.has_cover then
                info.has_cover = true
            end
        end
    end

    return info
end

--- Scan a directory tree for book files.
-- @string root_dir directory to scan
-- @table hidden_folders table of folder paths to skip (keys are paths, values are true)
-- @number max_files maximum number of files to collect (default 5000)
-- @treturn table array of book info tables (minimal: path, directory, filename, filesize, filemtime)
function BookScanner.scan(root_dir, hidden_folders, max_files)
    max_files = max_files or 5000
    hidden_folders = hidden_folders or {}

    local books = {}
    local count = 0

    local function scanDir(dir)
        if count >= max_files then return end

        -- Check if this folder is hidden
        if hidden_folders[dir] then return end
        local dir_clean = dir:gsub("/$", "")
        if hidden_folders[dir_clean] then return end

        local ok, iter, dir_obj = pcall(lfs.dir, dir)
        if not ok then return end

        local subdirs = {}

        for entry in iter, dir_obj do
            if count >= max_files then break end
            if entry ~= "." and entry ~= ".." then
                local fullpath = dir .. "/" .. entry
                local attr = lfs.attributes(fullpath)
                if attr then
                    if attr.mode == "directory" then
                        -- Skip hidden dirs (starting with .)
                        if entry:sub(1, 1) ~= "." then
                            table.insert(subdirs, fullpath)
                        end
                    elseif attr.mode == "file" then
                        if BookScanner.isBookFile(entry) then
                            count = count + 1
                            table.insert(books, {
                                path = fullpath,
                                directory = dir .. "/",
                                filename = entry,
                                filesize = attr.size or 0,
                                filemtime = attr.modification or 0,
                            })
                        end
                    end
                end
            end
        end

        -- Recurse into subdirs
        for _, subdir in ipairs(subdirs) do
            if count >= max_files then break end
            scanDir(subdir)
        end
    end

    scanDir(root_dir)

    return books
end

--- Fast metadata enrichment using only BookInfoManager's SQLite cache.
-- Does a single bulk query instead of opening individual sidecar files.
-- Falls back to filename for any books not in the cache.
-- @table books array of basic book entries from scan()
-- @treturn table the same array, with title and author fields populated
function BookScanner.enrichMetadataFast(books)
    if not books or #books == 0 then return books end

    -- Build a path-to-book lookup
    local by_path = {}
    for _, book in ipairs(books) do
        by_path[book.path] = book
        -- Set defaults from filename
        book.title = book.filename:gsub("%.%w+$", "")
        book.author = ""
    end

    -- Try BookInfoManager's SQLite database directly
    local bim_ok, BookInfoManager = pcall(require, "bookinfomanager")
    if bim_ok and BookInfoManager then
        local db_conn = nil
        pcall(function()
            if not BookInfoManager.db_created and BookInfoManager.init then
                BookInfoManager:init()
            end
            -- Access the internal db connection
            if BookInfoManager.db_conn then
                db_conn = BookInfoManager.db_conn
            end
        end)

        if db_conn then
            -- Query all cached book info in one shot
            local query_ok = pcall(function()
                local stmt = db_conn:prepare(
                    "SELECT directory, filename, title, authors FROM bookinfo"
                )
                if stmt then
                    for row in stmt:rows() do
                        local dir = row[1] or ""
                        local fname = row[2] or ""
                        local full_path = dir .. fname
                        local book = by_path[full_path]
                        if book then
                            local t = row[3]
                            local a = row[4]
                            if t and t ~= "" then
                                book.title = t
                            end
                            if a and a ~= "" then
                                book.author = a
                            end
                        end
                    end
                    stmt:close()
                end
            end)
            if not query_ok then
                logger.dbg("CozyHome: BookInfoManager bulk query failed, using filenames")
            end
        end
    end

    return books
end

--- Enrich a list of scanned book entries with metadata.
-- Reads DocSettings and BookInfoManager data for each book.
-- @table books array of basic book entries from scan()
-- @number batch_size optional limit on how many to enrich (default all)
-- @treturn table the same array, now with metadata fields populated
function BookScanner.enrichMetadata(books, batch_size)
    batch_size = batch_size or #books

    -- Build a lookup from ReadHistory for last-read timestamps.
    -- This lets "recent" sort use actual reading order, not just file mtime.
    local history_order = {}
    local hist_ok = pcall(function()
        local hist = ReadHistory.hist
        if hist then
            for i, entry in ipairs(hist) do
                if entry and entry.file then
                    history_order[entry.file] = i
                end
            end
        end
    end)

    local count = 0
    for _, book in ipairs(books) do
        if count >= batch_size then break end
        local meta = BookScanner.getBookMeta(book.path)
        if meta then
            book.title = meta.title
            book.authors = meta.authors
            book.series = meta.series
            book.series_index = meta.series_index
            book.pages = meta.pages
            book.percent_finished = meta.percent_finished
            book.has_cover = meta.has_cover
        else
            -- Fallback: use filename as title
            book.title = book.filename:gsub("%.%w+$", "")
            book.authors = ""
        end
        -- Attach history position for recent sort
        book._history_order = history_order[book.path]
        count = count + 1
    end

    return books
end

-- ============================================
-- SORTING
-- ============================================

--- Sort books by title (case-insensitive).
function BookScanner.sortByTitle(books)
    table.sort(books, function(a, b)
        return (a.title or ""):lower() < (b.title or ""):lower()
    end)
    return books
end

--- Sort books by author then title.
function BookScanner.sortByAuthor(books)
    table.sort(books, function(a, b)
        local aa = (a.authors or ""):lower()
        local ba = (b.authors or ""):lower()
        if aa == ba then
            return (a.title or ""):lower() < (b.title or ""):lower()
        end
        -- Empty authors go to the end
        if aa == "" then return false end
        if ba == "" then return true end
        return aa < ba
    end)
    return books
end

--- Sort books by most recently read first (falls back to file mtime).
-- Uses ReadHistory order when available so books you actually opened
-- recently appear first, even if their file mtime is old.
function BookScanner.sortByRecent(books)
    table.sort(books, function(a, b)
        -- Books in reading history come first, ordered by history position
        local ha = a._history_order
        local hb = b._history_order
        if ha and hb then
            return ha < hb
        end
        if ha and not hb then return true end
        if hb and not ha then return false end
        -- Both not in history: fall back to file modification time
        return (a.filemtime or 0) > (b.filemtime or 0)
    end)
    return books
end

return BookScanner
