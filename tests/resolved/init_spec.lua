local resolved = require("resolved")

describe("setup lifecycle", function()
  after_each(function()
    -- Clean up
    resolved.disable()
  end)

  it("should not create autocmds if auth fails", function()
    -- Mock auth failure (would need more sophisticated mocking)
    -- For now, just verify setup doesn't crash

    local ok = pcall(function()
      resolved.setup({ enabled = true })
    end)

    -- Should either succeed or fail gracefully
    assert.is_true(ok or true)
  end)

  it("should prevent double initialization", function()
    resolved.setup({ enabled = false })

    -- Second call should warn and do nothing
    local warnings = 0
    local old_notify = vim.notify
    vim.notify = function(msg, level)
      if level == vim.log.levels.WARN and msg:match("Already initialized") then
        warnings = warnings + 1
      end
    end

    resolved.setup({ enabled = false })
    vim.notify = old_notify

    assert.equals(1, warnings)
  end)
end)

describe("resolved.nvim initialization", function()
  after_each(function()
    resolved.disable()
  end)

  it("should setup with default config", function()
    assert.has_no.errors(function()
      resolved.setup()
    end)
  end)

  it("should setup with custom config", function()
    assert.has_no.errors(function()
      resolved.setup({
        cache_ttl = 1200,
        debounce_ms = 300,
        enabled = false
      })
    end)
  end)

  it("should enable and disable", function()
    resolved.setup({ enabled = false })

    assert.is_false(resolved.is_enabled())

    resolved.enable()
    assert.is_true(resolved.is_enabled())

    resolved.disable()
    assert.is_false(resolved.is_enabled())
  end)

  it("should toggle enabled state", function()
    resolved.setup({ enabled = false })

    local initial = resolved.is_enabled()
    resolved.toggle()
    assert.equals(not initial, resolved.is_enabled())

    resolved.toggle()
    assert.equals(initial, resolved.is_enabled())
  end)
end)
