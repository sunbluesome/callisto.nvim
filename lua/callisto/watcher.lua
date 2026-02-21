local M = {}

local timers = {}

-- Start watching an .ipynb file for external changes
function M.start(bufnr, ipynb_path)
  local state = require("callisto")
  local buf_state = state._buffers[bufnr]
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

  handle:start(ipynb_path, {}, vim.schedule_wrap(function(err)
    if err then
      return
    end

    -- Debounce: wait 200ms after last event
    if timers[bufnr] then
      timers[bufnr]:stop()
      timers[bufnr]:close()
    end

    timers[bufnr] = vim.uv.new_timer()
    timers[bufnr]:start(200, 0, vim.schedule_wrap(function()
      if timers[bufnr] then
        timers[bufnr]:stop()
        timers[bufnr]:close()
        timers[bufnr] = nil
      end

      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      if vim.bo[bufnr].modified then
        vim.notify(
          "callisto: external change detected but buffer has unsaved changes",
          vim.log.levels.WARN
        )
        return
      end

      M.reload(bufnr)
    end))
  end))
end

-- Reload buffer content from the .ipynb file
function M.reload(bufnr)
  local state = require("callisto")
  local buf_state = state._buffers[bufnr]
  if not buf_state then
    return
  end

  local format = state.config.jupytext.format

  vim.system({
    "jupytext",
    "--to", format,
    "--output", buf_state.tmp_py,
    buf_state.ipynb_path,
  }, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      vim.notify(
        "callisto: reload failed: " .. (result.stderr or "unknown error"),
        vim.log.levels.ERROR
      )
      return
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local lines = vim.fn.readfile(buf_state.tmp_py)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modified = false
  end))
end

-- Stop watching for a specific buffer
function M.stop(bufnr)
  local state = require("callisto")
  local buf_state = state._buffers[bufnr]
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
