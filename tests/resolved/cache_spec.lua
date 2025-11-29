local cache_mod = require("resolved.cache")

describe("cache", function()
  local cache

  before_each(function()
    cache = cache_mod.new(1) -- 1 second TTL for tests
  end)

  it("stores and retrieves values", function()
    cache:set("key", "value")
    assert.equals("value", cache:get("key"))
  end)

  it("returns nil for missing keys", function()
    assert.is_nil(cache:get("nonexistent"))
  end)

  it("checks existence with has()", function()
    cache:set("key", "value")
    assert.is_true(cache:has("key"))
    assert.is_false(cache:has("other"))
  end)

  it("removes keys", function()
    cache:set("key", "value")
    cache:remove("key")
    assert.is_nil(cache:get("key"))
  end)

  it("clears all entries", function()
    cache:set("a", 1)
    cache:set("b", 2)
    cache:clear()
    assert.is_nil(cache:get("a"))
    assert.is_nil(cache:get("b"))
  end)

  it("counts entries", function()
    cache:set("a", 1)
    cache:set("b", 2)
    assert.equals(2, cache:size())
  end)

  it("expires entries after TTL", function()
    cache:set("key", "value")
    -- Wait for TTL to expire
    vim.wait(1100, function()
      return false
    end)
    assert.is_nil(cache:get("key"))
  end)
end)
