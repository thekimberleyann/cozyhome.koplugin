-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊
--
--   spec/helpers.lua
--
--   Shared test helpers for Cozy Home specs.
-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊

local helpers = {}

--- Build a sample annotations table for mock DocSettings
-- @param count number: how many highlights to generate
-- @return table: { annotations = { ... } }
function helpers.make_annotations(count)
    local annotations = {}
    for i = 1, count do
        table.insert(annotations, {
            text = "Highlight " .. i,
            chapter = "Chapter " .. math.ceil(i / 3),
            pageno = i * 10,
            datetime = "2026-01-" .. string.format("%02d", i),
        })
    end
    return { annotations = annotations }
end

--- Build a sample bookmarks table (legacy format)
-- @param count number: how many bookmarks to generate
-- @return table: { bookmarks = { ... } }
function helpers.make_bookmarks(count)
    local bookmarks = {}
    for i = 1, count do
        table.insert(bookmarks, {
            notes = "Bookmark text " .. i,
            text = "User note " .. i,
            chapter = "Chapter " .. math.ceil(i / 2),
            page = i * 5,
            datetime = "2026-01-" .. string.format("%02d", i),
        })
    end
    return { bookmarks = bookmarks }
end

return helpers
