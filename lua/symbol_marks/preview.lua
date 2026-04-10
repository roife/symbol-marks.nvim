local api = vim.api
local fn = vim.fn
local uv = vim.uv or vim.loop

local helper = require("symbol_marks.helper")
local render = require("symbol_marks.render")
local state = require("symbol_marks.state")

local M = {}
local PREVIEW_HL_GROUP = "SymbolMarksPreview"

local function stop_timer(buf_state)
  if buf_state.preview.timer then buf_state.preview.timer:stop() end
end

function M.clear(bufnr)
  local buf_state = state.get_buf_state(bufnr)
  api.nvim_buf_clear_namespace(bufnr, buf_state.preview.ns_id, 0, -1)
end

function M.refresh(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local buf_state = state.get_buf_state(bufnr)
  M.clear(bufnr)
  if not state.config.preview.enabled or not helper.is_preview_mode(fn.mode()) then return end

  local text, kind = helper.get_text_and_kind()
  if not text or render.cursor_hit(bufnr) then return end

  local start_row, end_row = fn.line("w0") - 1, fn.line("w$") - 1
  local symbol = {
    text = text,
    kind = kind,
    ns_id = buf_state.preview.ns_id,
    style = PREVIEW_HL_GROUP,
    scope = 0,
  }
  local matches = render.render_symbol(bufnr, symbol, { start_row, end_row })
  if matches <= 1 and not state.config.preview.highlight_single then M.clear(bufnr) end
end

function M.restart_timer(bufnr)
  local buf_state = state.get_buf_state(bufnr)
  if not state.config.preview.enabled or not helper.is_preview_mode(fn.mode()) then return end

  if not buf_state.preview.timer then buf_state.preview.timer = uv.new_timer() end
  stop_timer(buf_state)
  buf_state.preview.timer:start(
    vim.o.updatetime,
    0,
    vim.schedule_wrap(function()
      if api.nvim_buf_is_valid(bufnr) then M.refresh(bufnr) end
    end)
  )
end

function M.on_cursor_moved(bufnr)
  M.clear(bufnr)
  M.restart_timer(bufnr)
end

function M.on_leave(bufnr)
  local buf_state = state.get_buf_state(bufnr)
  stop_timer(buf_state)
  M.clear(bufnr)
end

function M.close_timer(bufnr)
  local buf_state = state.peek_buf_state(bufnr)
  if buf_state and buf_state.preview.timer then
    stop_timer(buf_state)
    buf_state.preview.timer:close()
  end
end

return M
