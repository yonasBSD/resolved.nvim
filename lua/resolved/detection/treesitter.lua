local config = require("resolved.config")

---@class resolved.CommentNode
---@field text string Comment text content
---@field line integer 0-indexed line number
---@field col integer 0-indexed column
---@field end_line integer 0-indexed end line
---@field end_col integer 0-indexed end column

local M = {}

-- Cache for compiled queries per language
---@type table<string, vim.treesitter.Query>
local query_cache = {}

---Build a treesitter query for the given node types
---@param lang string
---@param node_types string[]
---@return vim.treesitter.Query|nil
local function build_query(lang, node_types)
  local cache_key = lang .. ":" .. table.concat(node_types, ",")
  if query_cache[cache_key] then
    return query_cache[cache_key]
  end

  local query_parts = {}
  for _, node_type in ipairs(node_types) do
    table.insert(query_parts, string.format("(%s) @comment", node_type))
  end

  local query_string = table.concat(query_parts, "\n")
  local ok, query = pcall(vim.treesitter.query.parse, lang, query_string)

  if ok and query then
    query_cache[cache_key] = query
    return query
  end

  return nil
end

---Get all comment nodes from a buffer
---@param bufnr integer
---@return resolved.CommentNode[]
function M.get_comments(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == "" then
    return {}
  end

  local ft_config = config.get_filetype(ft)
  if ft_config == false or not ft_config then
    return {}
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then
    return {}
  end

  local comments = {}
  local seen = {} -- Deduplicate overlapping nodes

  parser:for_each_tree(function(tree, ltree)
    local lang = ltree:lang()
    local query = build_query(lang, ft_config.node_types)
    if not query then
      return
    end

    local root = tree:root()
    for id, node in query:iter_captures(root, bufnr, 0, -1) do
      local name = query.captures[id]
      if name == "comment" then
        local start_row, start_col, end_row, end_col = node:range()
        local key = string.format("%d:%d:%d:%d", start_row, start_col, end_row, end_col)

        if not seen[key] then
          seen[key] = true
          local text = vim.treesitter.get_node_text(node, bufnr)
          table.insert(comments, {
            text = text,
            line = start_row,
            col = start_col,
            end_line = end_row,
            end_col = end_col,
          })
        end
      end
    end
  end)

  -- Sort by position
  table.sort(comments, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    return a.col < b.col
  end)

  return comments
end

---Clear the query cache (for testing or when config changes)
function M.clear_cache()
  query_cache = {}
end

return M
