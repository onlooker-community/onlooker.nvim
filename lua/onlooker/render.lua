-- Turns a raw transcript record into one or more display "blocks".
--
-- Rendering is a lossy *view* for convenience (long output gets
-- truncated), but observation itself stays lossless: every block carries
-- its `raw` source record so the feed/digest can show the untruncated
-- original on demand (see onlooker.view's `<CR>` inspect binding).
local M = {}

local MAX_RESULT_LINES = 40

local function clock(timestamp)
  if type(timestamp) ~= "string" then
    return "--:--:--"
  end
  return timestamp:match("T(%d%d:%d%d:%d%d)") or "--:--:--"
end

local function truncate_lines(text, max_lines)
  if type(text) ~= "string" then
    return {}, false
  end
  local lines = vim.split(text, "\n", { plain = true })
  if #lines <= max_lines then
    return lines, false
  end
  local shown = vim.list_slice(lines, 1, max_lines)
  return shown, #lines - max_lines
end

local function block(kind, text, raw)
  return { kind = kind, text = text, raw = raw }
end

local function first_line(text)
  return (text or ""):match("^[^\n]*") or ""
end

-- Tool-specific one-liners plus optional detail (diff/output) attached
-- below. `input` is the tool_use call's arguments.
local tool_formatters = {}

tool_formatters.Bash = function(input)
  local cmd = input.command or ""
  return "$ " .. first_line(cmd), (cmd:find("\n") and cmd or nil)
end

tool_formatters.Read = function(input)
  return "Read " .. (input.file_path or "?")
end

tool_formatters.Write = function(input)
  local n = input.content and (select(2, input.content:gsub("\n", "\n")) + 1) or 0
  return string.format("Write %s (%d lines)", input.file_path or "?", n)
end

tool_formatters.Edit = function(input)
  local header = "Edit " .. (input.file_path or "?")
  local diff = nil
  if input.old_string and input.new_string then
    local ok, result = pcall(vim.diff, input.old_string, input.new_string, {
      result_type = "unified",
      ctxlen = 2,
    })
    if ok and result and result ~= "" then
      diff = result
    end
  end
  return header, diff
end

tool_formatters.Grep = function(input)
  return string.format("Grep %q in %s", input.pattern or "?", input.path or ".")
end

tool_formatters.Glob = function(input)
  return string.format("Glob %q in %s", input.pattern or "?", input.path or ".")
end

tool_formatters.Task = function(input)
  return string.format("Task[%s]: %s", input.subagent_type or "?", input.description or "")
end

tool_formatters.TodoWrite = function(input)
  local todos = input.todos or {}
  local lines = { string.format("Todos updated (%d items)", #todos) }
  for _, todo in ipairs(todos) do
    lines[#lines + 1] = string.format("  [%s] %s", todo.status or "?", todo.content or todo.activeForm or "")
  end
  return lines[1], table.concat(lines, "\n", 2)
end

tool_formatters.WebFetch = function(input)
  return "WebFetch " .. (input.url or "?")
end

tool_formatters.WebSearch = function(input)
  return string.format("WebSearch %q", input.query or "?")
end

local function format_tool_use(name, input)
  local formatter = tool_formatters[name]
  if formatter then
    local head, detail = formatter(input or {})
    return head, detail
  end
  local ok, encoded = pcall(vim.inspect, input, { newline = " ", indent = "" })
  return name .. " " .. (ok and encoded or ""), nil
end

local function format_tool_result(tool_use_result, content_block)
  if type(tool_use_result) == "table" then
    if tool_use_result.stdout ~= nil or tool_use_result.stderr ~= nil then
      local lines = {}
      if tool_use_result.stdout and tool_use_result.stdout ~= "" then
        local shown, more = truncate_lines(tool_use_result.stdout, MAX_RESULT_LINES)
        vim.list_extend(lines, shown)
        if more then
          lines[#lines + 1] = string.format("… (+%d more lines)", more)
        end
      end
      if tool_use_result.stderr and tool_use_result.stderr ~= "" then
        lines[#lines + 1] = "stderr:"
        local shown = truncate_lines(tool_use_result.stderr, 10)
        vim.list_extend(lines, shown)
      end
      if tool_use_result.interrupted then
        lines[#lines + 1] = "(interrupted)"
      end
      return table.concat(lines, "\n")
    end
    if tool_use_result.file and tool_use_result.file.content then
      local shown, more = truncate_lines(tool_use_result.file.content, 10)
      local suffix = more and string.format("\n… (+%d more lines)", more) or ""
      return table.concat(shown, "\n") .. suffix
    end
    if tool_use_result.type == "create" or tool_use_result.type == "update" then
      return nil -- covered by the Edit/Write tool_use diff already.
    end
  end
  if content_block and type(content_block.content) == "string" then
    local shown, more = truncate_lines(content_block.content, MAX_RESULT_LINES)
    local suffix = more and string.format("\n… (+%d more lines)", more) or ""
    return table.concat(shown, "\n") .. suffix
  end
  return nil
end

--- Render one decoded transcript record into zero or more blocks.
function M.render(event)
  local blocks = {}
  local ts = clock(event.timestamp)
  local etype = event.type

  if etype == "user" or etype == "assistant" then
    local message = event.message
    if type(message) ~= "table" then
      return blocks
    end
    local content = message.content
    if type(content) == "string" then
      content = { { type = "text", text = content } }
    end
    if type(content) ~= "table" then
      return blocks
    end

    for _, c in ipairs(content) do
      if type(c) == "table" then
        if c.type == "text" and c.text and c.text ~= "" then
          local who = message.role == "user" and "you" or "claude"
          blocks[#blocks + 1] = block(message.role, string.format("[%s] %s › %s", ts, who, c.text), event)
        elseif c.type == "thinking" and c.thinking and c.thinking ~= "" then
          blocks[#blocks + 1] = block("thinking", string.format("[%s] (thinking) %s", ts, c.thinking), event)
        elseif c.type == "tool_use" then
          local head, detail = format_tool_use(c.name or "Tool", c.input or {})
          local text = string.format("[%s] → %s", ts, head)
          if detail then
            text = text .. "\n" .. detail
          end
          blocks[#blocks + 1] = block("tool", text, event)
        elseif c.type == "tool_result" then
          local body = format_tool_result(event.toolUseResult, c)
          if body and body ~= "" then
            local prefix = c.is_error and "✗" or "✓"
            blocks[#blocks + 1] = block("result", string.format("[%s] %s %s", ts, prefix, body), event)
          end
        end
      end
    end
  elseif etype == "system" then
    if event.subtype or event.level then
      blocks[#blocks + 1] = block("system", string.format("[%s] system: %s", ts, event.subtype or event.level), event)
    end
  elseif etype == "attachment" then
    local kind = event.attachment and event.attachment.type or "context"
    blocks[#blocks + 1] = block("meta", string.format("[%s] · context update (%s)", ts, kind), event)
  elseif etype == "queue-operation" then
    blocks[#blocks + 1] = block("meta", string.format("[%s] · queue %s", ts, event.operation or ""), event)
  elseif etype == "file-history-snapshot" then
    blocks[#blocks + 1] = block("meta", string.format("[%s] · snapshot", ts), event)
  elseif etype == "ai-title" then
    if event.aiTitle then
      blocks[#blocks + 1] = block("meta", string.format("[%s] · title: %s", ts, event.aiTitle), event)
    end
  end

  return blocks
end

return M
