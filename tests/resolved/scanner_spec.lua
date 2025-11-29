local scanner = require("resolved.scanner")

describe("multi-line comment position calculation", function()
  it("should handle Unix line endings (LF)", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "c")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "/*",
      " * See: https://github.com/owner/repo/issues/123",
      " */"
    })

    local results = scanner.scan(bufnr)

    assert.equals(1, #results)
    assert.equals(2, results[1].line)
    assert.equals(8, results[1].col)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("should handle Windows line endings (CRLF)", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "c")
    -- Simulate CRLF by setting fileformat
    vim.api.nvim_buf_set_option(bufnr, "fileformat", "dos")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "/*",
      " * See: https://github.com/owner/repo/issues/123",
      " */"
    })

    local results = scanner.scan(bufnr)

    assert.equals(1, #results)
    assert.equals(2, results[1].line)
    -- Column should be correct regardless of line ending

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("should handle URL at exact line boundary", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "c")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "/* https://github.com/owner/repo/issues/123",
      "   more text */"
    })

    local results = scanner.scan(bufnr)

    assert.equals(1, #results)
    assert.equals(1, results[1].line)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("should handle multiple URLs in multi-line comment", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "c")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "/*",
      " * https://github.com/owner/repo/issues/123",
      " * https://github.com/owner/repo/issues/456",
      " */"
    })

    local results = scanner.scan(bufnr)

    assert.equals(2, #results)
    assert.equals(2, results[1].line)
    assert.equals(3, results[2].line)

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
