-- Full view of everything onlooker can see: every session it finds on
-- disk (active or idle, dispatched by onlooker or not), refreshed on a
-- timer, with actions to drill into or steer any of them.
local config = require("onlooker.config")
local discover = require("onlooker.discover")
local registry = require("onlooker.registry")

local M = {}

local state = { buf = nil, timer = nil, line_map = {}, scope_cwd = nil }

local function fmt_age(seconds)
  if seconds < 60 then
    return string.format("%ds", seconds)
  end
  if seconds < 3600 then
    return string.format("%dm", math.floor(seconds / 60))
  end
  return string.format("%dh", math.floor(seconds / 3600))
end

local function pad(text, width)
  local w = vim.fn.strdisplaywidth(text)
  if w >= width then
    return text
  end
  return text .. string.rep(" ", width - w)
end

local function registry_for_session(session_id)
  if not session_id then
    return nil
  end
  for _, e in ipairs(registry.list()) do
    if e.session_id == session_id then
      return e
    end
  end
  return nil
end

local function render_lines()
  local now = os.time()
  local sessions = discover.list({ cwd = state.scope_cwd })

  local lines, line_map = {}, {}
  local scope_label = state.scope_cwd and vim.fn.fnamemodify(state.scope_cwd, ":~") or "all projects"
  lines[#lines + 1] = string.format("onlooker  ·  %s  ·  %s", scope_label, os.date("%H:%M:%S"))
  lines[#lines + 1] = ""
  lines[#lines + 1] =
    string.format("  %s %-9s %-18s %-14s %6s  %s", pad("", 3), "session", "project", "branch", "active", "last turn")

  if #sessions == 0 then
    lines[#lines + 1] = "  (no sessions found)"
  end

  for _, s in ipairs(sessions) do
    local marker = discover.status(s, now) == "active" and "●" or "○"
    if registry_for_session(s.session_id) then
      marker = marker .. "◆"
    end
    local proj = (s.cwd and vim.fn.fnamemodify(s.cwd, ":t") or "?"):sub(1, 18)
    local branch = (s.git_branch or ""):sub(1, 14)
    local preview = (s.preview or ""):gsub("%s+", " ")
    if #preview > 70 then
      preview = preview:sub(1, 67) .. "..."
    end

    lines[#lines + 1] = string.format(
      "  %s %-9s %-18s %-14s %6s  %s",
      pad(marker, 3),
      s.session_id:sub(1, 8),
      proj,
      branch,
      fmt_age(now - s.mtime),
      preview
    )
    line_map[#lines] = s
  end

  local pending = vim.tbl_filter(function(e)
    return not e.session_id
  end, registry.list())
  if #pending > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  dispatched, transcript not yet seen:"
    for _, e in ipairs(pending) do
      lines[#lines + 1] = string.format("  %s %-9s %s", pad("◆", 3), "-", e.label)
      line_map[#lines] = e
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "<CR> feed  D digest  T takeover  M queue  N dispatch  X cleanup  a all/project  gr refresh  q quit"

  return lines, line_map
end

function M.open()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, state.buf)
    return
  end

  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "onlooker-dashboard"
  vim.bo[buf].modifiable = false
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.cursorline = true
  vim.wo.signcolumn = "no"
  pcall(vim.api.nvim_buf_set_name, buf, "onlooker://dashboard")
  state.buf = buf

  local function refresh()
    if not vim.api.nvim_buf_is_valid(state.buf) then
      return
    end
    local lines, line_map = render_lines()
    state.line_map = line_map
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
  end

  local function target()
    return state.line_map[vim.api.nvim_win_get_cursor(0)[1]]
  end

  local function entry_for(t)
    if not t then
      return nil
    end
    return t.job_id and t or registry_for_session(t.session_id)
  end

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, silent = true, nowait = true, desc = desc })
  end

  map("<CR>", function()
    local t = target()
    if t and t.path then
      require("onlooker.feed").open(t)
    elseif t then
      vim.notify("onlooker: no transcript yet for this session", vim.log.levels.WARN)
    end
  end, "Onlooker: open live feed")

  map("D", function()
    local t = target()
    if t and t.path then
      require("onlooker.digest").open(t)
    elseif t then
      vim.notify("onlooker: no transcript yet for this session", vim.log.levels.WARN)
    end
  end, "Onlooker: open Q&A digest")

  map("T", function()
    local e = entry_for(target())
    if not e then
      vim.notify("onlooker: only sessions dispatched via :OnlookerDispatch can be taken over", vim.log.levels.WARN)
      return
    end
    require("onlooker.takeover").take(e)
  end, "Onlooker: take over session")

  map("M", function()
    local e = entry_for(target())
    if not e then
      vim.notify("onlooker: only sessions dispatched via :OnlookerDispatch can be queued into", vim.log.levels.WARN)
      return
    end
    require("onlooker.queue").queue(e)
  end, "Onlooker: queue a message")

  map("N", function()
    require("onlooker.dispatch").dispatch({ cwd = state.scope_cwd })
  end, "Onlooker: dispatch new agent")

  map("X", function()
    require("onlooker.cleanup").run()
  end, "Onlooker: clean up idle sessions")

  map("a", function()
    state.scope_cwd = state.scope_cwd and nil or vim.fn.getcwd()
    refresh()
  end, "Onlooker: toggle all-projects/this-project scope")

  map("gr", refresh, "Onlooker: refresh")
  map("q", "<cmd>tabclose<cr>", "Onlooker: close dashboard")

  refresh()

  state.timer = vim.uv.new_timer()
  state.timer:start(config.options.scan_ms, config.options.scan_ms, vim.schedule_wrap(refresh))

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if state.timer and not state.timer:is_closing() then
        state.timer:stop()
        state.timer:close()
      end
      state.buf = nil
    end,
  })
end

return M
