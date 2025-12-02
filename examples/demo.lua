-- Demo file for resolved.nvim
-- This shows how the plugin surfaces stale issue references

local M = {}

-- TODO: Remove this workaround when https://github.com/neovim/neovim/issues/21423 is fixed
-- The dict watcher crash has been fixed, this hack is no longer needed!
function M.safe_window_access()
  -- Defensive copy to avoid crash
  local buf = vim.api.nvim_win_get_buf(0)
  return buf
end

-- FIXME: Waiting for https://github.com/neovim/neovim/issues/36729 to be resolved
-- Empty hover responses should be handled upstream now
function M.handle_hover(result)
  if not result or result == "" then
    return nil
  end
  return result
end

-- WA: https://github.com/neovim/neovim/issues/23026
-- Semantic tokens range support was added
function M.get_semantic_tokens()
  -- Implementation here
end

-- Tracking: https://github.com/neovim/neovim/issues/36752
-- This is still open, exit_timeout isn't respected yet
function M.cleanup_lsp()
  vim.defer_fn(function()
    vim.lsp.stop_client(vim.lsp.get_clients())
  end, 1000)
end

-- See https://github.com/neovim/neovim/pull/36770 for the fix
function M.example_merged_pr()
  -- This PR was merged
end

return M
