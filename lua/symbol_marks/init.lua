local core = require("symbol_marks.core")
local api = vim.api

local M = {}
local PREVIEW_HL_GROUP = "SymbolMarksPreview"
local group = api.nvim_create_augroup("SymbolMarks", { clear = true })

local configured = false

M.lualine = require("symbol_marks.lualine")

M.jump_first = function() core.jump(1, true) end
M.jump_last = function() core.jump(-1, true) end
M.jump_next = function() core.jump(1, false) end
M.jump_prev = function() core.jump(-1, false) end

M.toggle = core.toggle
M.clear = core.clear
M.toggle_scope = core.toggle_scope
M.rename = core.rename

local function ensure_highlights(config)
  for i, color in ipairs(config.colors) do
    api.nvim_set_hl(0, "SymbolMarks" .. i, { fg = color, reverse = true })
  end
  api.nvim_set_hl(0, PREVIEW_HL_GROUP, { link = "Visual" })
end

local function register_user_commands()
  local commands = {
    { name = "SymbolMarksToggle", handler = M.toggle },
    { name = "SymbolMarksClear", handler = M.clear },
    { name = "SymbolMarksNext", handler = M.jump_next },
    { name = "SymbolMarksPrev", handler = M.jump_prev },
    { name = "SymbolMarksFirst", handler = M.jump_first },
    { name = "SymbolMarksLast", handler = M.jump_last },
    { name = "SymbolMarksToggleScope", handler = M.toggle_scope },
    { name = "SymbolMarksRename", handler = M.rename },
  }
  for _, command in ipairs(commands) do
    api.nvim_create_user_command(command.name, command.handler, command.opts or {})
  end
end

local function register_autocmds()
  api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function(args) core.on_cursor_moved(args.buf) end,
  })
  api.nvim_create_autocmd("ModeChanged", {
    group = group,
    callback = function(args) core.on_cursor_moved(args.buf) end,
  })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function(args) core.refresh(args.buf) end,
  })
  api.nvim_create_autocmd("BufLeave", {
    group = group,
    callback = function(args) core.on_leave(args.buf) end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args) core.on_wipeout(args.buf) end,
  })
end

local function register_keymaps()
  vim.keymap.set("n", "n", M.jump_next, { silent = true, desc = "SymbolMarks Next" })
  vim.keymap.set("n", "N", M.jump_prev, { silent = true, desc = "SymbolMarks Prev" })
end

function M.setup(opts)
  local config = core.configure(opts)
  if not configured then
    ensure_highlights(config)
    register_user_commands()
    register_autocmds()
    register_keymaps()
    configured = true
  end
  return M
end

return M
