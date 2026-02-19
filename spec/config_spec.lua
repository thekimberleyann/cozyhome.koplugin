-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊
--
--   spec/config_spec.lua
--
--   Tests for config.lua — validates structure, required keys,
--   and correct types for all configuration constants.
--
-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊

local mock_koreader = require("spec.mocks.mock_koreader")

describe("config.lua", function()
    local Config

    setup(function()
        mock_koreader.setup()
        Config = require("config")
    end)

    teardown(function()
        mock_koreader.teardown()
    end)

    -- ─── PLUGIN INFO ───

    describe("PLUGIN", function()
        it("exists and is a table", function()
            assert.is_table(Config.PLUGIN)
        end)

        it("has a name", function()
            assert.is_string(Config.PLUGIN.name)
            assert.is_true(#Config.PLUGIN.name > 0)
        end)

        it("has a semver version string", function()
            assert.is_string(Config.PLUGIN.version)
            assert.truthy(
                Config.PLUGIN.version:match("^%d+%.%d+%.%d+"),
                "Version should be semver: " .. Config.PLUGIN.version
            )
        end)

        it("has a human_name", function()
            assert.is_string(Config.PLUGIN.human_name)
        end)

        it("has a description", function()
            assert.is_string(Config.PLUGIN.description)
        end)
    end)

    -- ─── TILES ───

    describe("TILES", function()
        it("exists and is a non-empty array", function()
            assert.is_table(Config.TILES)
            assert.is_true(#Config.TILES >= 1, "Should have at least one tile")
        end)

        it("each tile has required fields", function()
            for i, tile in ipairs(Config.TILES) do
                assert.is_string(tile.key, "Tile " .. i .. " missing key")
                assert.is_string(tile.label, "Tile " .. i .. " missing label")
                assert.is_string(tile.icon_text, "Tile " .. i .. " missing icon_text")
                assert.is_boolean(tile.enabled, "Tile " .. i .. " missing enabled")
            end
        end)

        it("has unique keys", function()
            local seen = {}
            for _, tile in ipairs(Config.TILES) do
                assert.is_nil(seen[tile.key], "Duplicate tile key: " .. tile.key)
                seen[tile.key] = true
            end
        end)

        it("includes the core tiles", function()
            local keys = {}
            for _, tile in ipairs(Config.TILES) do
                keys[tile.key] = true
            end
            assert.is_true(keys["books"], "Missing 'books' tile")
            assert.is_true(keys["highlights"], "Missing 'highlights' tile")
            assert.is_true(keys["settings"], "Missing 'settings' tile")
        end)
    end)

    -- ─── UI LAYOUT ───

    describe("UI", function()
        it("exists and is a table", function()
            assert.is_table(Config.UI)
        end)

        it("has grid layout constants", function()
            assert.is_number(Config.UI.tile_columns)
            assert.is_number(Config.UI.tile_rows)
            assert.is_true(Config.UI.tile_columns >= 1)
            assert.is_true(Config.UI.tile_rows >= 1)
        end)

        it("has header height", function()
            assert.is_number(Config.UI.header_height)
            assert.is_true(Config.UI.header_height > 0)
        end)

        it("has font sizes as positive numbers", function()
            assert.is_number(Config.UI.font_size_title)
            assert.is_true(Config.UI.font_size_title > 0)
            assert.is_number(Config.UI.font_size_stats)
            assert.is_true(Config.UI.font_size_stats > 0)
        end)

        it("has display constants for highlights browser", function()
            assert.is_number(Config.UI.row_height_highlight_list)
            assert.is_number(Config.UI.reserved_height_highlight_list)
            assert.is_number(Config.UI.max_preview_text)
            assert.is_number(Config.UI.max_title_text)
            assert.is_number(Config.UI.max_note_text)
        end)

        it("has display constants for learning space", function()
            assert.is_number(Config.UI.row_height_class_list)
            assert.is_number(Config.UI.reserved_height_class_list)
            assert.is_number(Config.UI.row_height_class_detail)
            assert.is_number(Config.UI.reserved_height_class_detail)
        end)

        it("has animations disabled (e-ink)", function()
            assert.is_false(Config.UI.animations_enabled)
        end)
    end)

    -- ─── SETTINGS KEYS ───

    describe("SETTINGS", function()
        it("exists and is a table", function()
            assert.is_table(Config.SETTINGS)
        end)

        it("has a tile order key", function()
            assert.is_string(Config.SETTINGS.last_tile_order_key)
        end)
    end)

    -- ─── DATABASE ───

    describe("DATABASE", function()
        it("exists and is a table", function()
            assert.is_table(Config.DATABASE)
        end)

        it("has a filename", function()
            assert.is_string(Config.DATABASE.filename)
            assert.truthy(
                Config.DATABASE.filename:match("%.db$"),
                "Database filename should end in .db"
            )
        end)
    end)

    -- ─── FOCUS MODE ───

    describe("FOCUS", function()
        it("exists and is a table", function()
            assert.is_table(Config.FOCUS)
        end)

        it("has positive work duration", function()
            assert.is_number(Config.FOCUS.work_duration)
            assert.is_true(Config.FOCUS.work_duration > 0)
        end)

        it("has positive break durations", function()
            assert.is_number(Config.FOCUS.short_break)
            assert.is_true(Config.FOCUS.short_break > 0)
            assert.is_number(Config.FOCUS.long_break)
            assert.is_true(Config.FOCUS.long_break > 0)
        end)

        it("long break is longer than short break", function()
            assert.is_true(Config.FOCUS.long_break > Config.FOCUS.short_break)
        end)

        it("has sessions_before_long_break", function()
            assert.is_number(Config.FOCUS.sessions_before_long_break)
            assert.is_true(Config.FOCUS.sessions_before_long_break >= 1)
        end)
    end)

    -- ─── DEBUG ───

    describe("DEBUG", function()
        it("exists and is a table", function()
            assert.is_table(Config.DEBUG)
        end)

        it("has boolean flags", function()
            assert.is_boolean(Config.DEBUG.verbose_logging)
            assert.is_boolean(Config.DEBUG.show_debug_menu)
        end)
    end)
end)
