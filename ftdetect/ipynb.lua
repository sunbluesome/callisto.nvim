vim.filetype.add({
  extension = {
    ipynb = "ipynb",
  },
})

-- Bootstrap paired .py detection for sync mode.
-- When callisto is lazy-loaded, this ensures opening a .py with a
-- paired .ipynb triggers plugin load and sync setup.
vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = "*.py",
  callback = function(args)
    local py_path = vim.fn.fnamemodify(args.file, ":p")
    local ipynb_path = py_path:gsub("%.py$", ".ipynb")
    if vim.fn.filereadable(ipynb_path) ~= 1 then
      return
    end
    local ok, callisto = pcall(require, "callisto")
    if not ok or not callisto.config or not callisto.config.sync then
      return
    end
    if callisto._buffers[args.buf] then
      return
    end
    require("callisto.converter").setup_paired(args.buf, py_path, ipynb_path)
  end,
})
