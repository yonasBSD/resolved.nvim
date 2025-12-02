local config = require("resolved.config")
local cache_mod = require("resolved.cache")
local github = require("resolved.github")
local scanner = require("resolved.scanner")
local display = require("resolved.display")

local M = {}

-- Internal state
M._enabled = false
M._setup_done = false
M._setup_pending = false -- True while async setup is in progress
M._setup_generation = 0 -- Incremented on each setup to detect stale callbacks
M._cache = nil ---@type resolved.Cache|nil
M._debounce_timers = {} ---@type table<integer, uv_timer_t>
M._augroup = nil ---@type integer|nil

---Check if the plugin is enabled
---@return boolean
function M.is_enabled()
  return M._enabled
end

---Enable the plugin
function M.enable()
  if M._setup_pending then
    vim.notify("[resolved.nvim] Setup in progress, please wait...", vim.log.levels.INFO)
    return
  end
  if not M._setup_done then
    vim.notify(
      "[resolved.nvim] Plugin not set up. Call require('resolved').setup() first.",
      vim.log.levels.WARN
    )
    return
  end
  M._enabled = true
  M.refresh()
end

---Disable the plugin
---@param full_reset? boolean If true, also reset setup state (for testing)
function M.disable(full_reset)
  M._enabled = false
  display.clear_all()
  -- Cancel pending timers
  for bufnr, timer in pairs(M._debounce_timers) do
    if timer and timer:is_closing() == false then
      timer:stop()
      timer:close()
    end
    M._debounce_timers[bufnr] = nil
  end

  -- Full reset for testing or reconfiguration
  if full_reset then
    M._setup_done = false
    M._setup_pending = false
    M._setup_generation = M._setup_generation + 1 -- Invalidate any pending callbacks
    M._cache = nil
    if M._augroup then
      pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
      M._augroup = nil
    end
    -- Reset GitHub auth cache
    github._reset_auth_check()
  end
end

---Toggle the plugin
function M.toggle()
  if M._enabled then
    M.disable()
  else
    M.enable()
  end
end

---Clear the cache
function M.clear_cache()
  if M._cache then
    M._cache:clear()
  end
end

---Refresh the current buffer
function M.refresh()
  if not M._enabled then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  M._scan_buffer(bufnr)
end

---Refresh all visible buffers
function M.refresh_all()
  if not M._enabled then
    return
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    M._scan_buffer(bufnr)
  end
end

---Internal: Determine if a reference is stale
---@param state resolved.IssueState
---@param has_stale_keywords boolean
---@return boolean
local function is_stale(state, has_stale_keywords)
  -- A reference is "stale" if:
  -- 1. The issue/PR is closed or merged
  -- 2. AND the comment contains stale keywords (suggesting it's a workaround)
  local is_closed = state.state == "closed" or state.state == "merged"
  return is_closed and has_stale_keywords
end

---Internal: Process scan results and update display
---@param bufnr integer
---@param refs resolved.Reference[]
local function process_refs(bufnr, refs)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Collect URLs that need fetching
  local to_fetch = {}
  local cached_results = {}

  for _, ref in ipairs(refs) do
    local cached = M._cache:get(ref.url)
    if cached then
      cached_results[ref.url] = cached
    else
      table.insert(to_fetch, {
        url = ref.url,
        owner = ref.owner,
        repo = ref.repo,
        number = ref.number,
        type = ref.type,
      })
    end
  end

  -- Function to update display with results
  local function update_display(results)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local display_items = {}

    for _, ref in ipairs(refs) do
      local state = results[ref.url]
      if state then
        table.insert(display_items, {
          line = ref.line,
          col = ref.col,
          end_col = ref.end_col,
          url = ref.url,
          state = state,
          is_stale = is_stale(state, ref.has_stale_keywords),
          has_stale_keywords = ref.has_stale_keywords,
        })
      end
    end

    -- Update display safely
    pcall(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        display.update(bufnr, display_items)
      end
    end)
  end

  -- If everything is cached, update immediately
  if #to_fetch == 0 then
    update_display(cached_results)
    return
  end

  -- Fetch uncached URLs
  github.fetch_batch(to_fetch, function(fetch_results)
    -- Merge with cached results
    local all_results = vim.tbl_extend("force", {}, cached_results)

    for url, result in pairs(fetch_results) do
      if result.state then
        M._cache:set(url, result.state)
        all_results[url] = result.state
      elseif result.err then
        -- Log error but don't block display
        vim.schedule(function()
          vim.notify(string.format("[resolved.nvim] %s", result.err), vim.log.levels.DEBUG)
        end)
      end
    end

    vim.schedule(function()
      update_display(all_results)
    end)
  end)
end

---Internal: Scan a buffer for references
---@param bufnr integer
function M._scan_buffer(bufnr)
  if not M._enabled or not M._setup_done then
    return
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Skip special buffers
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return
  end

  local refs = scanner.scan(bufnr)
  if #refs == 0 then
    display.clear(bufnr)
    return
  end

  process_refs(bufnr, refs)
end

---Internal: Debounced scan
---@param bufnr integer
function M._debounced_scan(bufnr)
  if not M._enabled then
    return
  end

  local cfg = config.get()

  -- Clean up existing timer safely
  local existing = M._debounce_timers[bufnr]
  if existing then
    -- Use pcall to handle race condition where timer might be closing
    -- Use explicit == false check since is_closing() can return nil
    pcall(function()
      if existing:is_closing() == false then
        existing:stop()
      end
    end)
    pcall(function()
      if existing:is_closing() == false then
        existing:close()
      end
    end)
  end

  -- Create new timer
  local timer = vim.uv.new_timer()
  M._debounce_timers[bufnr] = timer

  timer:start(cfg.debounce_ms, 0, function()
    timer:stop()
    timer:close()
    M._debounce_timers[bufnr] = nil

    vim.schedule(function()
      -- Recheck buffer validity inside schedule
      if not vim.api.nvim_buf_is_valid(bufnr) then
        M._debounce_timers[bufnr] = nil
        return
      end
      M._scan_buffer(bufnr)
    end)
  end)
end

---Internal: Set up autocommands
local function setup_autocmds()
  if M._augroup then
    vim.api.nvim_del_augroup_by_id(M._augroup)
  end

  M._augroup = vim.api.nvim_create_augroup("resolved", { clear = true })

  -- Scan on buffer enter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = M._augroup,
    callback = function(args)
      if M._enabled then
        M._debounced_scan(args.buf)
      end
    end,
  })

  -- Scan on save
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = M._augroup,
    callback = function(args)
      if M._enabled then
        M._debounced_scan(args.buf)
      end
    end,
  })

  -- Scan on idle
  vim.api.nvim_create_autocmd("CursorHold", {
    group = M._augroup,
    callback = function(args)
      if M._enabled then
        M._debounced_scan(args.buf)
      end
    end,
  })

  -- Clean up on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    group = M._augroup,
    callback = function(args)
      local timer = M._debounce_timers[args.buf]
      -- Use explicit == false check since is_closing() can return nil
      if timer and timer:is_closing() == false then
        timer:stop()
        timer:close()
      end
      M._debounce_timers[args.buf] = nil
    end,
  })
