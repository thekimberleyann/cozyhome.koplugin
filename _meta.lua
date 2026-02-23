-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +
--
--   ⊹  File:         _meta.lua
--   ⊹  Author:       Kimberley Gonzalez (thekimberleyann)
--   ⊹  Date:         2026-02-05
--   ⊹  Modified:     2026-02-09
--   ⊹  Project:      Cozy Home for KOReader
--
--   🎀 Description:
--       Plugin metadata for KOReader's plugin manager.
--       Provides name, description, and version without
--       loading the full plugin code.
--
--   🎀 License:      MIT
--
--   🎀 Dependencies:
--       (none)
--
-- + ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ +

local _ = require("gettext")

return {
    name = "cozyhome",
    fullname = _("Cozy Home"),
    description = _([[A clean, customizable dashboard for KOReader.

Access from the Tools menu. Features a tappable tile grid
with quick access to your books, highlights, learning spaces,
flashcards, and settings.

Version 0.12.0:
- Welcome screen with customizable tile grid
- Library browser (list, covers, gallery views)
- Full-screen highlights browser with search and filters
- Learning spaces for grouping study material
- Flashcards hub with deck management and review
- Highlight-to-flashcard creation (single and batch)
- Kobo native highlight integration]]),
    version = "0.12.0",
}
