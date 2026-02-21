local M = {}

local defaults = {
  jupytext = {
    format = "py:percent",
  },
  preview = {
    command = "MarkdownPreview",
  },
}

-- Module state
M.config = {}

-- Mapping: bufnr -> { ipynb_path, tmp_py, tmpdir, watcher }
M._buffers = {}

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

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = aug,
    pattern = "*.ipynb",
    nested = true,
    callback = function(args)
      require("callisto.converter").write(args.buf, args.file)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = aug,
    pattern = "*.ipynb",
    callback = function(args)
      require("callisto.converter").cleanup(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = aug,
    callback = function()
      require("callisto.converter").cleanup_all()
    end,
  })

  require("callisto.commands").register()
end

return M
