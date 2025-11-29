local Job = require("plenary.job")

---@class resolved.IssueState
---@field state "open"|"closed"|"merged"
---@field state_reason? string For closed issues: "completed", "not_planned", "reopened"
---@field title string
---@field labels string[]
---@field closed_at? string ISO timestamp when closed
---@field merged_at? string ISO timestamp when merged (PRs only)

local M = {}

---@type boolean|nil
local _auth_checked = nil
---@type string|nil
local _auth_error = nil

---Check if gh CLI is available and authenticated
---@return boolean ok
---@return string? error_message
function M.check_auth()
  -- Return cached result if already checked
  if _auth_checked ~= nil then
    return _auth_checked, _auth_error
  end

  -- Check if gh exists
  if vim.fn.executable("gh") ~= 1 then
    _auth_checked = false
    _auth_error = "gh CLI not found. Install from https://cli.github.com/"
    return _auth_checked, _auth_error
  end

  -- Check if authenticated (synchronous, only runs once at setup)
  local result = vim.fn.system("gh auth status 2>&1")
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    _auth_checked = false
    _auth_error = "gh CLI not authenticated. Run: gh auth login"
    return _auth_checked, _auth_error
  end

  _auth_checked = true
  _auth_error = nil
  return true, nil
end

---Reset auth check (for testing)
function M._reset_auth_check()
  _auth_checked = nil
  _auth_error = nil
end

---Build the jq filter for extracting issue/PR data
---@param type "issue"|"pr"
---@return string
local function build_jq_filter(type)
  if type == "pr" then
    return [[{
      state: .state,
      merged: .merged,
      merged_at: .merged_at,
      title: .title,
      labels: [.labels[].name],
      closed_at: .closed_at
    }]]
  else
    return [[{
      state: .state,
      state_reason: .state_reason,
      title: .title,
      labels: [.labels[].name],
      closed_at: .closed_at
    }]]
  end
end

---Fetch issue or PR state from GitHub
---@param owner string Repository owner
---@param repo string Repository name
---@param number integer Issue/PR number
---@param type "issue"|"pr"
---@param callback fun(err?: string, state?: resolved.IssueState)
function M.fetch(owner, repo, number, type, callback)
  local endpoint = type == "pr"
      and string.format("repos/%s/%s/pulls/%d", owner, repo, number)
    or string.format("repos/%s/%s/issues/%d", owner, repo, number)

  local jq_filter = build_jq_filter(type)

  Job:new({
    command = "gh",
    args = { "api", endpoint, "--jq", jq_filter },
    on_exit = function(j, return_code)
      vim.schedule(function()
        if return_code ~= 0 then
          local stderr = table.concat(j:stderr_result(), "\n")
          -- Handle common errors gracefully
          if stderr:match("404") or stderr:match("Not Found") then
            callback(string.format("Issue/PR not found: %s/%s#%d", owner, repo, number))
          elseif stderr:match("401") or stderr:match("403") then
            callback("GitHub API authentication error. Try: gh auth login")
          else
            callback("gh api error: " .. stderr)
          end
          return
        end

        local output = table.concat(j:result(), "")
        local ok, data = pcall(vim.json.decode, output)
        if not ok then
          callback("Failed to parse GitHub response: " .. output)
          return
        end

        -- Determine effective state
        local state = data.state
        if type == "pr" and data.merged then
          state = "merged"
        end

        ---@type resolved.IssueState
        local issue_state = {
          state = state,
          state_reason = data.state_reason,
          title = data.title or "",
          labels = data.labels or {},
          closed_at = data.closed_at,
          merged_at = data.merged_at,
        }

        callback(nil, issue_state)
      end)
    end,
  }):start()
end

---Fetch multiple issues/PRs (sequential for simplicity)
---@param refs {owner: string, repo: string, number: integer, type: "issue"|"pr", url: string}[]
---@param callback fun(results: table<string, {err?: string, state?: resolved.IssueState}>)
function M.fetch_batch(refs, callback)
  local results = {}
  local pending = #refs

  if pending == 0 then
    callback(results)
    return
  end

  for _, ref in ipairs(refs) do
    M.fetch(ref.owner, ref.repo, ref.number, ref.type, function(err, state)
      results[ref.url] = { err = err, state = state }
      pending = pending - 1
      if pending == 0 then
        callback(results)
      end
    end)
  end
end

return M
