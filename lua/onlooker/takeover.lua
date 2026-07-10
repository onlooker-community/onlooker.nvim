-- Hands the terminal back to you: focuses an onlooker-dispatched
-- session's real TUI in a new tab and drops straight into terminal mode.
local registry = require("onlooker.registry")

local M = {}

local function focus(entry)
  vim.cmd("tabnew")
  vim.api.nvim_win_set_buf(0, entry.buf)
  vim.cmd("startinsert")
end

function M.take(entry)
  if entry then
    return focus(entry)
  end

  local entries = registry.list()
  if #entries == 0 then
    vim.notify(
      "onlooker: no dispatched sessions to take over (use :OnlookerDispatch to start one)",
      vim.log.levels.WARN
    )
    return
  end
  if #entries == 1 then
    return focus(entries[1])
  end

  vim.ui.select(entries, {
    prompt = "Onlooker: take over which session?",
    format_item = function(e)
      return string.format("%s  (%s)  idle %ds", e.label, e.cwd, registry.idle_seconds(e))
    end,
  }, function(choice)
    if choice then
      focus(choice)
    end
  end)
end

return M
