local api = vim.api

local buffers = {}
local next_style = 1
local next_symbol_id = 1

local DEFAULT_CONFIG = {
  colors = { "#aeee00", "#ff0000", "#0000ff", "#b88823", "#ffa724", "#ff2c4b" },
  preview = {
    enabled = true,
    highlight_single = false,
  },
  scope = { "function" },
}

local M = {
  config = nil,
}

function M.configure(opts)
  local config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_CONFIG), opts)
  if opts.scope then config.scope = opts.scope end
  if opts.colors then config.colors = opts.colors end
  M.config = config
  M.SCOPE_COUNT = #(config.scope or {})
  return M.config
end

function M.get_buf_state(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  local buf_state = buffers[bufnr]
  if buf_state then return buf_state end

  buf_state = {
    symbols = {
      by_id = {},
      ids_by_text = {},
      by_ns = {},
    },
    preview = {
      ns_id = api.nvim_create_namespace(""),
      timer = nil,
    },
    refresh = {
      suspended = false,
      dirty = nil,
      attached = false,
    },
  }
  buffers[bufnr] = buf_state
  return buf_state
end

function M.peek_buf_state(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  return buffers[bufnr]
end

function M.drop_buf_state(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  buffers[bufnr] = nil
end

function M.next_symbol_id()
  local id = next_symbol_id
  next_symbol_id = next_symbol_id + 1
  return id
end

function M.get_symbol(buf_state, id) return id and buf_state.symbols.by_id[id] or nil end

function M.insert_symbol(buf_state, symbol)
  buf_state.symbols.by_id[symbol.id] = symbol
  buf_state.symbols.by_ns[symbol.ns_id] = symbol.id

  local ids = buf_state.symbols.ids_by_text[symbol.text] or {}
  buf_state.symbols.ids_by_text[symbol.text] = ids
  ids[symbol.id] = true
end

function M.remove_symbol(buf_state, id)
  local symbol = M.get_symbol(buf_state, id)
  if not symbol then return nil end

  buf_state.symbols.by_id[id] = nil
  buf_state.symbols.by_ns[symbol.ns_id] = nil

  local ids = buf_state.symbols.ids_by_text[symbol.text]
  if ids then
    ids[id] = nil
    if next(ids) == nil then buf_state.symbols.ids_by_text[symbol.text] = nil end
  end

  return symbol
end

function M.next_style()
  local group = "SymbolMarks" .. next_style
  next_style = next_style % #M.config.colors + 1
  return group
end

return M
