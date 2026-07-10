-- Finds Claude Code session transcripts on disk and summarizes them
-- cheaply (head/tail peeks) without loading whole files into memory.
local config = require("onlooker.config")

local M = {}

local function peek_head(path, max_lines)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local info = {}
  for _ = 1, max_lines do
    local line = fd:read("l")
    if not line then
      break
    end
    local ok, decoded = pcall(vim.json.decode, line)
    if ok and type(decoded) == "table" then
      info.session_id = info.session_id or decoded.sessionId
      info.cwd = info.cwd or decoded.cwd
      info.git_branch = info.git_branch or decoded.gitBranch
      if info.cwd and info.session_id then
        break
      end
    end
  end
  fd:close()
  return info
end

local function first_text_block(content)
  if type(content) ~= "table" then
    return nil
  end
  for _, block in ipairs(content) do
    if type(block) == "table" and block.type == "text" and block.text and block.text ~= "" then
      return block.text
    end
  end
  return nil
end

local function peek_tail(path, max_bytes)
  local fd = io.open(path, "rb")
  if not fd then
    return nil
  end
  local size = fd:seek("end")
  local start = math.max(0, size - max_bytes)
  fd:seek("set", start)
  local chunk = fd:read(size - start)
  fd:close()
  if not chunk or chunk == "" then
    return nil
  end

  local lines = vim.split(chunk, "\n", { plain = true, trimempty = true })
  local info = {}
  for i = #lines, 1, -1 do
    local ok, decoded = pcall(vim.json.decode, lines[i])
    if ok and type(decoded) == "table" then
      info.timestamp = info.timestamp or decoded.timestamp
      if not info.preview and type(decoded.message) == "table" then
        local text = first_text_block(decoded.message.content)
        if text then
          info.preview = text
          info.preview_role = decoded.message.role
        end
      end
      if info.timestamp and info.preview then
        break
      end
    end
  end
  return info
end

--- List known sessions, most-recently-active first.
--- opts.cwd: only sessions whose transcript cwd matches exactly.
function M.list(opts)
  opts = opts or {}
  local root = config.options.projects_root
  local sessions = {}

  for _, dir in ipairs(vim.fn.glob(root .. "/*", false, true)) do
    if vim.fn.isdirectory(dir) == 1 then
      for _, path in ipairs(vim.fn.glob(dir .. "/*.jsonl", false, true)) do
        local stat = vim.uv.fs_stat(path)
        if stat and stat.size > 0 then
          local head = peek_head(path, 12) or {}
          local tail = peek_tail(path, config.options.max_tail_bytes) or {}
          sessions[#sessions + 1] = {
            session_id = head.session_id or vim.fn.fnamemodify(path, ":t:r"),
            path = path,
            cwd = head.cwd,
            git_branch = head.git_branch,
            mtime = stat.mtime.sec,
            size = stat.size,
            preview = tail.preview,
            preview_role = tail.preview_role,
            last_timestamp = tail.timestamp,
          }
        end
      end
    end
  end

  table.sort(sessions, function(a, b)
    return a.mtime > b.mtime
  end)

  if opts.cwd then
    sessions = vim.tbl_filter(function(s)
      return s.cwd == opts.cwd
    end, sessions)
  end

  return sessions
end

--- "active" (still being written to) vs "idle" (quiet for a while).
function M.status(session, now)
  now = now or os.time()
  if (now - session.mtime) <= config.options.active_window_seconds then
    return "active"
  end
  return "idle"
end

--- Find the newest session for `cwd` created at or after `since` (epoch
--- seconds). Used to bind a freshly dispatched terminal to the transcript
--- Claude Code creates for it.
function M.find_new_session(cwd, since)
  for _, session in ipairs(M.list({ cwd = cwd })) do
    if session.mtime >= since then
      return session
    end
  end
  return nil
end

return M
