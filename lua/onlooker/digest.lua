-- The Q&A digest: user turns and assistant answers, with tool calls
-- collapsed to a single line and pure noise (thinking, results, system,
-- context-update records) dropped.
local live_view = require("onlooker.live_view")
local pick = require("onlooker.pick")

local M = {}

local KEEP = { user = true, assistant = true, tool = true }

local function digestify(blocks)
  local out = {}
  for _, blk in ipairs(blocks) do
    if KEEP[blk.kind] then
      if blk.kind == "tool" then
        out[#out + 1] = { kind = blk.kind, text = blk.text:match("^[^\n]*"), raw = blk.raw }
      else
        out[#out + 1] = blk
      end
    end
  end
  return out
end

local open_digest = live_view.new("onlooker://digest", digestify)

function M.open(session)
  if session then
    return open_digest(session)
  end
  pick.session({ prompt = "Onlooker: Q&A digest for…" }, function(s)
    if s then
      open_digest(s)
    end
  end)
end

return M
