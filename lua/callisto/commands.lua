local util = require("callisto.util")

local M = {}

function M.register()
  vim.api.nvim_create_user_command("NotebookRun", function()
    M.run()
  end, { desc = "Execute notebook via nbconvert" })

  vim.api.nvim_create_user_command("NotebookExport", function()
    M.export()
  end, { desc = "Export notebook as markdown to project directory" })
end

--- Save buffer if modified and wait for the async write to complete.
--- @param bufnr integer
--- @return boolean ok True if buffer is saved (or was not modified), false on timeout
local function save_if_modified(bufnr)
  if not vim.bo[bufnr].modified then
    return true
  end
  vim.cmd("write")
  local ok = vim.wait(5000, function()
    return not vim.bo[bufnr].modified
  end, 100)
  if not ok then
    util.notify("save timed out, aborting", vim.log.levels.ERROR)
  end
  return ok
end

--- Get current buffer's notebook state, or nil with error notification.
--- @return table? state The callisto module table
--- @return integer? bufnr
--- @return callisto.BufState? buf_state
local function get_buf_state()
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state, state = util.get_buf_state(bufnr, true)
  if not buf_state then
    util.notify("current buffer is not a notebook", vim.log.levels.ERROR)
    return nil, nil, nil
  end
  return state, bufnr, buf_state
end

--- :NotebookRun - execute the notebook in-place via nbconvert.
function M.run()
  local state, bufnr, buf_state = get_buf_state()
  if not buf_state then
    return
  end

  if not save_if_modified(bufnr) then
    return
  end

  util.notify("executing notebook...")

  require("callisto.watcher").stop(bufnr)

  util.run_async({
    "jupyter", "nbconvert",
    "--to", "notebook",
    "--execute",
    "--inplace",
    buf_state.ipynb_path,
  }, "notebook execution", function()
    util.notify("notebook execution completed")
    require("callisto.watcher").reload(bufnr)

    if state.config.run.auto_export then
      M.export()
    end

    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) and state._buffers[bufnr] then
        require("callisto.watcher").start(bufnr, buf_state.ipynb_path)
      end
    end, state.config.watcher.restart_delay_ms)
  end, function()
    -- Restart watcher even on failure
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) and state._buffers[bufnr] then
        require("callisto.watcher").start(bufnr, buf_state.ipynb_path)
      end
    end, state.config.watcher.restart_delay_ms)
  end)
end

--- :NotebookExport - convert notebook to markdown in the project directory.
function M.export()
  local _, bufnr, buf_state = get_buf_state()
  if not buf_state then
    return
  end

  if not save_if_modified(bufnr) then
    return
  end

  local output_dir = vim.fn.fnamemodify(buf_state.ipynb_path, ":h")

  util.notify("exporting to markdown...")

  util.run_async({
    "jupyter", "nbconvert",
    "--to", "markdown",
    "--output-dir", output_dir,
    buf_state.ipynb_path,
  }, "export", function()
    local basename = vim.fn.fnamemodify(buf_state.ipynb_path, ":t:r")
    local md_path = output_dir .. "/" .. basename .. ".md"
    util.notify("exported to " .. md_path)
  end)
end

return M
