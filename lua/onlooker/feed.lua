-- The live, lossless feed: every turn, tool call, bash command, and diff
-- for a single session, appended as Claude Code writes its transcript.
local live_view = require("onlooker.live_view")
local pick = require("onlooker.pick")

local M = {}

local open_feed = live_view.new("onlooker://feed")

function M.open(session)
  if session then
    return open_feed(session)
  end
  pick.session({ prompt = "Onlooker: live feed for…" }, function(s)
    if s then
      open_feed(s)
    end
  end)
end

return M
