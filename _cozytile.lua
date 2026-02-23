-- _cozytile.lua — Cozy Launcher manifest for Cozy Home
-- This file lets the Cozy Launcher discover and display this plugin
-- as a tile on the home screen. Remove this file to hide from launcher.

return {
    key = "cozyhome",
    label = "Cozy Home",
    icon_text = "🏠",
    description = "Dashboard with library, highlights, learning, and more",
    module = "home",
    sort_order = 10,
}
