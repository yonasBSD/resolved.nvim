local treesitter = require("resolved.detection.treesitter")
local patterns = require("resolved.detection.patterns")
local config = require("resolved.config")

---@class resolved.Reference
---@field url string Full GitHub URL
---@field owner string Repository owner
---@field repo string Repository name
---@field type "issue"|"pr"
---@field number integer Issue/PR number
---@field line integer 1-indexed line number
---@field col integer 0-indexed column (start of URL)
---@field end_col integer 0-indexed column (end of URL, exclusive)
---@field comment_text string Full comment text containing the URL
---@field has_stale_keywords boolean Whether comment contains stale keywords

local M = {}

---Scan a buffer for GitHub issue/PR references in comments
---@param bufnr integer
---@return resolved.Reference[]
function M.scan(bufnr)
  local cfg = config.get()
  local comments = treesitter.get_comments(bufnr)
  local references = {}

  for _, comment in ipairs(comments) do
    local urls = patterns.extract_urls(comment.text)
    local has_keywords = patterns.has_stale_keywords(comment.text, cfg.stale_keywords)

    for _, url_match in ipairs(urls) do
      -- Calculate absolute line/col position
      -- For multi-line comments, we need to find which line the URL is on
      local url_line = comment.line
      local url_col = comment.col + url_match.start_col

      -- Handle multi-line comments: find actual line of URL
      local text_before_url = comment.text:sub(1, url_match.start_col)
      local newlines_before = select(2, text_before_url:gsub("\n", ""))
      if newlines_before > 0 then
        url_line = comment.line + newlines_before
        -- Find column on that line
        local last_newline = text_before_url:match(".*\n()")
        if last_newline then
          url_col = url_match.start_col - last_newline + 1
        end
      end

      local url_end_col = url_col + #url_match.url

      table.insert(references, {
        url = url_match.url,
        owner = url_match.owner,
        repo = url_match.repo,
        type = url_match.type,
        number = url_match.number,
        line = url_line + 1, -- Convert to 1-indexed
        col = url_col,
        end_col = url_end_col,
        comment_text = comment.text,
        has_stale_keywords = has_keywords,
      })
    end
  end

  return references
end

---Deduplicate references by URL (keep first occurrence)
---@param refs resolved.Reference[]
---@return resolved.Reference[]
function M.dedupe_by_url(refs)
  local seen = {}
  local result = {}

  for _, ref in ipairs(refs) do
    if not seen[ref.url] then
      seen[ref.url] = true
      table.insert(result, ref)
    end
  end

  return result
end

---Get unique URLs from references
---@param refs resolved.Reference[]
---@return string[]
function M.get_unique_urls(refs)
  local seen = {}
  local urls = {}

  for _, ref in ipairs(refs) do
    if not seen[ref.url] then
      seen[ref.url] = true
      table.insert(urls, ref.url)
    end
  end

  return urls
end

return M
