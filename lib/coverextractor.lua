-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         lib/coverextractor.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Standalone cover image extractor. Opens book files
--       (EPUB, PDF, CBZ, etc.) via KOReader's DocumentRegistry,
--       pulls out the cover image, and scales it to a target
--       size using MuPDF for high-quality downscaling.
--
--       Fully independent — does NOT depend on CoverBrowser,
--       ProjectTitle, or any third-party plugin.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       - KOReader built-ins only:
--         DocumentRegistry, DocSettings, RenderImage, Blitbuffer
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local Blitbuffer = require("ffi/blitbuffer")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local RenderImage = require("ui/renderimage")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local CoverExtractor = {}

-- Maximum pixel dimension for cached covers.
-- 600px matches ProjectTitle's proven quality and is more than enough
-- for a 3-column gallery on a 1264px-wide screen (~358px per tile).
-- Covers are scaled down to fit within this box while preserving
-- aspect ratio. Larger values use more memory per cover.
local MAX_COVER_DIMEN = 600

--- Extract a cover Blitbuffer from a book file.
--
-- Opens the book just enough to pull the embedded cover image,
-- then scales it down to MAX_COVER_DIMEN. The returned Blitbuffer
-- is owned by the caller (caller must :free() it when done).
--
-- @param filepath  string: full path to the book file
-- @return          Blitbuffer or nil: the cover image, scaled
function CoverExtractor.extract(filepath)
    -- Bail early if file doesn't exist or has no document provider
    if not filepath then return nil end
    local attr = lfs.attributes(filepath, "mode")
    if attr ~= "file" then return nil end
    if not DocumentRegistry:hasProvider(filepath) then return nil end

    -- Check for a user-set custom cover first (same logic KOReader uses)
    local cover_bb = nil
    local custom_cover = DocSettings:findCustomCoverFile(filepath)
    if custom_cover then
        local ok_custom, cover_doc = pcall(DocumentRegistry.openDocument, DocumentRegistry, custom_cover)
        if ok_custom and cover_doc then
            local ok_img, img = pcall(cover_doc.getCoverPageImage, cover_doc)
            if ok_img and img then
                cover_bb = img
            end
            cover_doc:close()
        end
    end

    -- If no custom cover, open the book itself
    if not cover_bb then
        local ok_open, doc = pcall(DocumentRegistry.openDocument, DocumentRegistry, filepath)
        if not ok_open or not doc then
            return nil
        end

        -- For CRE documents (EPUB, FB2, etc.), load only metadata — not the full book.
        -- This is much faster and uses less memory.
        if doc.loadDocument then
            local ok_load = pcall(doc.loadDocument, doc, false) -- false = metadata only
            if not ok_load then
                doc:close()
                return nil
            end
        end

        local ok_img, img = pcall(doc.getCoverPageImage, doc)
        if ok_img and img then
            cover_bb = img
        end
        doc:close()
    end

    if not cover_bb then
        return nil
    end

    -- Scale down to our target max dimension, preserving aspect ratio.
    -- RenderImage:scaleBlitBuffer uses MuPDF for high-quality scaling.
    local src_w = cover_bb:getWidth()
    local src_h = cover_bb:getHeight()

    if src_w > MAX_COVER_DIMEN or src_h > MAX_COVER_DIMEN then
        local scale
        if src_w >= src_h then
            -- Landscape or square: constrain by width
            scale = MAX_COVER_DIMEN / src_w
        else
            -- Portrait (most book covers): constrain by height
            scale = MAX_COVER_DIMEN / src_h
        end
        local new_w = math.floor(src_w * scale + 0.5)
        local new_h = math.floor(src_h * scale + 0.5)
        -- scaleBlitBuffer frees the original by default (free_orig_bb ~= false)
        cover_bb = RenderImage:scaleBlitBuffer(cover_bb, new_w, new_h, true)
    end

    return cover_bb
end

return CoverExtractor
