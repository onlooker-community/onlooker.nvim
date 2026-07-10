-- Incremental, lossless tailing of a session's .jsonl transcript. Onlooker
-- never opens these files for writing and never seeks backward past what
-- it has already delivered -- it only reads newly appended bytes.
local M = {}

local function split_lines(text)
  local lines = {}
  local from = 1
  while true do
    local nl = text:find("\n", from, true)
    if not nl then
      break
    end
    local line = text:sub(from, nl - 1)
    if line ~= "" then
      lines[#lines + 1] = line
    end
    from = nl + 1
  end
  return lines, text:sub(from)
end

--- Tail `path`, calling `on_events(events)` on the main loop whenever new
--- JSON records are appended. Returns a handle with `:stop()`.
--- opts.from_start: replay the whole file instead of starting at EOF.
function M.tail(path, on_events, opts)
  opts = opts or {}
  local poll_ms = opts.poll_ms or require("onlooker.config").options.poll_ms
  local state = { offset = 0, leftover = "", stopped = false }

  local stat = vim.uv.fs_stat(path)
  if stat then
    state.offset = opts.from_start and 0 or stat.size
  end

  local timer = vim.uv.new_timer()

  local function poll()
    if state.stopped then
      return
    end
    local st = vim.uv.fs_stat(path)
    if not st then
      return
    end

    if st.size < state.offset then
      -- Transcript was truncated or rotated; replay from the top.
      state.offset = 0
      state.leftover = ""
    end
    if st.size <= state.offset then
      return
    end

    local fd = vim.uv.fs_open(path, "r", 420)
    if not fd then
      return
    end
    local chunk = vim.uv.fs_read(fd, st.size - state.offset, state.offset)
    vim.uv.fs_close(fd)
    if not chunk or chunk == "" then
      return
    end
    state.offset = st.size

    local lines
    lines, state.leftover = split_lines(state.leftover .. chunk)
    if #lines == 0 then
      return
    end

    local events = {}
    for _, line in ipairs(lines) do
      local ok, decoded = pcall(vim.json.decode, line)
      if ok and type(decoded) == "table" then
        events[#events + 1] = decoded
      end
    end
    if #events > 0 then
      vim.schedule(function()
        on_events(events)
      end)
    end
  end

  timer:start(0, poll_ms, vim.schedule_wrap(poll))

  return {
    stop = function()
      if state.stopped then
        return
      end
      state.stopped = true
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end,
  }
end

return M
