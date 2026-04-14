local api = vim.api

local render = require("symbol_marks.render")
local scope = require("symbol_marks.scope")
local state = require("symbol_marks.state")

local M = {}

local function render_symbol(bufnr, symbol, opts)
  local range = opts and opts.update_range or scope.get_symbol_range(bufnr, symbol)
  if render.render_symbol(bufnr, symbol, range) == 0 then
    M.delete(bufnr, symbol)
    return nil
  end
  return symbol.id
end

function M.delete(bufnr, symbol)
  if not symbol then return end
  local buf_state = state.get_buf_state(bufnr)

  api.nvim_buf_clear_namespace(bufnr, symbol.ns_id, 0, -1)
  state.remove_symbol(buf_state, symbol.id)
end

function M.insert(bufnr, opts)
  local buf_state = state.get_buf_state(bufnr)
  local symbol = vim.tbl_extend("force", {
    id = state.next_symbol_id(),
    ns_id = api.nvim_create_namespace(""),
    style = state.next_style(),
    scope = 0,
    mark_ids = {},
    mark_index_by_id = {},
  }, opts)
  state.insert_symbol(buf_state, symbol)
  return render_symbol(bufnr, symbol)
end

function M.update(bufnr, symbol, opts)
  local buf_state = state.get_buf_state(bufnr)
  local old_text = symbol.text
  local old_scope = symbol.scope

  local updated = vim.tbl_extend("force", {}, symbol, opts or {})

  if updated.text ~= old_text or old_scope ~= updated.scope then
    local ids = buf_state.symbols.ids_by_text[updated.text]
    if ids then
      local symbol_range = scope.get_symbol_range(bufnr, updated)
      for id in pairs(ids) do
        local s = id ~= symbol.id and state.get_symbol(buf_state, id) or nil
        if s and s.scope == updated.scope and scope.get_symbol_range(bufnr, s) == symbol_range then
          M.delete(bufnr, symbol)
          return
        end
      end
    end
  end

  if updated.text ~= old_text then
    state.remove_symbol(buf_state, symbol.id)
    state.insert_symbol(buf_state, updated)
  else
    buf_state.symbols.by_id[updated.id] = updated
  end

  return render_symbol(bufnr, updated, {
    update_range = opts and opts.update_range or nil,
  })
end

function M.refresh(bufnr, dirty)
  local buf_state = state.get_buf_state(bufnr)
  if not dirty then return end
  for _, symbol in pairs(buf_state.symbols.by_id) do
    render.rerender_symbol_range(bufnr, symbol, dirty)
    if #symbol.mark_ids == 0 then M.delete(bufnr, symbol) end
  end
end

return M
