local M = {}

--- Send a notification with "callisto: " prefix.
--- @param msg string
--- @param level? integer vim.log.levels value (default: INFO)
function M.notify(msg, level)
  vim.notify("callisto: " .. msg, level or vim.log.levels.INFO)
end

--- Get buffer state for the given buffer number.
--- @param bufnr integer
--- @param silent? boolean If true, suppress error notification when state is missing
--- @return callisto.BufState? buf_state
--- @return table? state The callisto module table
function M.get_buf_state(bufnr, silent)
  local state = require("callisto")
  local buf_state = state._buffers[bufnr]
  if not buf_state and not silent then
    M.notify("no state found for buffer " .. bufnr, vim.log.levels.ERROR)
  end
  return buf_state, state
end

--- Build environment table with venv bin prepended to PATH.
--- Returns nil if no venv is configured or found (uses system PATH).
--- @return table<string, string>? env
local function make_env()
  local venv = require("callisto").config.venv
  if not venv then
    return nil
  end
  local venv_bin = vim.fn.getcwd() .. "/" .. venv .. "/bin"
  if vim.fn.isdirectory(venv_bin) ~= 1 then
    return nil
  end
  return { PATH = venv_bin .. ":" .. (vim.env.PATH or "") }
end

--- Run an external command synchronously with unified error handling.
--- @param cmd string[]
--- @param error_prefix string Context string for error messages (e.g. "jupytext read")
--- @return vim.SystemCompleted? result Non-nil on success, nil on failure
function M.run_sync(cmd, error_prefix)
  local result = vim.system(cmd, { text = true, env = make_env() }):wait()
  if result.code ~= 0 then
    local msg = error_prefix .. " failed"
    if result.stderr and result.stderr ~= "" then
      msg = msg .. ": " .. result.stderr
    end
    M.notify(msg, vim.log.levels.ERROR)
    return nil
  end
  return result
end

--- Run an external command asynchronously with unified error handling.
--- @param cmd string[]
--- @param error_prefix string Context string for error messages
--- @param on_success fun(result: vim.SystemCompleted) Called on success (scheduled on main loop)
--- @param on_error? fun(result: vim.SystemCompleted) Called on failure (scheduled on main loop)
function M.run_async(cmd, error_prefix, on_success, on_error)
  vim.system(cmd, { text = true, env = make_env() }, vim.schedule_wrap(function(result)
    if result.code ~= 0 then
      local msg = error_prefix .. " failed"
      if result.stderr and result.stderr ~= "" then
        msg = msg .. ": " .. result.stderr
      end
      M.notify(msg, vim.log.levels.ERROR)
      if on_error then
        on_error(result)
      end
      return
    end
    on_success(result)
  end))
end

return M
