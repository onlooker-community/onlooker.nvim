-- Defaults for the onlooker plugin. Nothing here talks to disk or
-- processes; `discover.lua`/`transcript.lua`/etc. read `M.options`.
local M = {}

M.defaults = {
  claude_bin = "claude",
  -- Where Claude Code writes session transcripts. One subdirectory per
  -- project, one append-only .jsonl file per session.
  projects_root = vim.fn.expand("~/.claude/projects"),
  -- How often the live feed/digest re-check a tailed transcript for
  -- appended lines.
  poll_ms = 750,
  -- How often the dashboard re-scans ~/.claude/projects for sessions.
  scan_ms = 4000,
  -- A session is "active" if its transcript was written to within this
  -- many seconds; otherwise it's "idle".
  active_window_seconds = 120,
  -- Dispatched sessions whose terminal buffer is detached (not shown in
  -- any window) and idle longer than this are cleanup candidates.
  idle_cleanup_minutes = 45,
  -- How much of a transcript's tail to read when summarizing a session
  -- for the dashboard (last-activity preview).
  max_tail_bytes = 65536,
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