end

---Subcommands for :Resolved
local subcommands = {
  enable = {
    fn = function()
      M.enable()
    end,
    desc = "Enable the plugin",
  },
  disable = {
    fn = function()
      M.disable()
    end,
    desc = "Disable the plugin",
  },
  toggle = {
    fn = function()
      M.toggle()
    end,
    desc = "Toggle enabled state",
  },
  refresh = {
    fn = function()
      M.refresh()
    end,
    desc = "Refresh current buffer",
  },
  clear_cache = {
    fn = function()
      M.clear_cache()
      vim.notify("[resolved.nvim] Cache cleared", vim.log.levels.INFO)
    end,
    desc = "Clear the issue status cache",
  },
  status = {
    fn = function()
      local state = M._enabled and "enabled" or "disabled"
      vim.notify(string.format("[resolved.nvim] %s", state), vim.log.levels.INFO)
    end,
    desc = "Show plugin status",
  },
  issues = {
    fn = function()
      require("resolved.picker").show_issues_picker()
    end,
    desc = "Show all GitHub issues in workspace",
  },
}

---Internal: Set up user commands
local function setup_commands()
  vim.api.nvim_create_user_command("Resolved", function(opts)
    local args = opts.fargs
    local subcmd = args[1]

    if not subcmd then
      -- No subcommand: show status
      subcommands.status.fn()
      return
    end

    local cmd = subcommands[subcmd]
    if cmd then
      cmd.fn()
    else
      vim.notify(string.format("[resolved.nvim] Unknown command: %s", subcmd), vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    desc = "resolved.nvim commands",
    complete = function(arg_lead, cmd_line, cursor_pos)
      local names = vim.tbl_keys(subcommands)
      table.sort(names)

      if arg_lead == "" then
        return names
      end

      return vim.tbl_filter(function(name)
        return name:find(arg_lead, 1, true) == 1
      end, names)
    end,
  })
end

---Set up the plugin
---@param user_config? resolved.Config
function M.setup(user_config)
  -- Prevent double initialization
  if M._setup_done then
    vim.notify(
      "[resolved.nvim] Already initialized. Call resolved.disable() first if you want to reconfigure.",
      vim.log.levels.WARN
    )
    return
  end

  -- Prevent concurrent setup attempts
  if M._setup_pending then
    vim.notify("[resolved.nvim] Setup already in progress.", vim.log.levels.WARN)
    return
  end

  -- Step 1: Validate and apply configuration (sync, fast)
  config.setup(user_config)
  local cfg = config.get()

  -- Step 2: Setup commands early so users can interact during async init
  setup_commands()

  -- Mark setup as pending with a new generation
  M._setup_pending = true
  M._setup_generation = M._setup_generation + 1
  local my_generation = M._setup_generation

  -- Step 3: Check GitHub auth asynchronously (non-blocking)
  github.check_auth_async(function(ok, err)
    -- Guard: if this callback is from a stale setup (reset/new setup occurred), abort
    if M._setup_generation ~= my_generation then
      return
    end

    M._setup_pending = false

    if not ok then
      -- Silent fail - user can check :checkhealth resolved for details
      return
    end

    -- Step 4: Initialize cache (after validation passes)
    M._cache = cache_mod.new(cfg.cache_ttl)

    -- Step 5: Setup autocmds (only after all validation passes)
    setup_autocmds()

    M._setup_done = true

    -- Step 6: Enable if configured to start enabled
    if cfg.enabled then
      M.enable()
    end
  end)
end

return M
