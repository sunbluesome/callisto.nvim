local M = {}

function M.check()
  vim.health.start("callisto.nvim")

  -- Check jupytext
  if vim.fn.executable("jupytext") == 1 then
    local version = vim.fn.system("jupytext --version"):gsub("%s+$", "")
    vim.health.ok("jupytext found: " .. version)
  else
    vim.health.error("jupytext not found in PATH", {
      "Install with: pip install jupytext",
    })
  end

  -- Check nbconvert
  if vim.fn.executable("jupyter") == 1 then
    local result = vim.fn.system("jupyter nbconvert --version"):gsub("%s+$", "")
    if result ~= "" and not result:match("Error") then
      vim.health.ok("nbconvert found: " .. result)
    else
      vim.health.error("jupyter nbconvert not found", {
        "Install with: pip install nbconvert",
      })
    end
  else
    vim.health.error("jupyter not found in PATH", {
      "Install with: pip install jupyter",
    })
  end

  -- Check markdown preview plugin
  if vim.fn.exists(":MarkdownPreview") == 2 then
    vim.health.ok("markdown-preview.nvim available")
  else
    vim.health.warn("markdown-preview.nvim not detected", {
      ":NotebookPreview requires a markdown preview plugin",
    })
  end
end

return M
