local util = require("callisto.util")

local M = {}

--- Debounce timers per buffer.
--- @type table<integer, uv_timer_t>
local timers = {}

--- Start watching an .ipynb file for external changes.
--- @param bufnr integer
--- @param ipynb_path string
function M.start(bufnr, ipynb_path)
  local buf_state, state = util.get_buf_state(bufnr, true)
  if not buf_state then
    return
  end

  -- Don't start a new watcher if one already exists
  if buf_state.watcher then
    return
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  buf_state.watcher = handle
  local debounce_ms = state.config.watcher.debounce_ms

  handle:start(ipynb_path, {}, vim.schedule_wrap(function(err)
    if err then
      return
    end

    -- Debounce: wait after last event before reloading
    if timers[bufnr] then
      timers[bufnr]:stop()
      timers[bufnr]:close()
    end

    timers[bufnr] = vim.uv.new_timer()
    timers[bufnr]:start(debounce_ms, 0, vim.schedule_wrap(function()
      if timers[bufnr] then
        timers[bufnr]:stop()
        timers[bufnr]:close()
        timers[bufnr] = nil
      end

      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      if vim.bo[bufnr].modified then
        util.notify("external change detected but buffer has unsaved changes", vim.log.levels.WARN)
        return
      end

      M.reload(bufnr)
    end))
  end))
end

--- Reload buffer content from the .ipynb file.
--- @param bufnr integer
function M.reload(bufnr)
  local buf_state, state = util.get_buf_state(bufnr, true)
  if not buf_state then
    return
  end

  util.run_async({
    "jupytext",
    "--to", state.JUPYTEXT_FORMAT,
    "--output", buf_state.tmp_py,
    buf_state.ipynb_path,
  }, "reload", function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local lines = vim.fn.readfile(buf_state.tmp_py)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modified = false

    -- Emit user event for extensibility
    vim.api.nvim_exec_autocmds("User", {
      pattern = "CallistoNotebookReloaded",
      data = { bufnr = bufnr },
    })
  end)
end

--- Stop watching for a specific buffer.
--- @param bufnr integer
function M.stop(bufnr)
  local buf_state = util.get_buf_state(bufnr, true)
  if buf_state and buf_state.watcher then
    buf_state.watcher:stop()
    buf_state.watcher:close()
    buf_state.watcher = nil
  end

  if timers[bufnr] then
    timers[bufnr]:stop()
    timers[bufnr]:close()
    timers[bufnr] = nil
  end
end

return M
