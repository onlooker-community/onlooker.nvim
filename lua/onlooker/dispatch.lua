-- Dispatches a new Claude Code agent as a Neovim terminal job that
-- onlooker owns, so it can later be taken over or steered.
local config = require("onlooker.config")
local discover = require("onlooker.discover")
local registry = require("onlooker.registry")

local M = {}

--- opts.cwd: working directory (default: current). opts.prompt: initial
--- message to queue once the agent boots. opts.label: display label.
function M.dispatch(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.getcwd()
  local since = os.time()
  local label = opts.label or vim.fn.fnamemodify(cwd, ":t")

  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()

  local entry
  local job_id = vim.fn.jobstart({ config.options.claude_bin }, {
    term = true,
    cwd = cwd,
    on_exit = function()
      vim.schedule(function()
        vim.notify(string.format("onlooker: %s exited", label))
      end)
    end,
  })

  if job_id <= 0 then
    vim.notify("onlooker: failed to start '" .. config.options.claude_bin .. "'", vim.log.levels.ERROR)
    vim.api.nvim_buf_delete(buf, { force = true })
    return nil
  end

  entry = registry.add({ job_id = job_id, buf = buf, cwd = cwd, label = label })
  pcall(vim.api.nvim_buf_set_name, buf, string.format("onlooker://dispatch/%s/%d", label, entry.id))

  if opts.prompt then
    vim.defer_fn(function()
      registry.send(entry, opts.prompt)
    end, 1500)
  end

  -- Bind the transcript Claude Code creates for this run, so idle
  -- tracking and the dashboard reflect real activity, not just wall time
  -- since dispatch.
  local attempts = 0
  local timer = vim.uv.new_timer()
  timer:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      attempts = attempts + 1
      local session = discover.find_new_session(cwd, since)
      if session or attempts >= 30 then
        if session then
          entry.session_id = session.session_id
          entry.session_path = session.path
        end
        timer:stop()
        timer:close()
      end
    end)
  )

  vim.notify(string.format("onlooker: dispatched agent in %s", cwd))
  return entry
end

return M
