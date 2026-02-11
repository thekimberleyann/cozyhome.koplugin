-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         config.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-05
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Central configuration for all Cozy Home settings.
--       All constants, defaults, tile definitions, and
--       tunable values live here.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       (none — standalone config module)
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--   local version = Config.PLUGIN.version
-- ============================================

local Config = {}

-- ============================================
-- PLUGIN INFO
-- ============================================

Config.PLUGIN = {
    name = "cozyhome",
    version = "0.12.0",
    human_name = "Cozy Home",
    description = "A clean, customizable welcome screen for KOReader.",
}

-- ============================================
-- TILE DEFINITIONS
-- ============================================
-- Each tile on the home screen is defined here.
-- Order determines default display order.
-- icon_text is a simple text label used when no icon image is available.

Config.TILES = {
    {
        key = "books",
        label = "Books",
        icon_text = "[=]",
        enabled = true,
        description = "Browse your book library",
    },
    {
        key = "highlights",
        label = "Highlights",
        icon_text = "≡\"",
        enabled = true,
        description = "Browse your book highlights",
    },
    {
        key = "notebooks",
        label = "Notebooks",
        icon_text = "//_",
        enabled = true,
        description = "Create and manage stylus notebooks",
    },
    {
        key = "learnspace",
        label = "Learn Space",
        icon_text = "{+}",
        enabled = true,
        description = "Organize books and cards by subject",
    },
    {
        key = "notecards",
        label = "Notecards",
        icon_text = "[?]",
        enabled = true,
        description = "Browse and review flashcards",
    },
    {
        key = "focus",
        label = "Focus",
        icon_text = "(◉)",
        enabled = true,
        description = "Pomodoro focus timer with XP and streaks",
    },
    {
        key = "settings",
        label = "Settings",
        icon_text = ":::",
        enabled = true,
        description = "Configure Cozy Home and plugins",
    },

}

-- ============================================
-- UI LAYOUT
-- ============================================

Config.UI = {
    -- Grid layout for tiles
    tile_columns = 3,
    tile_rows = 2,

    -- Tile sizing (as fraction of screen width)
    tile_width_fraction = 0.28,
    tile_height_fraction = 0.14,
    tile_margin = 8,

    -- Continue Reading card height (fraction of screen height)
    continue_card_height_fraction = 0.18,

    -- Status bar height
    statusbar_height = 30,

    -- Stats bar at bottom
    show_stats_bar = true,
    stats_bar_height = 25,

    -- General spacing
    section_padding = 12,
    content_padding = 15,

    -- Font sizes
    font_size_title = 24,
    font_size_tile_label = 18,
    font_size_tile_icon = 28,
    font_size_status = 14,
    font_size_continue_title = 18,
    font_size_continue_detail = 14,
    font_size_stats = 12,

    -- Message timeout (seconds)
    message_timeout = 3,

    -- Animations (false for e-ink)
    animations_enabled = false,

    -- Standardized header bar
    header_height = 44,
    header_font_size = 20,
    header_btn_font_size = 14,
    header_padding = 15,
}

-- ============================================
-- SETTINGS KEYS
-- ============================================

Config.SETTINGS = {
    -- Key used to persist tile order in G_reader_settings
    last_tile_order_key = "cozyhome_tile_order",
}

-- ============================================
-- DATABASE SETTINGS
-- ============================================

Config.DATABASE = {
    filename = "cozyhome.db",
}

-- ============================================
-- FOCUS MODE / POMODORO SETTINGS
-- ============================================

Config.FOCUS = {
    work_duration = 25,
    short_break = 5,
    long_break = 15,
    sessions_before_long_break = 4,
}

-- ============================================
-- DEBUG SETTINGS
-- ============================================

Config.DEBUG = {
    verbose_logging = false,
    show_debug_menu = false,
}

return Config
