local Job = require("plenary.job")

-- Constants
local MAX_FILE_SIZE_BYTES = 1024 * 1024 -- 1MB - skip files larger than this
local BATCH_SIZE = 20 -- Number of files to process in parallel per batch
local GIT_TIMEOUT_MS = 30000 -- 30 second timeout for git commands
local PROGRESS_THROTTLE_MS = 500 -- Update notifications at most every 500ms

---Notify helper for consistent error/info messages
---@param msg string
---@param level? integer vim.log.levels value
---@param opts? table Additional notification options
local function notify(msg, level, opts)
  opts = opts or {}
  vim.notify("[resolved.nvim] " .. msg, level or vim.log.levels.INFO, opts)
end

---@class resolved.FileReference : resolved.Reference
---@field file_path string Absolute path to file

---@class resolved.PickerIssue
---@field url string
---@field owner string
---@field repo string
---@field type "issue"|"pr"
---@field number integer
---@field title string
---@field state "open"|"closed"|"merged"|"unknown"
---@field locations resolved.FileReference[]
---@field is_stale boolean

local M = {}

---Get list of git-tracked files (async)
---@param callback fun(err: string?, files: string[]?)
local function get_tracked_files_async(callback)
  -- Check git executable
  if vim.fn.executable("git") ~= 1 then
    callback("git not found", nil)
    return
  end

  -- Validate and normalize cwd
  local cwd = vim.fn.getcwd()
  if vim.fn.isdirectory(cwd) ~= 1 then
    callback("Invalid working directory", nil)
    return
  end
  cwd = vim.fn.fnamemodify(cwd, ":p") -- Normalize to absolute path

  -- Use plenary.Job to run: git ls-files with timeout
  local job = Job:new({
    command = "git",
    args = { "ls-files" },
    cwd = cwd,
    on_exit = function(j, code, signal)
      vim.schedule(function()
        -- Check for timeout (signal 9 = SIGKILL from timeout)
        if signal == 9 then
          callback("Git command timed out", nil)
          return
        end

        if code ~= 0 then
          local err = table.concat(j:stderr_result(), "\n")
          callback("Not a git repository: " .. err, nil)
          return
        end

        local output = j:result()
        local files = {}

        for _, rel_path in ipairs(output) do
          if rel_path ~= "" then
            table.insert(files, vim.fn.fnamemodify(cwd .. "/" .. rel_path, ":p"))
          end
        end

        callback(nil, files)
      end)
    end,
  })

  job:start()

  -- Set up timeout
  vim.defer_fn(function()
    if job.handle and not job.handle:is_closing() then
      job:shutdown(1, 9) -- Send SIGKILL after 1ms grace period
    end
  end, GIT_TIMEOUT_MS)
end

---Scan a file for GitHub references (async, non-blocking)
---@param file_path string Absolute path to the file to scan
---@param callback fun(refs: resolved.FileReference[]) Callback with extracted references
local function scan_file_async(file_path, callback)
  local uv = vim.loop
  local fd = nil

  -- Cleanup helper to ensure fd is always closed
  local function cleanup()
    if fd then
      uv.fs_close(fd)
      fd = nil
    end
  end

  -- Safe callback that ensures cleanup
  local function safe_callback(refs)
    cleanup()
    vim.schedule(function()
      callback(refs)
    end)
  end

  -- Open file
  uv.fs_open(file_path, "r", 438, function(err_open, opened_fd)
    if err_open or not opened_fd then
      vim.schedule(function()
        callback({})
      end)
      return
    end

    fd = opened_fd

    -- Get file size
    uv.fs_fstat(fd, function(err_stat, stat)
      if err_stat or not stat then
        safe_callback({})
        return
      end

      -- Skip large files
      if stat.size > MAX_FILE_SIZE_BYTES then
        safe_callback({})
        return
      end

      -- Skip empty files
      if stat.size == 0 then
        safe_callback({})
        return
      end

      -- Read file content
      uv.fs_read(fd, stat.size, 0, function(err_read, data)
        if err_read or not data then
          safe_callback({})
          return
        end

        -- Close fd immediately after read
        cleanup()

        vim.schedule(function()
          -- Skip binary files (contains null byte)
          if data:find("\0") then
            callback({})
            return
          end

          -- Extract URLs using patterns module
          local patterns = require("resolved.detection.patterns")
          local config = require("resolved.config").get()
          local refs = {}

          -- Efficient line splitting without string concatenation
          local line_num = 1
          local start_idx = 1
          local data_len = #data

          while start_idx <= data_len do
            local end_idx = data:find("\n", start_idx, true) or (data_len + 1)
            local line_text = data:sub(start_idx, end_idx - 1)

            local urls = patterns.extract_urls(line_text)

            if #urls > 0 then
              local has_keywords = patterns.has_stale_keywords(line_text, config.stale_keywords)

              for _, url_match in ipairs(urls) do
                -- Validate URL match has required fields
                if url_match.url and url_match.owner and url_match.repo and url_match.number then
                  -- Filter out PRs unless include_prs is enabled
                  if url_match.type == "issue" or config.include_prs then
                    table.insert(refs, {
                      url = url_match.url,
                      owner = url_match.owner,
                      repo = url_match.repo,
                      type = url_match.type,
                      number = url_match.number,
                      line = line_num,
                      col = url_match.start_col,
                      end_col = url_match.end_col,
                      comment_text = line_text:match("^%s*(.-)%s*$"), -- Trim
                      has_stale_keywords = has_keywords,
                      file_path = file_path,
                    })
                  end
                end
              end
            end

            line_num = line_num + 1
            start_idx = end_idx + 1
          end

          callback(refs)
        end)
      end)
    end)
  end)
