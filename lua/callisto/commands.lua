local M = {}

function M.register()
  vim.api.nvim_create_user_command("NotebookRun", function()
    M.run()
  end, { desc = "Execute notebook via nbconvert" })

  vim.api.nvim_create_user_command("NotebookPreview", function()
    M.preview()
  end, { desc = "Preview notebook as markdown in browser" })

  vim.api.nvim_create_user_command("NotebookExport", function()
    M.export()
  end, { desc = "Export notebook as markdown to project directory" })
end

-- Save buffer if modified and wait for completion
local function save_if_modified(bufnr)
  if vim.bo[bufnr].modified then
    vim.cmd("write")
    vim.wait(2000, function()
      return not vim.bo[bufnr].modified
    end, 100)
  end
end

-- Get current buffer's notebook state, or nil with error
local function get_buf_state()
  local state = require("callisto")
  local bufnr = vim.api.nvim_get_current_buf()
  local buf_state = state._buffers[bufnr]

  if not buf_state then
    vim.notify("callisto: current buffer is not a notebook", vim.log.levels.ERROR)
    return nil, nil, nil
  end

  return state, bufnr, buf_state
end

-- :NotebookRun - execute the notebook in-place
function M.run()
  local state, bufnr, buf_state = get_buf_state()
  if not buf_state then
    return
  end

  save_if_modified(bufnr)

  vim.notify("callisto: executing notebook...", vim.log.levels.INFO)

  require("callisto.watcher").stop(bufnr)

  vim.system({
    "jupyter", "nbconvert",
    "--to", "notebook",
    "--execute",
    "--inplace",
    buf_state.ipynb_path,
  }, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      vim.notify(
        "callisto: notebook execution failed:\n" .. (result.stderr or "unknown error"),
        vim.log.levels.ERROR
      )
    else
      vim.notify("callisto: notebook execution completed", vim.log.levels.INFO)
      require("callisto.watcher").reload(bufnr)
    end

    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(bufnr) and state._buffers[bufnr] then
        require("callisto.watcher").start(bufnr, buf_state.ipynb_path)
      end
    end, 300)
  end))
end

-- :NotebookPreview - convert to markdown and preview in browser
function M.preview()
  local state, bufnr, buf_state = get_buf_state()
  if not buf_state then
    return
  end

  save_if_modified(bufnr)

  local md_tmpdir = vim.fn.tempname() .. "_callisto_preview"
  vim.fn.mkdir(md_tmpdir, "p")

  vim.notify("callisto: generating preview...", vim.log.levels.INFO)

  vim.system({
    "jupyter", "nbconvert",
    "--to", "markdown",
    "--output-dir", md_tmpdir,
    buf_state.ipynb_path,
  }, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      vim.notify(
        "callisto: preview generation failed:\n" .. (result.stderr or "unknown error"),
        vim.log.levels.ERROR
      )
      vim.fn.delete(md_tmpdir, "rf")
      return
    end

    local basename = vim.fn.fnamemodify(buf_state.ipynb_path, ":t:r")
    local md_path = md_tmpdir .. "/" .. basename .. ".md"

    vim.cmd("edit " .. vim.fn.fnameescape(md_path))
    local md_bufnr = vim.api.nvim_get_current_buf()

    vim.bo[md_bufnr].modifiable = false
    vim.bo[md_bufnr].readonly = true

    local preview_cmd = state.config.preview.command
    local ok, err = pcall(vim.cmd, preview_cmd)
    if not ok then
      vim.notify("callisto: " .. preview_cmd .. " failed: " .. err, vim.log.levels.WARN)
    end

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      buffer = md_bufnr,
      once = true,
      callback = function()
        pcall(vim.cmd, "MarkdownPreviewStop")
        vim.fn.delete(md_tmpdir, "rf")
      end,
    })
  end))
end

-- :NotebookExport - convert to markdown in the project directory
function M.export()
  local _, bufnr, buf_state = get_buf_state()
  if not buf_state then
    return
  end

  save_if_modified(bufnr)

  local output_dir = vim.fn.fnamemodify(buf_state.ipynb_path, ":h")

  vim.notify("callisto: exporting to markdown...", vim.log.levels.INFO)

  vim.system({
    "jupyter", "nbconvert",
    "--to", "markdown",
    "--output-dir", output_dir,
    buf_state.ipynb_path,
  }, { text = true }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      vim.notify(
        "callisto: export failed:\n" .. (result.stderr or "unknown error"),
        vim.log.levels.ERROR
      )
      return
    end

    local basename = vim.fn.fnamemodify(buf_state.ipynb_path, ":t:r")
    local md_path = output_dir .. "/" .. basename .. ".md"
    vim.notify("callisto: exported to " .. md_path, vim.log.levels.INFO)
  end))
end

return M
