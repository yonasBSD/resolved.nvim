local M = {}

local health = vim.health

function M.check()
  health.start("resolved.nvim")

  -- Check gh CLI installed
  local gh_path = vim.fn.exepath("gh")
  if gh_path == "" then
    health.error("gh CLI not found", {
      "Install GitHub CLI: https://cli.github.com/",
      "Or via package manager: brew install gh / apt install gh",
    })
    return
  end
  health.ok("gh CLI found: " .. gh_path)

  -- Check gh auth status
  local auth_result = vim.fn.system("gh auth status 2>&1")
  local auth_code = vim.v.shell_error
  if auth_code ~= 0 then
    health.error("gh CLI not authenticated", {
      "Run: gh auth login",
      "Output: " .. vim.trim(auth_result),
    })
  else
    health.ok("gh CLI authenticated")
  end

  -- Check treesitter
  local ts_ok = pcall(require, "nvim-treesitter")
  if ts_ok then
    health.ok("nvim-treesitter installed")
  else
    health.warn("nvim-treesitter not found", {
      "Install nvim-treesitter for better comment detection",
      "Fallback: basic pattern matching (less accurate)",
    })
  end

  -- Check optional icon providers
  local mini_ok = pcall(require, "mini.icons")
  local devicons_ok = pcall(require, "nvim-web-devicons")

  if mini_ok then
    health.ok("mini.icons available (set icon_provider = 'mini' to use)")
  end
  if devicons_ok then
    health.ok("nvim-web-devicons available (set icon_provider = 'devicons' to use)")
  end
  if not mini_ok and not devicons_ok then
    health.info("No icon provider found (using default icons)")
  end

  -- Check plugin state
  local resolved = require("resolved")
  if resolved._setup_done then
    health.ok("Plugin initialized")
    if resolved._enabled then
      health.ok("Plugin enabled")
    else
      health.info("Plugin disabled (run :ResolvedEnable to activate)")
    end
  else
    health.warn("Plugin not initialized", {
      "Call require('resolved').setup() in your config",
    })
  end
end

return M
