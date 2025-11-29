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
      local url_line = comment.line
      local url_col = url_match.start_col

      -- Handle multi-line comments: calculate which line the URL is actually on
      if comment.text:find("\n") then
        -- Normalize line endings (CRLF -> LF) for consistent counting
        local normalized_text = comment.text:gsub("\r\n", "\n")
        local text_before_url = normalized_text:sub(1, url_match.start_col - 1)

        -- Count newlines before the URL
        local newlines_before = 0
        for _ in text_before_url:gmatch("\n") do
          newlines_before = newlines_before + 1
        end

        if newlines_before > 0 then
          url_line = comment.line + newlines_before

          -- Find the last newline position to calculate column offset
          local last_newline_pos = text_before_url:match("^.*\n()")
          if last_newline_pos then
            -- Column is relative to the last newline
            url_col = url_match.start_col - last_newline_pos + 1
          else
            -- No newline found (shouldn't happen if newlines_before > 0)
            url_col = url_match.start_col
          end
        end
      end

      table.insert(references, {
        url = url_match.url,
        owner = url_match.owner,
        repo = url_match.repo,
        type = url_match.type,
        number = url_match.number,
        line = url_line,
        col = url_col,
        end_col = url_col + #url_match.url,
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
