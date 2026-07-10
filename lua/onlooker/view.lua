-- Shared scratch-buffer plumbing for onlooker's views (dashboard, feed,
-- digest): opening a tab-scoped buffer, appending rendered blocks with
-- tail-follow + highlighting, and inspecting a block's raw source record.
local M = {}

local NS = vim.api.nvim_create_namespace("onlooker")
local raw_store = {} -- bufnr -> { [0-indexed line] = raw event }

local HL_BY_KIND = {
  user = "Title",
  assistant = "String",
  tool = "Function",
  result = "Comment",
  thinking = "NonText",
  system = "WarningMsg",
  meta = "Comment",
}

function M.ns()
  return NS
end

--- Open a wiped, unlisted scratch buffer in a new tab.
function M.open_tab(name, filetype)
  vim.cmd("tabnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = filetype or "onlooker"
  vim.bo[buf].modifiable = false
  vim.wo.wrap = true
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  pcall(vim.api.nvim_buf_set_name, buf, name)

  raw_store[buf] = {}
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      raw_store[buf] = nil
    end,
  })

  return buf, vim.api.nvim_get_current_win()
end

local function buffer_is_empty(buf)
  local count = vim.api.nvim_buf_line_count(buf)
  return count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

--- Append rendered `blocks` (from onlooker.render) to `buf`, tailing the
--- window if its cursor was already at the end. `filter(block) -> bool`
--- optionally drops blocks (used by the digest to collapse tool noise).
function M.append(buf, win, blocks, filter)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end

  local new_lines, kinds, raws = {}, {}, {}
  for _, blk in ipairs(blocks) do
    if not filter or filter(blk) then
      for _, line in ipairs(vim.split(blk.text, "\n", { plain = true })) do
        new_lines[#new_lines + 1] = line
        kinds[#new_lines] = blk.kind
        raws[#new_lines] = blk.raw
      end
    end
  end
  if #new_lines == 0 then
    return
  end

  local old_count = vim.api.nvim_buf_line_count(buf)
  local start = buffer_is_empty(buf) and 0 or old_count

  local was_modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, start, -1, false, new_lines)
  vim.bo[buf].modifiable = was_modifiable

  local store = raw_store[buf]
  for i = 1, #new_lines do
    local lnum = start + i - 1
    local hl = HL_BY_KIND[kinds[i]]
    if hl then
      vim.api.nvim_buf_set_extmark(buf, NS, lnum, 0, { line_hl_group = hl })
    end
    if store then
      store[lnum] = raws[i]
    end
  end

  if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    if cursor_line >= old_count then
      vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    end
  end
end

--- Show the full, untruncated raw record behind the block under the
--- cursor -- the escape hatch that keeps rendering "lossy" without
--- making observation lossy.
function M.inspect_raw(raw)
  local lines = vim.split(vim.inspect(raw), "\n", { plain = true })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "lua"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " onlooker: raw record ",
  })
  local close = "<cmd>close<cr>"
  vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })
end

--- Bind <CR> in `buf` to inspect the raw record behind the cursor line.
function M.enable_inspect(buf)
  vim.keymap.set("n", "<CR>", function()
    local store = raw_store[buf]
    if not store then
      return
    end
    local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
    if store[lnum] then
      M.inspect_raw(store[lnum])
    end
  end, { buffer = buf, silent = true, desc = "Onlooker: inspect raw record" })
end

return M
