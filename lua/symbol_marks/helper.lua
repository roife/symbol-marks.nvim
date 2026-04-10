local api = vim.api
local fn = vim.fn

local M = {}

M.KIND = {
  WORD = 1,
  LITERAL = 2,
}

function M.cmp_pos(a_row, a_col, b_row, b_col)
  if a_row ~= b_row then return a_row < b_row and -1 or 1 end
  if a_col ~= b_col then return a_col < b_col and -1 or 1 end
  return 0
end

function M.lower_bound(items, is_before)
  local left, right = 1, #items + 1
  while left < right do
    local mid = math.floor((left + right) / 2)
    if is_before(items[mid], mid) then
      left = mid + 1
    else
      right = mid
    end
  end
  return left
end

M.matchers = {
  [M.KIND.WORD] = {
    pattern = function(text)
      local case_prefix = vim.o.ignorecase
          and (not vim.o.smartcase or fn.match(text, [[\u]]) == -1)
          and [[\c]]
        or [[\C]]
      return case_prefix .. [[\V\<]] .. fn.escape(text, [[\]]) .. [[\>]]
    end,
    line_span = function() return 1 end,
    overlap = false,
  },
  [M.KIND.LITERAL] = {
    pattern = function(text) return text end,
    line_span = function(text)
      local _, count = text:gsub("\n", "\n")
      return count + 1
    end,
    overlap = true,
  },
}

function M.is_visual_mode(mode) return mode == "v" or mode == "V" end

function M.is_preview_mode(mode)
  return mode == "n" or mode:sub(1, 1) == "i" or M.is_visual_mode(mode)
end

function M.get_visual_selection()
  local mode = api.nvim_get_mode().mode
  if not M.is_visual_mode(mode) then return nil end

  local start_pos = fn.getpos("v")
  local end_pos = fn.getpos(".")
  local start_row, start_col = start_pos[2] - 1, start_pos[3] - 1
  local end_row, end_col = end_pos[2] - 1, end_pos[3] - 1

  if M.cmp_pos(end_row, end_col, start_row, start_col) < 0 then
    start_row, end_row = end_row, start_row
    start_col, end_col = end_col, start_col
  end

  if mode == "V" then
    start_col = 0
    end_col = #api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1]
  else
    end_col = end_col + 1
  end

  local text = api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  return #text == 0 and nil or table.concat(text, "\n")
end

function M.get_text_and_kind()
  local mode = api.nvim_get_mode().mode
  if M.is_visual_mode(mode) then return M.get_visual_selection(), M.KIND.LITERAL end
  local word = fn.expand("<cword>")
  return (word ~= "" and word or nil), M.KIND.WORD
end

return M
