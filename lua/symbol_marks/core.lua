local api = vim.api
local fn = vim.fn

local helper = require("symbol_marks.helper")
local preview = require("symbol_marks.preview")
local render = require("symbol_marks.render")
local scope = require("symbol_marks.scope")
local state = require("symbol_marks.state")
local symbols = require("symbol_marks.symbols")

local M = {}

function M.configure(opts) return state.configure(opts) end

local function ensure_refresh_attached(bufnr)
  local buf_state = state.get_buf_state(bufnr)

  if not buf_state.refresh.attached then
    api.nvim_buf_attach(bufnr, false, {
      on_bytes = function(_, buf, _, start_row, _, _, old_end_row, _, _, new_end_row, _)
        local refresh = state.get_buf_state(buf).refresh
        local end_row = start_row + math.max(old_end_row, new_end_row)
        refresh.dirty = refresh.dirty or { start_row = start_row, end_row = end_row }
        refresh.dirty.start_row = math.min(refresh.dirty.start_row, start_row)
        refresh.dirty.end_row = math.max(refresh.dirty.end_row, end_row)
      end,
      on_detach = function(_, buf)
        preview.close_timer(buf)
        state.drop_buf_state(buf)
      end,
    })
    buf_state.refresh.attached = true
  end
end

function M.toggle()
  local bufnr = api.nvim_get_current_buf()
  ensure_refresh_attached(bufnr)
  local text, kind = helper.get_text_and_kind()
  if not text then return end

  local hit = render.cursor_hit(bufnr)
  if hit then
    symbols.delete(bufnr, hit.symbol)
    return
  end

  symbols.insert(bufnr, {
    text = text,
    kind = kind,
  })
end

function M.clear()
  local bufnr = api.nvim_get_current_buf()
  preview.clear(bufnr)
  local symbols_by_id = state.get_buf_state(bufnr).symbols.by_id
  for _, symbol in pairs(symbols_by_id) do
    symbols.delete(bufnr, symbol)
  end
end

function M.refresh(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local buf_state = state.get_buf_state(bufnr)
  if buf_state.refresh.suspended then return end

  preview.clear(bufnr)
  local dirty = buf_state.refresh.dirty
  buf_state.refresh.dirty = nil
  symbols.refresh(bufnr, dirty)
end

function M.jump(step, boundary)
  local bufnr = api.nvim_get_current_buf()
  local hit = render.cursor_hit(bufnr)
  if not hit then
    if not boundary then vim.cmd.normal { args = { step > 0 and "n" or "N" }, bang = true } end
    return
  end

  local end_ = step > 0 and -1 or 0
  local ns_id = hit.symbol.ns_id

  local mark
  if not boundary then
    local start = hit.mark[1]
    mark =
      api.nvim_buf_get_extmarks(bufnr, ns_id, start, end_, { limit = 2, type = "highlight" })[2]
  end
  mark = mark
    or api.nvim_buf_get_extmarks(bufnr, ns_id, -1 - end_, end_, { limit = 1, type = "highlight" })[1]

  api.nvim_win_set_cursor(0, { mark[2] + 1, mark[3] })
end

function M.toggle_scope()
  local bufnr = api.nvim_get_current_buf()
  local hit = render.cursor_hit(bufnr)
  if not hit then return end

  local symbol = hit.symbol

  local next_mode = (symbol.scope + 1) % (state.SCOPE_COUNT + 1)
  local scope_mode, range = scope.resolve_mode(bufnr, next_mode, nil)
  if scope_mode == symbol.scope then return end

  symbols.update(bufnr, symbol, { scope = scope_mode, update_range = range })
end

function M.rename(new_name)
  local bufnr = api.nvim_get_current_buf()
  local hit = render.cursor_hit(bufnr)
  if not hit then return end

  local symbol = hit.symbol
  if symbol.kind ~= helper.KIND.WORD then
    vim.notify("SymbolMarksRename only supports word symbols", vim.log.levels.WARN)
    return
  end

  local buf_state = state.get_buf_state(bufnr)
  new_name = new_name or fn.input("Rename to: ", symbol.text)
  if new_name == "" or new_name == symbol.text then return end

  local marks = api.nvim_buf_get_extmarks(bufnr, symbol.ns_id, 0, -1, {
    details = true,
    type = "highlight",
  })

  buf_state.refresh.suspended = true
  for i = #marks, 1, -1 do
    local mark = marks[i]
    local details = mark[4]
    api.nvim_buf_set_text(bufnr, mark[2], mark[3], details.end_row, details.end_col, { new_name })
  end
  buf_state.refresh.suspended = false

  symbols.update(bufnr, symbol, { text = new_name })
end

M.on_cursor_moved = preview.on_cursor_moved
M.refresh_preview = preview.refresh
M.on_leave = preview.on_leave

function M.on_wipeout(bufnr)
  preview.close_timer(bufnr)
  state.drop_buf_state(bufnr)
end

function M.get_buf_state(bufnr) return state.get_buf_state(bufnr or api.nvim_get_current_buf()) end

return M
