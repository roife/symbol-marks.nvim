local api = vim.api

local state = require("symbol_marks.state")

local M = {}

function M.get_symbol_range(bufnr, symbol)
  local marks = api.nvim_buf_get_extmarks(bufnr, symbol.ns_id, 0, -1, {
    limit = 1,
    type = "highlight",
  })
  local pos = marks[1] and { marks[1][2], marks[1][3] } or nil
  local _, range = M.resolve_mode(bufnr, symbol.scope, pos)
  return range
end

local function node_matches(node_type, mode)
  local name = (state.config.scope or {})[mode]

  if name == "function" then
    local is_function_like = node_type:find("function", 1, true) ~= nil
      or node_type:find("method", 1, true) ~= nil
    return is_function_like and node_type:find("call", 1, true) == nil
  end
  return node_type:find(name, 1, true) ~= nil
end

function M.resolve_mode(bufnr, mode, pos)
  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr)
  if ok_parser and parser then parser:parse() end

  local ok_node, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = pos })

  local current = mode
  while true do
    if current == 0 then return current, { 0, api.nvim_buf_line_count(bufnr) - 1 } end

    if ok_node and node then
      local candidate = node
      while candidate do
        local node_type = candidate:type()
        if node_matches(node_type, current) then
          local start_row, _, end_row = candidate:range()
          return current, { start_row, end_row }
        end
        candidate = candidate:parent()
      end
    end

    current = (current + 1) % (state.SCOPE_COUNT + 1)
  end
end

return M
