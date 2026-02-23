-- .luacheckrc — Luacheck config for Cozy Home
std = "lua51+luajit"
max_line_length = 200

-- KOReader globals we reference but don't define
read_globals = {
    "G_reader_settings",
}

-- Patterns that are unavoidable in KOReader's widget/callback architecture
ignore = {
    "212",  -- unused argument (KOReader callbacks always receive self, args we don't need)
    "213",  -- unused loop variable (idiomatic Lua: for _, v in ipairs)
    "432",  -- shadowing upvalue 'self' (KOReader nested widget pattern)
    "611",  -- line contains only whitespace (cosmetic, low-value fix)
    "612",  -- line contains trailing whitespace (cosmetic, low-value fix)
}

-- Per-file overrides
files["spec/**/*_spec.lua"] = {
    std = "+busted",
}

files["spec/mocks/*.lua"] = {
    std = "+busted",
}

files["spec/helpers.lua"] = {
    std = "+busted",
}

-- ClassDetailScreen is used as a forward-declared global in learningspace.lua
files["learningspace.lua"] = {
    globals = {"ClassDetailScreen"},
}

-- picker_dialog forward reference in settings.lua
files["settings.lua"] = {
    globals = {"picker_dialog"},
}

-- SQL query strings have intentional trailing whitespace
files["lib/kobo.lua"] = {
    ignore = {"613"},
}

-- Exclude
exclude_files = {
    ".git/**",
    "data/**",

}
