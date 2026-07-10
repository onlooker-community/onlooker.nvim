-- Factory for tab-scoped views that tail a session transcript and render
-- it live. Both the feed and the digest are this same lifecycle; they
-- only differ in how they transform rendered blocks before display.
local view = require("onlooker.view")
local transcript = require("onlooker.transcript")
local render = require("onlooker.render")

local M = {}

--- Returns an `open(session)` function that opens (or refocuses) a tab
--- tailing `session.path` from the start, rendering each record through
--- `render.render` and then `transform(blocks) -> blocks` (optional).
function M.new(uri_prefix, transform)
  local open_state = {} -- session_id -> { buf, win, tail }

  return function(session)
    local existing = open_state[session.session_id]
    if existing and vim.api.nvim_buf_is_valid(existing.buf) then
      vim.cmd("tabnew")
      vim.api.nvim_win_set_buf(0, existing.buf)
      vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(existing.buf), 0 })
      return
    end

    local name = string.format("%s://%s", uri_prefix, session.session_id:sub(1, 8))
    local buf, win = view.open_tab(name, "onlooker")
    view.enable_inspect(buf)

    local tail = transcript.tail(session.path, function(events)
      for _, event in ipairs(events) do
        local blocks = render.render(event)
        view.append(buf, win, transform and transform(blocks) or blocks)
      end
    end, { from_start = true })

    open_state[session.session_id] = { buf = buf, win = win, tail = tail }
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        tail.stop()
        open_state[session.session_id] = nil
      end,
    })
  end
end

return M
