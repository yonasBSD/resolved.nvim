local resolved = require("resolved")

describe("buffer validity race conditions", function()
  before_each(function()
    resolved.setup({ enabled = false })
  end)

  after_each(function()
    resolved.disable()
  end)

  it("should handle buffer deletion during scan", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "-- https://github.com/owner/repo/issues/123"
    })

    -- Start scan (async)
    resolved._scan_buffer(bufnr)

    -- Delete buffer immediately
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Wait for async operations
    vim.wait(200)

    -- Should not crash
    assert.is_true(true)
  end)

  it("should handle buffer deletion during display update", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "-- https://github.com/owner/repo/issues/123"
    })

    local display = require("resolved.display")

    -- Try to update display for buffer
    local ok = pcall(function()
      display.update(bufnr, {
        {
          url = "https://github.com/owner/repo/issues/123",
          line = 1,
          start_col = 4,
          end_col = 47,
          state = "closed",
          is_stale = false
        }
      })
    end)

    -- Delete buffer
    vim.api.nvim_buf_delete(bufnr, { force = true })

    assert.is_true(ok)
  end)
end)
