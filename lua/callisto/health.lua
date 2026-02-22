local M = {}

--- Check if a command is available, considering venv if configured.
--- @param cmd string
--- @param venv_bin? string
--- @return string? path Absolute path to the command, or nil
local function find_command(cmd, venv_bin)
  if venv_bin then
    local venv_path = venv_bin .. "/" .. cmd
    if vim.fn.executable(venv_path) == 1 then
      return venv_path
    end
  end
  if vim.fn.executable(cmd) == 1 then
    return cmd
  end
  return nil
end

function M.check()
  vim.health.start("callisto.nvim")

  -- Resolve venv
  local ok, state = pcall(require, "callisto")
  local venv_bin = nil
  if ok and state.config and state.config.venv then
    local venv_dir = vim.fn.getcwd() .. "/" .. state.config.venv
    local bin_dir = venv_dir .. "/bin"
    if vim.fn.isdirectory(bin_dir) == 1 then
      venv_bin = bin_dir
      vim.health.ok("venv found: " .. venv_dir)
    else
      vim.health.info("venv not found: " .. venv_dir .. " (using system PATH)")
    end
  end

  -- Check jupytext
  local jupytext = find_command("jupytext", venv_bin)
  if jupytext then
    local version = vim.fn.system(jupytext .. " --version"):gsub("%s+$", "")
    vim.health.ok("jupytext found: " .. jupytext .. " (" .. version .. ")")
  else
    vim.health.error("jupytext not found", {
      "Install with: pip install jupytext",
    })
  end

  -- Check nbconvert
  local jupyter = find_command("jupyter", venv_bin)
  if jupyter then
    local result = vim.fn.system(jupyter .. " nbconvert --version"):gsub("%s+$", "")
    if result ~= "" and not result:match("Error") then
      vim.health.ok("nbconvert found: " .. jupyter .. " (" .. result .. ")")
    else
      vim.health.error("jupyter nbconvert not found", {
        "Install with: pip install nbconvert",
      })
    end
  else
    vim.health.error("jupyter not found", {
      "Install with: pip install jupyter",
    })
  end

  -- Show current configuration
  if ok and state.config then
    vim.health.start("callisto.nvim configuration")
    vim.health.ok("venv: " .. (state.config.venv or "(disabled)"))
    vim.health.ok("sync: " .. tostring(state.config.sync))
    vim.health.ok("tmpdir: " .. (state.config.tmpdir or "(OS default)"))
    vim.health.ok("run.auto_export: " .. tostring(state.config.run.auto_export))
    vim.health.ok("watcher.debounce_ms: " .. tostring(state.config.watcher.debounce_ms))
    vim.health.ok("watcher.restart_delay_ms: " .. tostring(state.config.watcher.restart_delay_ms))
  end
end

return M