end

---Scan all files in batches (async with progress)
---Uses atomic counter pattern to avoid race conditions in batch completion detection.
---@param files string[] List of file paths to scan
---@param on_progress fun(completed: integer, total: integer, found: integer) Progress callback
---@param callback fun(refs: resolved.FileReference[]) Final callback with all references
local function scan_files_batched(files, on_progress, callback)
  local all_refs = {}
  local completed = 0
  local last_progress_time = 0

  local function process_batch(start_idx)
    if start_idx > #files then
      -- Final progress update
      on_progress(completed, #files, #all_refs)
      callback(all_refs)
      return
    end

    local batch_end = math.min(start_idx + BATCH_SIZE - 1, #files)
    local batch = vim.list_slice(files, start_idx, batch_end)
    local batch_completed = 0
    local batch_size = #batch
    local batch_done = false -- Guard to ensure we only trigger next batch once

    -- Process all files in batch in parallel
    for _, file in ipairs(batch) do
      scan_file_async(file, function(refs)
        -- All state updates happen in vim.schedule callbacks (main thread)
        -- This ensures no race conditions as Lua is single-threaded
        vim.schedule(function()
          -- Guard against duplicate completion
          if batch_done then
            return
          end

          vim.list_extend(all_refs, refs)
          batch_completed = batch_completed + 1
          completed = completed + 1

          if batch_completed >= batch_size then
            batch_done = true -- Prevent any late callbacks from triggering

            -- Batch complete - throttle progress updates
            local now = vim.loop.now()
            if now - last_progress_time >= PROGRESS_THROTTLE_MS then
              on_progress(completed, #files, #all_refs)
              last_progress_time = now
            end

            -- Schedule next batch (yield to event loop)
            vim.schedule(function()
              process_batch(batch_end + 1)
            end)
          end
        end)
      end)
    end
  end

  process_batch(1)
end

---Group references by issue URL
---@param refs resolved.FileReference[]
---@return table<string, resolved.FileReference[]>
local function group_by_url(refs)
  local by_url = {}

  for _, ref in ipairs(refs) do
    if not by_url[ref.url] then
      by_url[ref.url] = {}
    end
    table.insert(by_url[ref.url], ref)
  end

  return by_url
end

---Format issue for picker display with color indicators
---@param issue resolved.PickerIssue
---@return string
local function format_issue(issue)
  local icon, color_marker

  if issue.is_stale then
    icon = "⚠ "
    color_marker = "●" -- Yellow/warning dot
  elseif issue.state == "open" then
    icon = " "
    color_marker = "●" -- Green dot
  else
    icon = "✓ "
    color_marker = "●" -- Gray dot
  end

  local ref_count = #issue.locations

  -- Truncate title if too long
  local title = issue.title
  local max_title_len = 50
  if #title > max_title_len then
    title = title:sub(1, max_title_len - 3) .. "..."
  end

  -- Build format: color_marker [state] icon owner/repo#number (refs) - title
  local status = string.format("[%-6s]", issue.state) -- Pad status to 6 chars for alignment
  local issue_id = string.format("%s/%s#%d", issue.owner, issue.repo, issue.number)

  -- Only show ref count if > 1 to save space
  local ref_info = ref_count > 1 and string.format(" (%d refs)", ref_count) or ""

  return string.format("%s %s %s%s%s - %s", color_marker, status, icon, issue_id, ref_info, title)
end

---Build picker issues from refs and states
---@param by_url table<string, resolved.FileReference[]>
---@param states table<string, resolved.IssueState>
---@return resolved.PickerIssue[]
local function build_picker_issues(by_url, states)
  local issues = {}

  for url, refs in pairs(by_url) do
    local ref = refs[1]
    local state = states[url] or { state = "unknown", title = "Unknown" }

    -- Check if stale (any location has keywords + closed)
    local is_stale = false
    if state.state == "closed" or state.state == "merged" then
      for _, r in ipairs(refs) do
        if r.has_stale_keywords then
          is_stale = true
          break
        end
      end
    end

    local issue = {
      url = url,
      owner = ref.owner,
      repo = ref.repo,
      type = ref.type,
      number = ref.number,
      title = state.title,
      state = state.state,
      locations = refs,
      is_stale = is_stale,
    }

    -- Add fields for snacks.picker
    issue.text = format_issue(issue)
    issue.file = ref.file_path -- For preview
    issue.pos = { ref.line, ref.col } -- Line and column for preview

    -- Add highlight group for coloring
    if issue.is_stale then
      issue.hl = "DiagnosticWarn" -- Yellow/orange for stale
    elseif issue.state == "open" then
      issue.hl = "DiagnosticInfo" -- Blue/cyan for open
    else
      issue.hl = "Comment" -- Gray for closed
    end

    table.insert(issues, issue)
  end

  -- Sort: stale > closed > open (closed first as requested)
  table.sort(issues, function(a, b)
    local function tier(issue)
      if issue.is_stale then
        return 1
      end
      if issue.state == "closed" or issue.state == "merged" then
        return 2
      end
      return 3 -- open
    end
    return tier(a) < tier(b)
  end)

  return issues
end

---Fetch states for URLs (async, uses cache)
---@param by_url table<string, resolved.FileReference[]>
---@param on_progress fun(fetched: integer, total: integer)
---@param callback fun(issues: resolved.PickerIssue[])
local function fetch_and_build_issues(by_url, on_progress, callback)
  local resolved = require("resolved")
  local github = require("resolved.github")

  -- Check cache first
  local to_fetch = {}
  local states = {} -- url -> state

  for url, refs in pairs(by_url) do
    local cached = resolved._cache:get(url)
    if cached then
      states[url] = cached
    else
      local ref = refs[1] -- Use first ref for metadata
      table.insert(to_fetch, {
        url = url,
        owner = ref.owner,
        repo = ref.repo,
        number = ref.number,
        type = ref.type,
      })
    end
  end

  -- If all cached, build issues immediately
  if #to_fetch == 0 then
    local issues = build_picker_issues(by_url, states)
    callback(issues)
    return
  end

  -- Fetch uncached
  on_progress(0, #to_fetch)

  github.fetch_batch(to_fetch, function(results)
    for url, result in pairs(results) do
      if result.state then
        resolved._cache:set(url, result.state)
        states[url] = result.state
      end
    end

    local issues = build_picker_issues(by_url, states)
    callback(issues)
  end)
end

---Jump to file location with validation
---@param location resolved.FileReference
local function jump_to_location(location)
  -- Open file with error handling
  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(location.file_path))
  if not ok then
    notify(string.format("Failed to open file: %s", err), vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    notify("Buffer became invalid after opening file", vim.log.levels.ERROR)
    return
  end

  -- Validate line exists in buffer
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local target_line = location.line
  if target_line > line_count then
    notify(
      string.format("Line %d exceeds file length %d, jumping to end", target_line, line_count),
      vim.log.levels.WARN
    )
    target_line = line_count
  end

  -- Validate column is within line bounds
  local line_text = vim.api.nvim_buf_get_lines(bufnr, target_line - 1, target_line, false)[1] or ""
  local target_col = math.min(location.col, math.max(0, #line_text - 1))

  -- Jump to position
  vim.api.nvim_win_set_cursor(0, { target_line, target_col })

  -- Center view
  vim.cmd("normal! zz")

  -- Flash highlight (optional)
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local ns = vim.api.nvim_create_namespace("resolved_picker_flash")
    local end_col = math.min(location.end_col or (target_col + 1), #line_text)

    pcall(function()
      vim.api.nvim_buf_set_extmark(bufnr, ns, target_line - 1, target_col, {
        end_col = end_col,
        hl_group = "IncSearch",
      })
    end)

    vim.defer_fn(function()
      pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
    end, 500)
  end, 50)
end

---Generic picker creation with snacks.picker fallback to vim.ui.select
---@param items table[] Items to pick from
---@param opts {prompt: string, format_item: fun(item: table): string, format_snacks?: "text"|fun(item: table): table, on_select: fun(item: table)}
local function create_picker(items, opts)
  local has_snacks, snacks = pcall(require, "snacks")

  if has_snacks and snacks.picker then
    -- Determine format for snacks.picker
    local format = opts.format_snacks or "text"

    snacks.picker.pick({
      items = items,
      format = format,
      prompt = opts.prompt,
      on_select = opts.on_select,
    })
  else
    -- Fallback to vim.ui.select
    vim.ui.select(items, {
      prompt = opts.prompt .. ":",
      format_item = opts.format_item,
    }, function(selected)
      if selected then
        opts.on_select(selected)
      end
    end)
  end
end

---Show location picker for multiple refs
---@param issue resolved.PickerIssue
local function show_location_picker(issue)
  ---@param loc resolved.FileReference
  ---@return string
  local function format_loc(loc)
    local rel_path = vim.fn.fnamemodify(loc.file_path, ":~:.")
    return string.format("%s:%d - %s", rel_path, loc.line, loc.comment_text)
  end

  -- Add text field to locations for snacks.picker
  local locations_with_text = {}
  for _, loc in ipairs(issue.locations) do
    local loc_copy = vim.tbl_extend("force", {}, loc)
    loc_copy.text = format_loc(loc)
    table.insert(locations_with_text, loc_copy)
  end

  create_picker(locations_with_text, {
    prompt = string.format("References to #%d", issue.number),
    format_item = format_loc,
    format_snacks = "text",
    on_select = jump_to_location,
  })
end

---Handle issue selection
---@param issue resolved.PickerIssue
local function handle_issue_selection(issue)
  if #issue.locations == 1 then
    jump_to_location(issue.locations[1])
  else
    show_location_picker(issue)
  end
end

---Show snacks picker or fallback
---@param issues resolved.PickerIssue[]
local function show_picker(issues)
  create_picker(issues, {
    prompt = "GitHub Issues",
    format_item = format_issue,
    format_snacks = function(item)
      -- Return array of {text, highlight} tuples for colored display
      return {
        { item.text, item.hl or "Normal" },
      }
    end,
    on_select = handle_issue_selection,
  })
end

---Show GitHub issues picker
---@param opts? {force_refresh: boolean?}
function M.show_issues_picker(opts)
  opts = opts or {}
  local resolved = require("resolved")

  -- Verify setup
  if not resolved._setup_done then
    notify("Run setup() first", vim.log.levels.ERROR)
    return
  end

  -- Use consistent ID string for automatic notification replacement
  local notif_id = "resolved_picker_progress"

  -- Create initial notification (raw vim.notify for progress, without prefix)
  vim.notify("Getting file list...", vim.log.levels.INFO, { id = notif_id, timeout = false })

  get_tracked_files_async(function(err, files)
    if err then
      notify(err, vim.log.levels.ERROR, { id = notif_id, timeout = 3000 })
      return
    end

    if not files or #files == 0 then
      notify("No tracked files", vim.log.levels.INFO, { id = notif_id, timeout = 2000 })
      return
    end

    -- Step 2: Scan files
    scan_files_batched(files, function(completed, total, found)
      -- Reuse same ID to automatically replace notification (no prefix for progress)
      vim.notify(
        string.format("Scanning: %d/%d files (%d refs)", completed, total, found),
        vim.log.levels.INFO,
        { id = notif_id, timeout = false }
      )
    end, function(refs)
      if #refs == 0 then
        notify("No GitHub references found", vim.log.levels.INFO, { id = notif_id, timeout = 2000 })
        return
      end

      -- Step 3: Group by URL
      local by_url = group_by_url(refs)

      -- Step 4: Fetch states (no prefix for progress)
      vim.notify(
        string.format("Fetching status for %d issues...", vim.tbl_count(by_url)),
        vim.log.levels.INFO,
        { id = notif_id, timeout = false }
      )

      fetch_and_build_issues(by_url, function(fetched, total)
        -- Progress callback (currently unused, could show)
      end, function(issues)
        -- Step 5: Replace notification with success message that auto-dismisses
        vim.notify(
          string.format("Found %d issues", #issues),
          vim.log.levels.INFO,
          { id = notif_id, timeout = 500 }
        )
        show_picker(issues)
      end)
    end)
  end)
end

return M
