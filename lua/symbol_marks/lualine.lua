local api = vim.api

local render = require("symbol_marks.render")

local M = {}

local function current_status(bufnr)
  local hit = render.cursor_hit(bufnr)
  if not hit then return nil end

  local current = hit.symbol.mark_index_by_id[hit.mark[1]]
  return current, #hit.symbol.mark_ids
end

function M.get(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local current, total = current_status(bufnr)
  if not current then return "" end
  return string.format("%d/%d", current, total)
end

function M.has(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  return current_status(bufnr) ~= nil
end

return M
