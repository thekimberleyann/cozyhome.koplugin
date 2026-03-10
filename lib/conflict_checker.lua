-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         lib/conflict_checker.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-03-04
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Detects installed plugins that may conflict with
--       Cozy Home. Returns a list of conflict reports for
--       display in the settings screen or as a warning.
--
--       Checks performed:
--         1. Auto-launch collision (another plugin also set
--            to open on startup)
--         2. Known incompatible plugins (curated list)
--         3. _cozytile.lua key duplicates (two plugins
--            claiming the same tile key)
--
--       All checks are wrapped in pcall — a broken manifest
--       or missing filesystem entry will never surface as
--       an error to the user.
--
--   🎀 License:      MIT
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local lfs = require("libs/libkoreader-lfs")
local DataManager = require("datamanager")
local logger = require("logger")

local ConflictChecker = {}

-- ============================================================
-- Known conflicts table.
-- Add entries here as real-world issues are discovered.
-- severity: "error"   — actively breaks something
--           "warning" — degrades UX or may cause confusion
--           "info"    — cosmetic / user should be aware
-- ============================================================

local KNOWN_CONFLICTS = {
    {
        plugin_dir = "cozylauncher.koplugin",
        name       = "Cozy Launcher",
        severity   = "warning",
        reason     = "Both Cozy Home and Cozy Launcher can auto-launch on startup. "
                  .. "If both are enabled, the one that wins is unpredictable.",
        fix        = "Disable 'Open on startup' in one of the two plugins' settings.",
    },
    {
        plugin_dir = "statistics.koplugin",
        name       = "KOReader Statistics",
        severity   = "info",
        reason     = "The built-in Statistics plugin also tracks reading sessions. "
                  .. "Data may appear to be counted in two places.",
        fix        = "No action needed — both work independently. Disable Statistics "
                  .. "if you prefer Cozy Home as your only session tracker.",
    },
    {
        plugin_dir = "calibre.koplugin",
        name       = "Calibre Wireless",
        severity   = "info",
        reason     = "Calibre sync can trigger book-list refreshes mid-session, "
                  .. "which may cause the home screen stats to update unexpectedly.",
        fix        = "No action needed — this is cosmetic only.",
    },
    {
        plugin_dir = "externalkeyboard.koplugin",
        name       = "External Keyboard",
        severity   = "warning",
        reason     = "External Keyboard intercepts EV_KEY events. If you use keyboard "
                  .. "shortcuts in Cozy Home, some may be captured by this plugin first.",
        fix        = "Check keyboard shortcut assignments in both plugins' settings.",
    },
}

-- ============================================================
-- Internal helpers
-- ============================================================

local function getPluginRoot()
    return DataManager:getDataDir() .. "/plugins"
end

local function isPluginInstalled(plugin_dir)
    local path = getPluginRoot() .. "/" .. plugin_dir
    local ok, attr = pcall(lfs.attributes, path, "mode")
    return ok and attr == "directory"
end

local function getSetting(key)
    if not G_reader_settings then return nil end
    local ok, val = pcall(function()
        return G_reader_settings:readSetting(key)
    end)
    return ok and val or nil
end

-- ============================================================
-- Check 1: Auto-launch collision
-- Only relevant if Cozy Home itself is set to auto-launch.
-- ============================================================

local function checkAutoLaunchCollision()
    local conflicts = {}

    local cozy_autolaunches = G_reader_settings
        and G_reader_settings:isTrue("cozyhome_auto_launch")
    if not cozy_autolaunches then
        -- Cozy Home isn't set to auto-launch, so no collision is possible.
        return conflicts
    end

    if isPluginInstalled("cozylauncher.koplugin") then
        local launcher_on = getSetting("cozylauncher_auto_launch")
        if launcher_on then
            table.insert(conflicts, {
                source   = "auto_launch",
                severity = "error",
                plugin   = "Cozy Launcher",
                reason   = "Both Cozy Home and Cozy Launcher are set to auto-launch. "
                        .. "Only one will actually open — which one wins is unpredictable.",
                fix      = "Disable 'Open on startup' in Cozy Launcher (or here).",
            })
        end
    end

    return conflicts
end

-- ============================================================
-- Check 2: Known incompatible plugins (curated list above)
-- ============================================================

