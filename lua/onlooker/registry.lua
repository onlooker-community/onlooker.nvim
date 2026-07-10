-- Tracks sessions onlooker itself dispatched as Neovim terminal jobs.
-- Steering (takeover/queue/cleanup) only ever touches these: onlooker
-- writes to its own child's pty, never to a session it merely observes.
local M = {}

M.entries = {}

local next_id = 0

function M.add(entry)
  next_id = next_id + 1
  entry.id = next_id
  entry.dispatched_at = os.time()
  M.entries[entry.id] = entry
  return entry
end

--- Live, buffer-valid entries, most recently dispatched first. Also
--- prunes entries whose buffer got wiped out from under us.
function M.list()
  local out = {}
  for id, entry in pairs(M.entries) do
    if vim.api.nvim_buf_is_valid(entry.buf) then
      out[#out + 1] = entry
    else
      M.entries[id] = nil
    end
  end
  table.sort(out, function(a, b)
    return a.dispatched_at > b.dispatched_at
  end)
  return out
end

function M.is_running(entry)
  return vim.fn.jobwait({ entry.job_id }, 0)[1] == -1
end

function M.is_detached(entry)
  return #vim.fn.win_findbuf(entry.buf) == 0
end

--- Seconds since real activity: the bound transcript's mtime once known
--- (Claude Code stops writing while idle-waiting on input), else time
--- since dispatch.
function M.idle_seconds(entry)
  if entry.session_path then
    local stat = vim.uv.fs_stat(entry.session_path)
    if stat then
      return os.time() - stat.mtime.sec
    end
  end
  return os.time() - entry.dispatched_at
end

--- Type `message` into the session's own pty, as if the user had typed
--- it and pressed Enter.
function M.send(entry, message)
  if not M.is_running(entry) then
    vim.notify("onlooker: that session is no longer running", vim.log.levels.WARN)
    return false
  end
  vim.fn.chansend(entry.job_id, message .. "\r")
  return true
end

function M.kill(entry)
  pcall(vim.fn.jobstop, entry.job_id)
  if vim.api.nvim_buf_is_valid(entry.buf) then
    vim.api.nvim_buf_delete(entry.buf, { force = true })
  end
  M.entries[entry.id] = nil
end

return M
