-- lua/onlooker/init.lua
--- onlooker.nvim
---
--- Observe and steer Claude Code sessions from Neovim.
--- Observation (dashboard/feed/digest) is lossless and non-invasive -- it
--- only tails the .jsonl transcripts Claude Code already writes under
--- `~/.claude/projects/`, for every session it finds, whether or not
--- onlooker started it. Steering (dispatch/takeover/queue/cleanup) only ever touches
--- sessions onlooker itself dispatched as terminal jobs: it writes to its own
--- child's pty, never reaches into another process's.
---@tag onlooker
local M = {}


function M.setup(opts)
    require("onlooker.config").setup(opts)
  
    local function command(name, fn, cmd_opts)
      vim.api.nvim_create_user_command(name, fn, cmd_opts or {})
    end
  
    command("OnlookerDashboard", function()
      require("onlooker.dashboard").open()
    end, { desc = "Onlooker: open the session dashboard" })
  
    command("OnlookerFeed", function()
      require("onlooker.feed").open()
    end, { desc = "Onlooker: open the live, lossless feed for a session" })
  
    command("OnlookerDigest", function()
      require("onlooker.digest").open()
    end, { desc = "Onlooker: open the Q&A digest for a session" })
  
    command("OnlookerDispatch", function(o)
      require("onlooker.dispatch").dispatch({ prompt = o.args ~= "" and o.args or nil })
    end, { desc = "Onlooker: dispatch a new agent in the current directory", nargs = "*" })
  
    command("OnlookerTakeover", function()
      require("onlooker.takeover").take()
    end, { desc = "Onlooker: take over a dispatched session's TUI" })
  
    command("OnlookerQueue", function()
      require("onlooker.queue").queue()
    end, { desc = "Onlooker: queue a message into a dispatched session" })
  
    command("OnlookerCleanup", function()
      require("onlooker.cleanup").run()
    end, { desc = "Onlooker: clean up idle, detached dispatched sessions" })
  
    local map = vim.keymap.set
    map("n", "<leader>oo", "<cmd>OnlookerDashboard<cr>", { desc = "Onlooker: dashboard" })
    map("n", "<leader>of", "<cmd>OnlookerFeed<cr>", { desc = "Onlooker: live feed" })
    map("n", "<leader>od", "<cmd>OnlookerDigest<cr>", { desc = "Onlooker: Q&A digest" })
    map("n", "<leader>on", "<cmd>OnlookerDispatch<cr>", { desc = "Onlooker: dispatch new agent" })
    map("n", "<leader>ot", "<cmd>OnlookerTakeover<cr>", { desc = "Onlooker: take over session" })
    map("n", "<leader>om", "<cmd>OnlookerQueue<cr>", { desc = "Onlooker: queue message" })
    map("n", "<leader>ox", "<cmd>OnlookerCleanup<cr>", { desc = "Onlooker: cleanup idle sessions" })
  end
  
  return M
  