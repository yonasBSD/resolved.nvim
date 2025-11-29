---@class resolved.FiletypeConfig
---@field node_types string[] Treesitter node types to search for URLs

---@class resolved.Config
---@field enabled boolean Initial enabled state
---@field cache_ttl integer Cache TTL in seconds
---@field debounce_ms integer Debounce delay in milliseconds
---@field stale_keywords string[] Keywords indicating acknowledged stale references
---@field filetypes table<string, resolved.FiletypeConfig|false> Per-filetype treesitter config
---@field icons table<string, string> Icons for display
---@field highlights table<string, string> Highlight groups

local M = {}

---@type resolved.Config
M.defaults = {
  enabled = true,
  cache_ttl = 300, -- 5 minutes
  debounce_ms = 500,
  stale_keywords = {
    "TODO",
    "FIXME",
    "HACK",
    "XXX",
    "WA",
    "workaround",
    "temporary",
    "temp",
    "WIP",
    "blocked",
    "waiting",
    "upstream",
  },
  filetypes = {
    lua = { node_types = { "comment" } },
    python = { node_types = { "comment", "string" } },
    go = { node_types = { "comment" } },
    javascript = { node_types = { "comment" } },
    typescript = { node_types = { "comment" } },
    typescriptreact = { node_types = { "comment" } },
    javascriptreact = { node_types = { "comment" } },
    rust = { node_types = { "line_comment", "block_comment" } },
    nix = { node_types = { "comment" } },
    c = { node_types = { "comment" } },
    cpp = { node_types = { "comment" } },
    java = { node_types = { "comment", "line_comment", "block_comment" } },
    ruby = { node_types = { "comment" } },
    sh = { node_types = { "comment" } },
    bash = { node_types = { "comment" } },
    zsh = { node_types = { "comment" } },
    yaml = { node_types = { "comment" } },
    toml = { node_types = { "comment" } },
    ["*"] = { node_types = { "comment" } },
  },
  icons = {
    stale = "⚠",
    stale_sign = "⚠",
    open = "",
  },
  highlights = {
    -- High priority: closed + keywords (warning/yellow)
    stale = "DiagnosticWarn",
    stale_sign = "DiagnosticWarn",
    stale_url = "ResolvedStaleUrl",
    -- Low priority: closed, no keywords (hint/blue-ish)
    closed = "DiagnosticHint",
    closed_url = "ResolvedClosedUrl",
    -- Open issues (green/ok)
    open = "DiagnosticOk",
  },
  -- Show sign column indicators
  signs = true,
  -- Icon provider: "mini" (mini.icons), "devicons" (nvim-web-devicons), or false for defaults
  icon_provider = false,
}

---@type resolved.Config
M.current = vim.deepcopy(M.defaults)

---Merge user config with defaults
---@param user_config? resolved.Config
function M.setup(user_config)
  M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_config or {})
end

---Get current config
---@return resolved.Config
function M.get()
  return M.current
end

---Get filetype config, falling back to wildcard
---@param ft string
---@return resolved.FiletypeConfig|false|nil
function M.get_filetype(ft)
  local cfg = M.current.filetypes[ft]
  if cfg ~= nil then
    return cfg
  end
  return M.current.filetypes["*"]
end

return M
