local M = {}

local function get_state()
  return require("callisto")
end

-- Generate a unique tmpdir and .py path for an ipynb file
local function make_tmp_path(ipynb_path)
  local dir = vim.fn.tempname() .. "_callisto"
  vim.fn.mkdir(dir, "p")
  local basename = vim.fn.fnamemodify(ipynb_path, ":t:r")
  return dir, dir .. "/" .. basename .. ".py"
end

-- Read: convert .ipynb -> .py via jupytext, load into buffer
function M.read(bufnr, ipynb_path)
  local state = get_state()
  local format = state.config.jupytext.format

  ipynb_path = vim.fn.fnamemodify(ipynb_path, ":p")

  local tmpdir, tmp_py = make_tmp_path(ipynb_path)

  local result = vim.system({
    "jupytext",
    "--to", format,
    "--output", tmp_py,
    ipynb_path,
  }, { text = true }):wait()

  if result.code ~= 0 then
    vim.notify(
      "callisto: jupytext read failed: " .. (result.stderr or "unknown error"),
      vim.log.levels.ERROR
    )
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "# Error: Failed to convert " .. ipynb_path,
      "# " .. (result.stderr or ""),
    })
    return
  end

  local lines = vim.fn.readfile(tmp_py)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  vim.bo[bufnr].filetype = "python"
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = true

  state._buffers[bufnr] = {
    ipynb_path = ipynb_path,
    tmp_py = tmp_py,
    tmpdir = tmpdir,
    watcher = nil,
  }

  require("callisto.watcher").start(bufnr, ipynb_path)
end

-- Write: convert buffer content back to .ipynb via jupytext
function M.write(bufnr, ipynb_path)
  local state = get_state()
  local buf_state = state._buffers[bufnr]

  if not buf_state then
    vim.notify("callisto: no state found for buffer", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.fn.writefile(lines, buf_state.tmp_py)

  vim.cmd.doautocmd({ args = { "BufWritePre", ipynb_path }, mods = { silent = true } })

  -- Stop watcher to prevent circular reload
  require("callisto.watcher").stop(bufnr)

  vim.system({
    "jupytext",
    "--to", "notebook",
    "--output", buf_state.ipynb_path,
    buf_state.tmp_py,
  }, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      vim.notify(
        "callisto: jupytext write failed: " .. (result.stderr or "unknown error"),
        vim.log.levels.ERROR
      )
      -- Restart watcher even on failure
      require("callisto.watcher").start(bufnr, buf_state.ipynb_path)
      return
    end

    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.bo[bufnr].modified = false
    end

    vim.cmd.doautocmd({ args = { "BufWritePost", ipynb_path }, mods = { silent = true } })

    -- Restart watcher after a delay to avoid catching the tail end of write
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) and state._buffers[bufnr] then
        require("callisto.watcher").start(bufnr, buf_state.ipynb_path)
      end
    end, 300)
  end))
end

-- Cleanup a single buffer's resources
function M.cleanup(bufnr)
  local state = get_state()
  local buf_state = state._buffers[bufnr]
  if not buf_state then
    return
  end

  require("callisto.watcher").stop(bufnr)
  vim.fn.delete(buf_state.tmpdir, "rf")
  state._buffers[bufnr] = nil
end

-- Cleanup all buffers
function M.cleanup_all()
  local state = get_state()
  for bufnr, _ in pairs(state._buffers) do
    M.cleanup(bufnr)
  end
end

return M