local function checkKnownConflicts()
    local conflicts = {}
    for _, entry in ipairs(KNOWN_CONFLICTS) do
        if isPluginInstalled(entry.plugin_dir) then
            table.insert(conflicts, {
                source   = "known_conflict",
                severity = entry.severity,
                plugin   = entry.name,
                reason   = entry.reason,
                fix      = entry.fix,
            })
        end
    end
    return conflicts
end

-- ============================================================
-- Check 3: _cozytile.lua key duplicates
-- Two plugins in the plugins/ dir claiming the same tile key.
-- ============================================================

local function checkTileKeyDuplicates()
    local conflicts = {}
    local seen_keys = {}  -- key string → plugin_dir that first claimed it
    local plugin_root = getPluginRoot()

    local iter_ok, iter_or_err = pcall(lfs.dir, plugin_root)
    if not iter_ok then
        logger.warn("ConflictChecker: could not scan plugin dir:", iter_or_err)
        return conflicts
    end

    for entry in iter_or_err do
        if entry:match("%.koplugin$") then
            local tile_path = plugin_root .. "/" .. entry .. "/_cozytile.lua"
            local attr_ok, attr = pcall(lfs.attributes, tile_path, "mode")
            if attr_ok and attr == "file" then
                -- Use dofile (not require) so we don't pollute package.loaded
                local load_ok, manifest = pcall(dofile, tile_path)
                if load_ok
                    and type(manifest) == "table"
                    and type(manifest.key) == "string"
                    and manifest.key ~= ""
                then
                    local k = manifest.key
                    if seen_keys[k] then
                        table.insert(conflicts, {
                            source   = "tile_key_duplicate",
                            severity = "warning",
                            plugin   = entry,
                            reason   = string.format(
                                'Tile key "%s" is already claimed by %s. '
                             .. "Only the first plugin found will show its tile "
                             .. "in Cozy Launcher.",
                                k, seen_keys[k]
                            ),
                            fix      = "Rename the key in one plugin's _cozytile.lua file.",
                        })
                    else
                        seen_keys[k] = entry
                    end
                end
            end
        end
    end

    return conflicts
end

-- ============================================================
-- Public API
-- ============================================================

--- Run all conflict checks and return a combined list.
-- Each entry is a table: { source, severity, plugin, reason, fix }
-- severity is one of: "error", "warning", "info"
-- The list is sorted: errors first, then warnings, then info.
-- Returns an empty table if no conflicts are found.
-- Never raises — all checks are pcall-wrapped.
--
-- @return table
function ConflictChecker.check()
    local all = {}

    local checks = {
        checkAutoLaunchCollision,
        checkKnownConflicts,
        checkTileKeyDuplicates,
    }

    for _, check_fn in ipairs(checks) do
        local ok, results = pcall(check_fn)
        if ok and results then
            for _, conflict in ipairs(results) do
                table.insert(all, conflict)
            end
        else
            -- Log the failure but never surface it to the user
            logger.warn("ConflictChecker: a check function failed:", results)
        end
    end

    local order = { error = 1, warning = 2, info = 3 }
    table.sort(all, function(a, b)
        return (order[a.severity] or 9) < (order[b.severity] or 9)
    end)

    return all
end

--- Returns true if any "error" severity conflicts are present.
-- Useful for showing a badge or alert icon without displaying
-- the full conflict list.
--
-- @return boolean
function ConflictChecker.hasErrors()
    for _, c in ipairs(ConflictChecker.check()) do
        if c.severity == "error" then return true end
    end
    return false
end

--- Returns a single human-readable string summarising all conflicts,
-- suitable for showing in an InfoMessage. Returns nil if there are none.
--
-- @return string|nil
function ConflictChecker.summary()
    local results = ConflictChecker.check()
    if #results == 0 then return nil end

    local lines = {}
    local icons = { error = "✗", warning = "!", info = "i" }
    for _, c in ipairs(results) do
        local icon = icons[c.severity] or "?"
        table.insert(lines, string.format("[%s] %s\n%s\n→ %s",
            icon, c.plugin, c.reason, c.fix))
    end
    return table.concat(lines, "\n\n")
end

return ConflictChecker
