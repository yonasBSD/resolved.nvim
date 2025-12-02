-- resolved.nvim - Surface stale issue/PR references in code comments
-- Lazy loading: This file sets up commands that load the plugin on demand

if vim.g.loaded_resolved then
  return
end
vim.g.loaded_resolved = true

-- Require Neovim 0.10+
if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("[resolved.nvim] Requires Neovim 0.10 or later", vim.log.levels.ERROR)
  return
end

-- Commands are set up in init.lua after setup() is called
-- This file just prevents double-loading
