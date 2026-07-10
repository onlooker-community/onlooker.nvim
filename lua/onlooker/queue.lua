-- Queues a message into a running, onlooker-dispatched session without
-- taking it over: types it straight into the session's own pty.
local registry = require("onlooker.registry")

local M = {}

local function prompt_and_send(entry)
  vim.ui.input({ prompt = string.format("Queue message to %s: ", entry.label) }, function(message)
    if message and message ~= "" and registry.send(entry, message) then
      vim.notify("onlooker: message queued")
    end
  end)
end

function M.queue(entry)
  if entry then
    return prompt_and_send(entry)
  end

  local entries = registry.list()
  if #entries == 0 then
    vim.notify(
      "onlooker: no dispatched sessions to queue into (only sessions started via :OnlookerDispatch can be steered)",
      vim.log.levels.WARN
    )
    return
  end
  if #entries == 1 then
    return prompt_and_send(entries[1])
  end

  vim.ui.select(entries, {
    prompt = "Onlooker: queue a message into which session?",
    format_item = function(e)
      return string.format("%s  (%s)", e.label, e.cwd)
    end,
  }, function(choice)
    if choice then
      prompt_and_send(choice)
    end
  end)
end

return M
