local util = require("callisto.util")

local M = {}

--- Generate a .py path for an ipynb file.
--- In sync mode, returns the .py path alongside the .ipynb (no tmpdir).
--- Otherwise, creates a unique tmpdir and returns the .py path inside it.
--- @param ipynb_path string
--- @param base_tmpdir? string  Base directory for temp files (nil = OS default)
--- @param sync boolean         Save .py alongside .ipynb
--- @return string? tmpdir  nil in sync mode
--- @return string tmp_py
local function make_tmp_path(ipynb_path, base_tmpdir, sync)
  local basename = vim.fn.fnamemodify(ipynb_path, ":t:r")
  if sync then
    return nil, vim.fn.fnamemodify(ipynb_path, ":h") .. "/" .. basename .. ".py"
  end
  local dir
  if base_tmpdir then
    base_tmpdir = vim.fn.fnamemodify(base_tmpdir, ":p")
    local unique = vim.fn.fnamemodify(vim.fn.tempname(), ":t")
    dir = base_tmpdir .. "/" .. unique .. "_callisto"
  else
    dir = vim.fn.tempname() .. "_callisto"
  end
  vim.fn.mkdir(dir, "p")
  return dir, dir .. "/" .. basename .. ".py"
end

--- Configure the buffer as a Python file for LSP compatibility.
--- Renames the buffer to .py, fires BufReadPre for lazy-loaded plugins,
--- and sets the filetype to Python.
--- @param bufnr integer
--- @param ipynb_path string
local function setup_buffer_filetype(bufnr, ipynb_path)
  local py_name = ipynb_path:gsub("%.ipynb$", ".py")
  vim.api.nvim_buf_set_name(bufnr, py_name)

  -- BufReadCmd suppresses the normal read event chain, so we emit
  -- BufReadPre manually to trigger lazy-loaded plugins (mason, LSP).
  vim.api.nvim_exec_autocmds("BufReadPre", { buffer = bufnr })

  -- Set filetype after BufReadPre so LSP is already initialized
  vim.bo[bufnr].filetype = "python"
  vim.bo[bufnr].modified = false
end

--- Register buffer-local autocmds for write and cleanup.
--- Pattern-based *.ipynb won't match after the buffer is renamed to .py,
--- so we use buffer-specific autocmds instead.
--- @param bufnr integer
--- @param ipynb_path string
local function register_buffer_autocmds(bufnr, ipynb_path)
  local aug = vim.api.nvim_create_augroup("CallistoBuf" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    buffer = bufnr,
    nested = true,
    callback = function()
      require("callisto.converter").write(bufnr, ipynb_path)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = aug,
    buffer = bufnr,
    callback = function()
      require("callisto.converter").cleanup(bufnr)
    end,
  })
end

--- Register buffer-local keymaps from configuration.
--- @param bufnr integer
--- @param keys table { run?: string, export?: string }
local function register_buffer_keymaps(bufnr, keys)
  if keys.run then
    vim.keymap.set("n", keys.run, "<cmd>NotebookRun<cr>", {
      buffer = bufnr,
      desc = "Execute notebook",
    })
  end
  if keys.export then
    vim.keymap.set("n", keys.export, "<cmd>NotebookExport<cr>", {
      buffer = bufnr,
      desc = "Export notebook to markdown",
    })
  end
end

--- Read: convert .ipynb -> .py via jupytext and load into buffer.
--- @param bufnr integer
--- @param ipynb_path string
function M.read(bufnr, ipynb_path)
  local state = require("callisto")
  ipynb_path = vim.fn.fnamemodify(ipynb_path, ":p")

  local tmpdir, tmp_py = make_tmp_path(ipynb_path, state.config.tmpdir, state.config.sync)

  local result = util.run_sync({
    "jupytext",
    "--to", state.JUPYTEXT_FORMAT,
    "--output", tmp_py,
    ipynb_path,
  }, "jupytext read")

  if not result then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "# Error: Failed to convert " .. ipynb_path,
    })
    return
  end

  local lines = vim.fn.readfile(tmp_py)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = true

  state.create_buf_state(bufnr, ipynb_path, tmp_py, tmpdir)
  setup_buffer_filetype(bufnr, ipynb_path)
  register_buffer_autocmds(bufnr, ipynb_path)
  register_buffer_keymaps(bufnr, state.config.keys)

  require("callisto.watcher").start(bufnr, ipynb_path)
