-- Session picker shared by the feed, digest, takeover, and queue commands.
local discover = require("onlooker.discover")

local M = {}

local function label(session, now)
  local status = discover.status(session, now)
  local marker = status == "active" and "●" or "○"
  local age_min = math.floor((now - session.mtime) / 60)
  local where = session.cwd and vim.fn.fnamemodify(session.cwd, ":t") or "?"
  local branch = session.git_branch and ("@" .. session.git_branch) or ""
  local preview = (session.preview or ""):gsub("%s+", " ")
  if #preview > 60 then
    preview = preview:sub(1, 57) .. "..."
  end
  return string.format(
    "%s %-8s %s%-20s %3dm ago  %s",
    marker,
    session.session_id:sub(1, 8),
    where,
    branch,
    age_min,
    preview
  )
end

--- Prompt the user to pick one known session. opts.cwd restricts to a
--- single project's sessions. Calls callback(session|nil).
function M.session(opts, callback)
  opts = opts or {}
  local sessions = discover.list({ cwd = opts.cwd })
  if #sessions == 0 then
    vim.notify("onlooker: no sessions found", vim.log.levels.WARN)
    return callback(nil)
  end
  local now = os.time()
  vim.ui.select(sessions, {
    prompt = opts.prompt or "Onlooker: choose a session",
    format_item = function(s)
      return label(s, now)
    end,
  }, callback)
end

return M
