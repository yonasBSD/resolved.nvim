local patterns = require("resolved.detection.patterns")

describe("patterns", function()
  describe("extract_urls", function()
    it("extracts GitHub issue URLs", function()
      local text = "See https://github.com/NixOS/nixpkgs/issues/462025 for details"
      local matches = patterns.extract_urls(text)

      assert.equals(1, #matches)
      assert.equals("https://github.com/NixOS/nixpkgs/issues/462025", matches[1].url)
      assert.equals("NixOS", matches[1].owner)
      assert.equals("nixpkgs", matches[1].repo)
      assert.equals(462025, matches[1].number)
      assert.equals("issue", matches[1].type)
    end)

    it("extracts GitHub PR URLs", function()
      local text = "Fixed in https://github.com/neovim/neovim/pull/12345"
      local matches = patterns.extract_urls(text)

      assert.equals(1, #matches)
      assert.equals("pr", matches[1].type)
      assert.equals(12345, matches[1].number)
    end)

    it("extracts multiple URLs", function()
      local text = "See #1 https://github.com/a/b/issues/1 and https://github.com/c/d/pull/2"
      local matches = patterns.extract_urls(text)

      assert.equals(2, #matches)
      assert.equals("issue", matches[1].type)
      assert.equals("pr", matches[2].type)
    end)

    it("handles repos with dots and hyphens", function()
      local text = "https://github.com/nvim-lua/plenary.nvim/issues/123"
      local matches = patterns.extract_urls(text)

      assert.equals(1, #matches)
      assert.equals("nvim-lua", matches[1].owner)
      assert.equals("plenary.nvim", matches[1].repo)
    end)

    it("returns empty for no matches", function()
      local text = "No URLs here"
      local matches = patterns.extract_urls(text)

      assert.equals(0, #matches)
    end)
  end)

  describe("has_stale_keywords", function()
    local keywords = { "TODO", "FIXME", "workaround" }

    it("detects TODO", function()
      assert.is_true(patterns.has_stale_keywords("TODO: fix this", keywords))
    end)

    it("detects case-insensitive", function()
      assert.is_true(patterns.has_stale_keywords("Workaround for bug", keywords))
    end)

    it("returns false when no keywords", function()
      assert.is_false(patterns.has_stale_keywords("See issue #123", keywords))
    end)
  end)
end)
