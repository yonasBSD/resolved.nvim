local config = require("resolved.config")

local M = {}

---Get icon for a given type
---@param icon_type "stale"|"stale_sign"|"open"|"closed"
---@return string icon
---@return string highlight
function M.get(icon_type)
  local cfg = config.get()
  local icon = cfg.icons[icon_type] or "?"
  local hl = cfg.highlights[icon_type] or "Normal"
  return icon, hl
end

---Get stale icon and highlight
---@return string icon, string highlight
function M.stale()
  return M.get("stale")
end

---Get stale sign icon and highlight
---@return string icon, string highlight
function M.stale_sign()
  return M.get("stale_sign")
end

---Get open icon and highlight
---@return string icon, string highlight
function M.open()
  return M.get("open")
end

---Get closed icon and highlight
---@return string icon, string highlight
function M.closed()
  return M.get("closed")
end

return M
