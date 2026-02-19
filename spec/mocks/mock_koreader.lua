-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊
--
--   spec/mocks/mock_koreader.lua
--
--   Minimal mocks for KOReader dependencies so that
--   lib/ modules can be loaded outside the KOReader runtime.
--
--   Usage: call M.setup() in setup(), M.teardown() in teardown()
-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊

local M = {}

-- ─── Path setup ───
-- Ensure the project root is on package.path so require("config"),
-- require("lib/highlights"), etc. resolve correctly from spec/.
local function ensure_project_root_on_path()
    -- Determine project root: this file is at spec/mocks/mock_koreader.lua
    -- so project root is two levels up.
    local info = debug.getinfo(1, "S")
    local this_file = info and info.source and info.source:match("@?(.*)") or ""
    -- Normalize path separators
    this_file = this_file:gsub("\\", "/")
    local project_root = this_file:match("(.*/)[^/]+/[^/]+$") or "./"
    -- Strip trailing spec/ if present
    project_root = project_root:gsub("spec/$", "")
    if project_root == "" then project_root = "./" end

    -- Add project root to package.path if not already there
    local root_pattern = project_root:gsub("([%.%-%+])", "%%%1")
    if not package.path:find(root_pattern) then
        package.path = project_root .. "?.lua;" ..
                       project_root .. "?/init.lua;" ..
                       package.path
    end
    return project_root
end

M._project_root = ensure_project_root_on_path()

-- ─── DocSettings mock ───
-- Tests can set DocSettingsMock._mock_data[path] = { annotations = {...}, ... }
-- and DocSettings:open(path) will return an object with that .data table.

local DocSettingsMock = {}
DocSettingsMock.__index = DocSettingsMock
DocSettingsMock._mock_data = {}

function DocSettingsMock:open(path)
    local instance = setmetatable({}, DocSettingsMock)
    instance.data = DocSettingsMock._mock_data[path] or {}
    instance.sidecar_file = path .. ".sdr/metadata.epub.lua"
    return instance
end

function DocSettingsMock:getSidecarDir(path)
    return path .. ".sdr"
end

-- ─── Setup / Teardown ───

function M.setup()
    -- Make sure project root is on path
    ensure_project_root_on_path()

    -- Logger: no-op (all levels silenced)
    package.loaded["logger"] = {
        info = function() end,
        warn = function() end,
        err  = function() end,
        dbg  = function() end,
    }

    -- DocSettings
    DocSettingsMock._mock_data = {}
    package.loaded["docsettings"] = DocSettingsMock

    -- lfs: minimal fake
    package.loaded["libs/libkoreader-lfs"] = {
        attributes = function() return nil end,
        dir = function()
            return function() return nil end
        end,
        symlinkattributes = function() return nil end,
    }

    -- Config: force a fresh load from the real file.
    -- config.lua has no KOReader dependencies so it loads standalone.
    package.loaded["config"] = nil

    -- Clear any previously loaded lib modules so they pick up the mocks
    package.loaded["lib/highlights"] = nil
end

function M.teardown()
    package.loaded["logger"] = nil
    package.loaded["docsettings"] = nil
    package.loaded["libs/libkoreader-lfs"] = nil
    package.loaded["config"] = nil
    package.loaded["lib/highlights"] = nil
end

--- Convenience: return the DocSettingsMock so tests can set _mock_data
function M.getDocSettingsMock()
    return DocSettingsMock
end

return M
