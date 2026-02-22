local M = {}

--- @class callisto.BufState
--- @field ipynb_path string   Absolute path to the .ipynb file
--- @field tmp_py string       Path to .py file (tmpdir or alongside .ipynb)
--- @field tmpdir? string      Path to temporary directory (nil in sync mode)
--- @field watcher? userdata   uv_fs_event_t handle (managed by watcher module)

-- Internal constants (not user-configurable)
M.JUPYTEXT_FORMAT = "py:percent"

local defaults = {
  tmpdir = nil,
  sync = false,
  venv = ".venv",
  run = {
    auto_export = true,
  },
  watcher = {
    debounce_ms = 200,
    restart_delay_ms = 300,
  },
  keys = {
    run = "<leader>nr",
    export = "<leader>ne",
  },
}

M.config = {}

--- Buffer state table: bufnr -> callisto.BufState
M._buffers = {}

--- Create and register a new buffer state entry.
--- @param bufnr integer
--- @param ipynb_path string
--- @param tmp_py string
--- @param tmpdir? string
--- @return callisto.BufState
function M.create_buf_state(bufnr, ipynb_path, tmp_py, tmpdir)
  local buf_state = {
    ipynb_path = ipynb_path,
    tmp_py = tmp_py,
    tmpdir = tmpdir,
    watcher = nil,
  }
  M._buffers[bufnr] = buf_state
  return buf_state
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})

  local aug = vim.api.nvim_create_augroup("Callisto", { clear = true })

  vim.api.nvim_create_autocmd("BufReadCmd", {
    group = aug,
    pattern = "*.ipynb",
    nested = true,
    callback = function(args)
      require("callisto.converter").read(args.buf, args.file)
    end,
  })

  -- BufWriteCmd and BufDelete are registered per-buffer in converter.read()
  -- because the buffer is renamed to .py for LSP compatibility.

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = aug,
    callback = function()
      require("callisto.converter").cleanup_all()
    end,
  })

  -- Detect paired .py files when sync is enabled
  if M.config.sync then
    vim.api.nvim_create_autocmd("BufReadPost", {
      group = aug,
      pattern = "*.py",
      callback = function(args)
        local py_path = vim.fn.fnamemodify(args.file, ":p")
        local ipynb_path = py_path:gsub("%.py$", ".ipynb")
        if vim.fn.filereadable(ipynb_path) ~= 1 then
          return
        end
        if M._buffers[args.buf] then
          return
        end
        require("callisto.converter").setup_paired(args.buf, py_path, ipynb_path)
      end,
    })
  end

  require("callisto.commands").register()
end

return M
