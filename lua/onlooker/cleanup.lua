-- Finds onlooker-dispatched sessions that are detached (not shown in any
-- window) and have been idle past the configured threshold, and offers
-- to kill them. Never touches sessions onlooker didn't dispatch.
local config = require("onlooker.config")
local registry = require("onlooker.registry")

local M = {}

function M.candidates()
  local threshold = config.options.idle_cleanup_minutes * 60
  local out = {}
  for _, entry in ipairs(registry.list()) do
    if registry.is_detached(entry) and registry.idle_seconds(entry) >= threshold then
      out[#out + 1] = entry
    end
  end
  return out
end

function M.run()
  local candidates = M.candidates()
  if #candidates == 0 then
    vim.notify(string.format("onlooker: no detached sessions idle past %dm", config.options.idle_cleanup_minutes))
    return
  end

  local report = {
    string.format("onlooker: %d detached session(s) idle past %dm:", #candidates, config.options.idle_cleanup_minutes),
  }
  for _, e in ipairs(candidates) do
    report[#report + 1] =
      string.format("  - %s (%s), idle %dm", e.label, e.cwd, math.floor(registry.idle_seconds(e) / 60))
  end
  vim.notify(table.concat(report, "\n"))

  vim.ui.select({ "Yes, kill them", "No, cancel" }, {
    prompt = string.format("Clean up %d idle detached session(s)?", #candidates),
  }, function(choice)
    if choice == "Yes, kill them" then
      for _, e in ipairs(candidates) do
        registry.kill(e)
      end
      vim.notify(string.format("onlooker: cleaned up %d session(s)", #candidates))
    end
  end)
end

return M
