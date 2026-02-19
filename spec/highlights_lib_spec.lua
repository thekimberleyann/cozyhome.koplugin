-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊
--
--   spec/highlights_lib_spec.lua
--
--   Tests for lib/highlights.lua — highlight reading, caching,
--   search, chapter grouping, and sorting.
--
--   Uses mock_koreader to fake DocSettings so we can test the
--   actual module without KOReader runtime.
--
-- ₊ ⊹ 🎀 ⋆ 🌙 ⋆ ☆ ⋆ ☀️ ⋆ 🎀 ⊹ ₊

local mock_koreader = require("spec.mocks.mock_koreader")
local helpers = require("spec.helpers")

describe("lib/highlights.lua", function()
    local Highlights
    local DocSettingsMock

    setup(function()
        mock_koreader.setup()
        DocSettingsMock = mock_koreader.getDocSettingsMock()
        Highlights = require("lib/highlights")
    end)

    teardown(function()
        mock_koreader.teardown()
    end)

    before_each(function()
        -- Fresh state for every test
        Highlights.clearFullCache()
        DocSettingsMock._mock_data = {}
    end)

    -- ════════════════════════════════════════════
    -- getHighlights()
    -- ════════════════════════════════════════════

    describe("getHighlights()", function()

        it("returns empty table for nil path", function()
            assert.same({}, Highlights.getHighlights(nil))
        end)

        it("returns empty table when no data exists", function()
            DocSettingsMock._mock_data["/books/empty.epub"] = {}
            local result = Highlights.getHighlights("/books/empty.epub")
            assert.same({}, result)
        end)

        it("returns empty table when annotations is empty", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                annotations = {},
            }
            assert.same({}, Highlights.getHighlights("/books/test.epub"))
        end)

        it("reads annotations from sidecar data", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                annotations = {
                    { text = "First highlight", chapter = "Ch 1", pageno = 5 },
                    { text = "Second highlight", chapter = "Ch 2", pageno = 12 },
                },
            }
            local result = Highlights.getHighlights("/books/test.epub")
            assert.equals(2, #result)
            assert.equals("First highlight", result[1].text)
            assert.equals("Second highlight", result[2].text)
        end)

        it("preserves all annotation fields", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                annotations = {
                    {
                        text = "Highlight text",
                        note = "My note",
                        chapter = "Chapter 3",
                        pageno = 42,
                        datetime = "2026-01-15",
                        drawer = "lighten",
                    },
                },
            }
            local result = Highlights.getHighlights("/books/test.epub")
            assert.equals(1, #result)
            assert.equals("Highlight text", result[1].text)
            assert.equals("My note", result[1].note)
            assert.equals("Chapter 3", result[1].chapter)
            assert.equals(42, result[1].pageno)
            assert.equals("2026-01-15", result[1].datetime)
            assert.equals("lighten", result[1].drawer)
        end)

        it("skips annotations with empty text", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                annotations = {
                    { text = "Valid", chapter = "Ch 1" },
                    { text = "", chapter = "Ch 2" },
                    { text = nil, chapter = "Ch 3" },
                },
            }
            local result = Highlights.getHighlights("/books/test.epub")
            assert.equals(1, #result)
            assert.equals("Valid", result[1].text)
        end)

        it("falls back to bookmarks if no annotations", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                bookmarks = {
                    { notes = "Bookmark highlight", page = 3, datetime = "2026-01-01" },
                },
            }
            local result = Highlights.getHighlights("/books/test.epub")
            assert.equals(1, #result)
            assert.equals("Bookmark highlight", result[1].text)
        end)

        it("prefers annotations over bookmarks when both exist", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                annotations = {
                    { text = "From annotations", chapter = "Ch 1" },
                },
                bookmarks = {
                    { notes = "From bookmarks", page = 1 },
                },
            }
            local result = Highlights.getHighlights("/books/test.epub")
            assert.equals(1, #result)
            assert.equals("From annotations", result[1].text)
        end)

        it("handles many annotations", function()
            local data = helpers.make_annotations(50)
            DocSettingsMock._mock_data["/books/big.epub"] = data
            local result = Highlights.getHighlights("/books/big.epub")
            assert.equals(50, #result)
        end)
    end)

    -- ════════════════════════════════════════════
    -- getHighlightCount() / hasHighlights()
    -- ════════════════════════════════════════════

    describe("getHighlightCount()", function()
        it("returns 0 for nil path", function()
            assert.equals(0, Highlights.getHighlightCount(nil))
        end)

        it("returns 0 for book with no highlights", function()
            DocSettingsMock._mock_data["/books/empty.epub"] = {}
            assert.equals(0, Highlights.getHighlightCount("/books/empty.epub"))
        end)

        it("returns correct count", function()
            DocSettingsMock._mock_data["/books/test.epub"] = helpers.make_annotations(7)
            assert.equals(7, Highlights.getHighlightCount("/books/test.epub"))
        end)
    end)

    describe("hasHighlights()", function()
        it("returns false for book with no highlights", function()
            DocSettingsMock._mock_data["/books/empty.epub"] = {}
            assert.is_false(Highlights.hasHighlights("/books/empty.epub"))
        end)

        it("returns true for book with highlights", function()
            DocSettingsMock._mock_data["/books/test.epub"] = helpers.make_annotations(1)
            assert.is_true(Highlights.hasHighlights("/books/test.epub"))
        end)
    end)

    -- ════════════════════════════════════════════
    -- Cache behavior
    -- ════════════════════════════════════════════

    describe("cache behavior", function()

        it("caches results after first read", function()
            DocSettingsMock._mock_data["/books/a.epub"] = helpers.make_annotations(1)
            Highlights.getHighlights("/books/a.epub")
            assert.is_true(Highlights.isCached("/books/a.epub"))
        end)

        it("is not cached before first read", function()
            assert.is_false(Highlights.isCached("/books/never-read.epub"))
        end)

        it("returns cached data on second call (ignores underlying changes)", function()
            DocSettingsMock._mock_data["/books/a.epub"] = {
                annotations = {{ text = "original" }},
            }
            Highlights.getHighlights("/books/a.epub")

            -- Simulate underlying data change
            DocSettingsMock._mock_data["/books/a.epub"] = {
                annotations = {{ text = "changed" }},
            }
            local result = Highlights.getHighlights("/books/a.epub")
            assert.equals("original", result[1].text)
        end)

        it("caches empty results too", function()
            DocSettingsMock._mock_data["/books/empty.epub"] = {}
            Highlights.getHighlights("/books/empty.epub")
            assert.is_true(Highlights.isCached("/books/empty.epub"))
        end)

        -- ─── invalidateCache ───

        describe("invalidateCache()", function()
            it("clears one book when path given", function()
                DocSettingsMock._mock_data["/books/a.epub"] = helpers.make_annotations(1)
                DocSettingsMock._mock_data["/books/b.epub"] = helpers.make_annotations(1)
                Highlights.getHighlights("/books/a.epub")
                Highlights.getHighlights("/books/b.epub")

                Highlights.invalidateCache("/books/a.epub")
                assert.is_false(Highlights.isCached("/books/a.epub"))
                assert.is_true(Highlights.isCached("/books/b.epub"))
            end)

            it("clears all when path is nil", function()
                DocSettingsMock._mock_data["/books/a.epub"] = helpers.make_annotations(1)
                DocSettingsMock._mock_data["/books/b.epub"] = helpers.make_annotations(1)
                Highlights.getHighlights("/books/a.epub")
                Highlights.getHighlights("/books/b.epub")

                Highlights.invalidateCache(nil)
                assert.is_false(Highlights.isCached("/books/a.epub"))
                assert.is_false(Highlights.isCached("/books/b.epub"))
            end)

            it("is a no-op for uncached path", function()
                -- Should not error
                Highlights.invalidateCache("/books/never-cached.epub")
                assert.is_false(Highlights.isCached("/books/never-cached.epub"))
            end)

            it("allows fresh read after invalidation", function()
                DocSettingsMock._mock_data["/books/a.epub"] = {
                    annotations = {{ text = "v1" }},
                }
                Highlights.getHighlights("/books/a.epub")

                -- Update data and invalidate
                DocSettingsMock._mock_data["/books/a.epub"] = {
                    annotations = {{ text = "v2" }},
                }
                Highlights.invalidateCache("/books/a.epub")

                local result = Highlights.getHighlights("/books/a.epub")
                assert.equals("v2", result[1].text)
            end)
        end)

        -- ─── clearFullCache ───

        describe("clearFullCache()", function()
            it("clears all cached entries", function()
                DocSettingsMock._mock_data["/books/a.epub"] = helpers.make_annotations(1)
                DocSettingsMock._mock_data["/books/b.epub"] = helpers.make_annotations(1)
                DocSettingsMock._mock_data["/books/c.epub"] = helpers.make_annotations(1)
                Highlights.getHighlights("/books/a.epub")
                Highlights.getHighlights("/books/b.epub")
                Highlights.getHighlights("/books/c.epub")

                Highlights.clearFullCache()
                assert.is_false(Highlights.isCached("/books/a.epub"))
                assert.is_false(Highlights.isCached("/books/b.epub"))
                assert.is_false(Highlights.isCached("/books/c.epub"))
            end)

            it("is safe to call on empty cache", function()
                Highlights.clearFullCache()  -- should not error
            end)
        end)
    end)

    -- ════════════════════════════════════════════
    -- searchHighlights()
    -- ════════════════════════════════════════════

    describe("searchHighlights()", function()
        before_each(function()
            DocSettingsMock._mock_data["/books/search.epub"] = {
                annotations = {
                    { text = "The quick brown fox", chapter = "Ch 1" },
                    { text = "jumps over the lazy dog", note = "famous pangram", chapter = "Ch 2" },
                    { text = "Hello world", chapter = "Ch 3" },
                    { text = "Another highlight about foxes", chapter = "Ch 4" },
                },
            }
        end)

        it("finds matches in text (case insensitive)", function()
            local results = Highlights.searchHighlights("/books/search.epub", "QUICK")
            assert.equals(1, #results)
            assert.equals("The quick brown fox", results[1].text)
        end)

        it("finds matches in notes", function()
            local results = Highlights.searchHighlights("/books/search.epub", "pangram")
            assert.equals(1, #results)
            assert.equals("jumps over the lazy dog", results[1].text)
        end)

        it("finds multiple matches", function()
            local results = Highlights.searchHighlights("/books/search.epub", "fox")
            assert.equals(2, #results)
        end)

        it("returns empty for no match", function()
            local results = Highlights.searchHighlights("/books/search.epub", "xyz123")
            assert.equals(0, #results)
        end)

        it("returns empty for nil query", function()
            assert.same({}, Highlights.searchHighlights("/books/search.epub", nil))
        end)

        it("returns empty for empty query", function()
            assert.same({}, Highlights.searchHighlights("/books/search.epub", ""))
        end)

        it("returns empty for nil path", function()
            assert.same({}, Highlights.searchHighlights(nil, "test"))
        end)

        it("does plain text matching (not patterns)", function()
            -- Lua patterns use characters like . and % — make sure search
            -- does plain matching, not pattern matching
            DocSettingsMock._mock_data["/books/pattern.epub"] = {
                annotations = {
                    { text = "result: 3.14 (approx)" },
                },
            }
            Highlights.clearFullCache()
            local results = Highlights.searchHighlights("/books/pattern.epub", "3.14")
            assert.equals(1, #results)
        end)
    end)

    -- ════════════════════════════════════════════
    -- getHighlightsByChapter()
    -- ════════════════════════════════════════════

    describe("getHighlightsByChapter()", function()

        it("groups highlights by chapter", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                annotations = {
                    { text = "hl1", chapter = "Ch 1" },
                    { text = "hl2", chapter = "Ch 1" },
                    { text = "hl3", chapter = "Ch 2" },
                },
            }
            local by_ch = Highlights.getHighlightsByChapter("/books/test.epub")
            assert.is_not_nil(by_ch["Ch 1"])
            assert.equals(2, #by_ch["Ch 1"])
            assert.is_not_nil(by_ch["Ch 2"])
            assert.equals(1, #by_ch["Ch 2"])
        end)

        it("uses 'Unknown Chapter' for nil chapter", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                annotations = {
                    { text = "no chapter" },
                },
            }
            local by_ch = Highlights.getHighlightsByChapter("/books/test.epub")
            assert.is_not_nil(by_ch["Unknown Chapter"])
            assert.equals(1, #by_ch["Unknown Chapter"])
        end)

        it("returns empty table for book with no highlights", function()
            DocSettingsMock._mock_data["/books/empty.epub"] = {}
            local by_ch = Highlights.getHighlightsByChapter("/books/empty.epub")
            -- Should be an empty table (no keys)
            local count = 0
            for _ in pairs(by_ch) do count = count + 1 end
            assert.equals(0, count)
        end)

        it("handles many chapters", function()
            local data = helpers.make_annotations(30)
            DocSettingsMock._mock_data["/books/big.epub"] = data
            local by_ch = Highlights.getHighlightsByChapter("/books/big.epub")
            -- helpers.make_annotations assigns chapter = "Chapter " .. ceil(i/3)
            -- 30 highlights / 3 per chapter = 10 chapters
            local chapter_count = 0
            for _ in pairs(by_ch) do chapter_count = chapter_count + 1 end
            assert.equals(10, chapter_count)
        end)
    end)

    -- ════════════════════════════════════════════
    -- getHighlightsSorted()
    -- ════════════════════════════════════════════

    describe("getHighlightsSorted()", function()

        it("sorts by page number ascending", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                annotations = {
                    { text = "hl1", pageno = 50 },
                    { text = "hl2", pageno = 10 },
                    { text = "hl3", pageno = 30 },
                },
            }
            local sorted = Highlights.getHighlightsSorted("/books/test.epub")
            assert.equals(3, #sorted)
            assert.equals(10, sorted[1].pageno)
            assert.equals(30, sorted[2].pageno)
            assert.equals(50, sorted[3].pageno)
        end)

        it("handles nil pageno (treats as 0)", function()
            DocSettingsMock._mock_data["/books/test.epub"] = {
                annotations = {
                    { text = "with page", pageno = 20 },
                    { text = "no page" },  -- pageno = nil
                },
            }
            local sorted = Highlights.getHighlightsSorted("/books/test.epub")
            assert.equals(2, #sorted)
            -- nil pageno -> 0, so it comes first
            assert.equals("no page", sorted[1].text)
            assert.equals("with page", sorted[2].text)
        end)

        it("returns empty for book with no highlights", function()
            DocSettingsMock._mock_data["/books/empty.epub"] = {}
            local sorted = Highlights.getHighlightsSorted("/books/empty.epub")
            assert.same({}, sorted)
        end)
    end)

    -- ════════════════════════════════════════════
    -- getBookHighlights() alias
    -- ════════════════════════════════════════════

    describe("getBookHighlights()", function()
        it("is an alias for getHighlights()", function()
            assert.equals(Highlights.getHighlights, Highlights.getBookHighlights)
        end)
    end)
end)
