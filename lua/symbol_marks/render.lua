local api = vim.api
local MAX_COL = vim.v.maxcol

local helper = require("symbol_marks.helper")
local scope = require("symbol_marks.scope")
local state = require("symbol_marks.state")

local M = {}

local function offset_to_pos(line_starts, lines, offset)
  local idx = helper.lower_bound(line_starts, function(start) return start < offset + 1 end) - 1
  idx = math.max(idx, 1)
  local row = idx - 1
  return row, math.min(offset - line_starts[idx], #lines[idx])
end

local function set_mark_ids(symbol, mark_ids)
  symbol.mark_ids = mark_ids
  symbol.mark_index_by_id = {}
  for i, id in ipairs(mark_ids) do
    symbol.mark_index_by_id[id] = i
  end
end

local function replace_mark_ids(symbol, start_idx, end_idx, new_ids)
  local mark_ids = symbol.mark_ids
  local mark_index_by_id = symbol.mark_index_by_id
  local old_count = #mark_ids
  local old_len = end_idx - start_idx + 1
  local new_len = #new_ids
  local new_count = old_count + new_len - old_len

  for i = start_idx, end_idx do
    mark_index_by_id[mark_ids[i]] = nil
  end

  if new_len ~= old_len and end_idx < old_count then
    table.move(mark_ids, end_idx + 1, old_count, start_idx + new_len)
  end

  for i, id in ipairs(new_ids) do
    local idx = start_idx + i - 1
    mark_ids[idx] = id
    mark_index_by_id[id] = idx
  end

  for i = new_count + 1, old_count do
    mark_ids[i] = nil
  end

  for i = start_idx + new_len, new_count do
    mark_index_by_id[mark_ids[i]] = i
  end
end

local function find_prev_mark(bufnr, symbol, row)
  return api.nvim_buf_get_extmarks(bufnr, symbol.ns_id, { row, 0 }, 0, { limit = 1, type = "highlight" })[1]
end

function M.render_matches(bufnr, symbol, start_row, end_row)
  local lines = api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  if #lines == 0 then return {} end

  local line_starts, offset = {}, 0
  for idx, line in ipairs(lines) do
    line_starts[idx] = offset
    offset = offset + #line + (idx < #lines and 1 or 0)
  end

  local mark_ids, cursor = {}, 0
  local priority = vim.hl.priorities.user + symbol.scope
  local is_literal = symbol.kind == helper.KIND.LITERAL
  local text = table.concat(lines, "\n")
  local pattern = helper.matchers[symbol.kind].pattern(symbol.text)
  local regex = not is_literal and vim.regex(pattern) or nil
  while true do
    local start_offset, end_offset
    if is_literal then
      local start_idx, end_idx = text:find(pattern, cursor + 1, true)
      if not start_idx then break end
      start_offset, end_offset = start_idx - 1, end_idx
    else
      local start_idx, end_idx = regex:match_str(text:sub(cursor + 1))
      if not start_idx then break end
      start_offset = cursor + start_idx
      end_offset = cursor + end_idx
    end

    local local_start_row, start_col = offset_to_pos(line_starts, lines, start_offset)
    local local_end_row, end_col = offset_to_pos(line_starts, lines, end_offset)
    local mark_start_row = start_row + local_start_row
    local mark_end_row = start_row + local_end_row
    local mark_id = api.nvim_buf_set_extmark(bufnr, symbol.ns_id, mark_start_row, start_col, {
      end_row = mark_end_row,
      end_col = end_col,
      hl_group = symbol.style,
      invalidate = true,
      priority = priority,
    })
    mark_ids[#mark_ids + 1] = mark_id
    cursor = math.max(end_offset, start_offset + 1)
  end

  return mark_ids
end

function M.render_symbol(bufnr, symbol, range)
  api.nvim_buf_clear_namespace(bufnr, symbol.ns_id, 0, -1)
  local mark_ids = M.render_matches(bufnr, symbol, range[1], range[2])
  set_mark_ids(symbol, mark_ids)
  return #mark_ids
end

function M.rerender_symbol_range(bufnr, symbol, dirty)
  local matcher = helper.matchers[symbol.kind]
  local padding = matcher.line_span(symbol.text) - 1
  local range = scope.get_symbol_range(bufnr, symbol)
  local start_row = math.max(range[1], dirty.start_row - padding)
  local end_row = math.min(range[2], dirty.end_row + padding)
  if end_row < start_row then return end

  local old_marks =
    api.nvim_buf_get_extmarks(bufnr, symbol.ns_id, { start_row, 0 }, { end_row, MAX_COL }, {
      overlap = true,
      type = "highlight",
    })

  local start_idx = 1
  local end_idx = 0
  if #old_marks > 0 then
    start_idx = symbol.mark_index_by_id[old_marks[1][1]]
    end_idx = symbol.mark_index_by_id[old_marks[#old_marks][1]]
    for _, mark in ipairs(old_marks) do
      api.nvim_buf_del_extmark(bufnr, symbol.ns_id, mark[1])
    end
  else
    local prev = find_prev_mark(bufnr, symbol, start_row)
    start_idx = prev and symbol.mark_index_by_id[prev[1]] + 1 or 1
    end_idx = start_idx - 1
  end

  replace_mark_ids(symbol, start_idx, end_idx, M.render_matches(bufnr, symbol, start_row, end_row))
end

function M.cursor_hit(bufnr)
  local buf_state = state.peek_buf_state(bufnr)
  if not buf_state then return nil end
  local cursor = api.nvim_win_get_cursor(0)
  local pos = { cursor[1] - 1, cursor[2] }
  local extmarks = api.nvim_buf_get_extmarks(bufnr, -1, pos, pos, {
    details = true,
    overlap = true,
    type = "highlight",
  })

  local best_symbol, best_mark
  for _, mark in ipairs(extmarks) do
    local id = buf_state.symbols.by_ns[mark[4].ns_id]
    local symbol = state.get_symbol(buf_state, id)
    if symbol and (not best_symbol or symbol.scope > best_symbol.scope) then
      best_symbol = symbol
      best_mark = mark
    end
  end
  return best_symbol and { symbol = best_symbol, mark = best_mark } or nil
end

return M
