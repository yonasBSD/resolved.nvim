local config = require("resolved.config")

local M = {}

-- Icon names to request from providers
local ICON_NAMES = {
  stale = "warning", -- or "issue-closed", "alert"
  open = "issue-opened",
}

---@return string icon, string? highlight
local function get_mini_icon(name)
  local ok, mini_icons = pcall(require, "mini.icons")
  if not ok then
    return nil, nil
  end

  -- mini.icons uses get() with category and name
  -- Try "lsp" category for warning/error icons
  local icon, hl = mini_icons.get("lsp", name)
  if icon then
    return icon, hl
  end

  -- Fallback to default category
  icon, hl = mini_icons.get("default", name)
  return icon, hl
end

---@return string icon, string? highlight
local function get_devicons_icon(name)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if not ok then
    return nil, nil
  end

  -- nvim-web-devicons doesn't have semantic icons like "warning"
  -- It's mainly for filetypes, so we return nil
  return nil, nil
end

---Get icon for a given type
---@param icon_type "stale"|"open"
---@return string icon
---@return string highlight
function M.get(icon_type)
  local cfg = config.get()
  local provider = cfg.icon_provider

  -- Default icons from config
  local default_icon = cfg.icons[icon_type] or "?"
  local default_hl = cfg.highlights[icon_type] or "Normal"

  if not provider then
    return default_icon, default_hl
  end

  local icon_name = ICON_NAMES[icon_type]
  local icon, hl

  if provider == "mini" then
    icon, hl = get_mini_icon(icon_name)
  elseif provider == "devicons" then
    icon, hl = get_devicons_icon(icon_name)
  end

  -- Use provider icon/hl if available, otherwise fall back to defaults
  return icon or default_icon, hl or default_hl
end

---Get stale icon and highlight
---@return string icon, string highlight
function M.stale()
  return M.get("stale")
end

---Get stale sign icon and highlight
---@return string icon, string highlight
function M.stale_sign()
  local cfg = config.get()
  local icon, hl = M.get("stale")
  -- Allow separate sign icon override
  if cfg.icons.stale_sign and cfg.icons.stale_sign ~= cfg.icons.stale then
    icon = cfg.icons.stale_sign
  end
  if cfg.highlights.stale_sign then
    hl = cfg.highlights.stale_sign
  end
  return icon, hl
end

---Get open icon and highlight
---@return string icon, string highlight
function M.open()
  return M.get("open")
end

return M