end

--- Write: convert buffer content back to .ipynb via jupytext.
--- @param bufnr integer
--- @param ipynb_path string
function M.write(bufnr, ipynb_path)
  local buf_state, state = util.get_buf_state(bufnr)
  if not buf_state then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.fn.writefile(lines, buf_state.tmp_py)

  vim.cmd.doautocmd({ args = { "BufWritePre", ipynb_path }, mods = { silent = true } })

  -- Stop watcher to prevent circular reload
  require("callisto.watcher").stop(bufnr)

  util.run_async({
    "jupytext",
    "--to", "notebook",
    "--update",
    "--output", buf_state.ipynb_path,
    buf_state.tmp_py,
  }, "jupytext write", function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.bo[bufnr].modified = false
    end

    vim.cmd.doautocmd({ args = { "BufWritePost", ipynb_path }, mods = { silent = true } })

    vim.api.nvim_exec_autocmds("User", {
      pattern = "CallistoNotebookWritten",
      data = { bufnr = bufnr },
    })

    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) and state._buffers[bufnr] then
        require("callisto.watcher").start(bufnr, buf_state.ipynb_path)
      end
    end, state.config.watcher.restart_delay_ms)
  end, function()
    require("callisto.watcher").start(bufnr, buf_state.ipynb_path)
  end)
end

--- Cleanup a single buffer's resources.
--- @param bufnr integer
function M.cleanup(bufnr)
  local buf_state, state = util.get_buf_state(bufnr, true)
  if not buf_state then
    return
  end

  require("callisto.watcher").stop(bufnr)
  if buf_state.tmpdir then
    vim.fn.delete(buf_state.tmpdir, "rf")
  end
  state._buffers[bufnr] = nil
end

--- Set up sync for a .py file opened directly with a paired .ipynb.
--- Syncs based on timestamps, then reuses existing buffer infrastructure.
--- @param bufnr integer
--- @param py_path string   Absolute path to the .py file
--- @param ipynb_path string Absolute path to the paired .ipynb file
function M.setup_paired(bufnr, py_path, ipynb_path)
  local state = require("callisto")

  -- Sync based on timestamps
  local py_mtime = vim.fn.getftime(py_path)
  local ipynb_mtime = vim.fn.getftime(ipynb_path)
  if py_mtime > ipynb_mtime then
    -- .py is newer → update .ipynb (preserve output cells)
    util.run_sync({
      "jupytext", "--to", "notebook", "--update",
      "--output", ipynb_path, py_path,
    }, "jupytext sync")
  elseif ipynb_mtime > py_mtime then
    -- .ipynb is newer → update .py and reload buffer content
    util.run_sync({
      "jupytext", "--to", state.JUPYTEXT_FORMAT,
      "--output", py_path, ipynb_path,
    }, "jupytext sync")
    local lines = vim.fn.readfile(py_path)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modified = false
  end

  -- Register state (tmpdir=nil → no file deletion on cleanup)
  state.create_buf_state(bufnr, ipynb_path, py_path, nil)
  register_buffer_autocmds(bufnr, ipynb_path)
  register_buffer_keymaps(bufnr, state.config.keys)
  require("callisto.watcher").start(bufnr, ipynb_path)
end

--- Cleanup all buffers (called on VimLeavePre).
function M.cleanup_all()
  local state = require("callisto")
  for bufnr, _ in pairs(state._buffers) do
    M.cleanup(bufnr)
  end
end

return M
