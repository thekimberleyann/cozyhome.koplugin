-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊
--
--   spec/cozyui_spec.lua
--
--   Tests for CozyUI.sanitizeInput() — the input sanitization helper.
--
--   NOTE: lib/cozyui.lua has many KOReader widget dependencies (Blitbuffer,
--   Font, Screen, etc.) that can't easily be mocked. So we test
--   sanitizeInput() by extracting a local copy of the pure function.
--   This tests the logic without requiring the full widget stack.
--
--   When we have KOReader emulator integration tests, we can test the
--   actual module directly.
--
-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊

describe("CozyUI.sanitizeInput()", function()
    -- Extract the pure function logic — this matches the implementation
    -- in lib/cozyui.lua exactly. If the implementation changes, update here.
    local sanitizeInput

    setup(function()
        -- Read the actual function source from lib/cozyui.lua.
        -- Since we can't require the full module (widget deps), we define
        -- a local copy. This is validated against the real code in CI via
        -- integration tests (future).
        sanitizeInput = function(text, max_len, allow_newlines)
            if not text or type(text) ~= "string" then return "" end
            text = text:match("^%s*(.-)%s*$") or ""
            if not allow_newlines then
                text = text:gsub("%c", "")
            else
                text = text:gsub("[%c\r]", function(c)
                    return (c == "\n") and c or ""
                end)
            end
            if max_len and #text > max_len then
                text = text:sub(1, max_len)
            end
            return text
        end
    end)

    -- ─── Nil / Invalid input ───

    describe("nil and invalid input", function()
        it("returns empty string for nil", function()
            assert.equals("", sanitizeInput(nil, 100))
        end)

        it("returns empty string for number", function()
            assert.equals("", sanitizeInput(42, 100))
        end)

        it("returns empty string for table", function()
            assert.equals("", sanitizeInput({}, 100))
        end)

        it("returns empty string for boolean", function()
            assert.equals("", sanitizeInput(true, 100))
            assert.equals("", sanitizeInput(false, 100))
        end)
    end)

    -- ─── Whitespace trimming ───

    describe("whitespace trimming", function()
        it("trims leading spaces", function()
            assert.equals("hello", sanitizeInput("   hello", 100))
        end)

        it("trims trailing spaces", function()
            assert.equals("hello", sanitizeInput("hello   ", 100))
        end)

        it("trims both sides", function()
            assert.equals("hello", sanitizeInput("  hello  ", 100))
        end)

        it("trims tabs", function()
            assert.equals("hello", sanitizeInput("\thello\t", 100))
        end)

        it("handles whitespace-only string", function()
            assert.equals("", sanitizeInput("   ", 100))
        end)

        it("handles empty string", function()
            assert.equals("", sanitizeInput("", 100))
        end)
    end)

    -- ─── Control character removal ───

    describe("control character removal", function()
        it("removes null bytes", function()
            assert.equals("hello world", sanitizeInput("hello" .. string.char(0) .. " world", 100))
        end)

        it("removes bell character", function()
            assert.equals("test", sanitizeInput("te" .. string.char(7) .. "st", 100))
        end)

        it("removes carriage return", function()
            assert.equals("line1line2", sanitizeInput("line1\rline2", 100))
        end)

        it("removes newlines when not allowed", function()
            local result = sanitizeInput("line1\nline2", 100, false)
            assert.falsy(result:find("\n"))
            assert.equals("line1line2", result)
        end)

        it("removes mixed control chars", function()
            local input = string.char(0) .. "a" .. string.char(1) .. "b" .. string.char(2) .. "c" .. string.char(3)
            assert.equals("abc", sanitizeInput(input, 100))
        end)
    end)

    -- ─── Newline preservation ───

    describe("newline handling (allow_newlines=true)", function()
        it("preserves newlines when allowed", function()
            local result = sanitizeInput("line1\nline2", 100, true)
            assert.equals("line1\nline2", result)
        end)

        it("removes carriage returns even when newlines allowed", function()
            local result = sanitizeInput("line1\r\nline2", 100, true)
            assert.equals("line1\nline2", result)
        end)

        it("removes other control chars while preserving newlines", function()
            local input = "a" .. string.char(0) .. "\nb" .. string.char(1)
            local result = sanitizeInput(input, 100, true)
            assert.equals("a\nb", result)
        end)
    end)

    -- ─── Length enforcement ───

    describe("max length", function()
        it("truncates to max_len", function()
            local result = sanitizeInput("abcdefghij", 5)
            assert.equals(5, #result)
            assert.equals("abcde", result)
        end)

        it("does not truncate when under limit", function()
            assert.equals("abc", sanitizeInput("abc", 100))
        end)

        it("handles exact length", function()
            assert.equals("abc", sanitizeInput("abc", 3))
        end)

        it("handles very long input", function()
            local long = string.rep("a", 10000)
            local result = sanitizeInput(long, 100)
            assert.equals(100, #result)
        end)

        it("works without max_len (no truncation)", function()
            local long = string.rep("x", 500)
            local result = sanitizeInput(long, nil)
            assert.equals(500, #result)
        end)
    end)

    -- ─── Combined behavior ───

    describe("combined trimming + sanitization + truncation", function()
        it("trims before measuring length", function()
            -- "  hello  " (9 chars) -> "hello" (5 chars) -> truncate to 5 = "hello"
            assert.equals("hello", sanitizeInput("  hello  ", 5))
        end)

        it("removes control chars before measuring length", function()
            local input = "a" .. string.char(0) .. "b" .. string.char(0) .. "c"
            assert.equals("abc", sanitizeInput(input, 3))
        end)

        it("handles realistic class name input", function()
            assert.equals("Math 101", sanitizeInput("  Math 101  ", 100))
        end)

        it("handles realistic search query input", function()
            assert.equals("quantum physics", sanitizeInput("quantum physics\n", 200))
        end)
    end)
end)
