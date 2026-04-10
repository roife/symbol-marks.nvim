vim.opt.runtimepath:append(".")

local api = vim.api
local plugin = require("symbol_marks")
local core = require("symbol_marks.core")
local lualine = require("symbol_marks.lualine")

local function eq(actual, expected, label)
  if actual ~= expected then
    error(
      string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual))
    )
  end
end

local function ok(value, label)
  if not value then error(label) end
end

local function set_buffer(lines, filetype)
  vim.cmd.enew()
  local bufnr = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  if filetype then
    vim.bo[bufnr].filetype = filetype
    pcall(vim.treesitter.start, bufnr, filetype)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, filetype)
    if ok and parser then parser:parse() end
  end
  api.nvim_win_set_cursor(0, { 1, 0 })
  return bufnr
end

local function symbol_entry_for_key(bufnr, key)
  local state = core.get_buf_state(bufnr)
  local ids = state.symbols.ids_by_text[key]
  if not ids then return nil end
  local id = next(ids)
  return id and state.symbols.by_id[id] or nil
end

local function symbol_count_for_key(bufnr, key)
  local state = core.get_buf_state(bufnr)
  local ids = state.symbols.ids_by_text[key]
  if not ids then return 0 end
  local count = 0
  for _ in pairs(ids) do
    count = count + 1
  end
  return count
end

local function mark_counts_for_key(bufnr, key)
  local state = core.get_buf_state(bufnr)
  local ids = state.symbols.ids_by_text[key] or {}
  local counts = {}
  for id in pairs(ids) do
    local symbol = state.symbols.by_id[id]
    counts[#counts + 1] = #api.nvim_buf_get_extmarks(bufnr, symbol.ns_id, 0, -1, {
      type = "highlight",
    })
  end
  table.sort(counts)
  return counts
end

local function marks_for_symbol(bufnr, symbol)
  local entry = symbol_entry_for_key(bufnr, symbol)
  local ns_id = entry and entry.ns_id
  if not ns_id then return {} end
  return api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true, type = "highlight" })
end

local function preview_marks(bufnr)
  local state = core.get_buf_state(bufnr)
  return api.nvim_buf_get_extmarks(bufnr, state.preview.ns_id, 0, -1, { type = "highlight" })
end

local function first_symbol_key(bufnr)
  for key in pairs(core.get_buf_state(bufnr).symbols.ids_by_text) do
    return key
  end
  return nil
end

local function press(keys)
  local termcodes = api.nvim_replace_termcodes(keys, true, false, true)
  api.nvim_feedkeys(termcodes, "x", false)
end

local function toggle_visual(bufnr, keys)
  vim.keymap.set("x", "q", function() plugin.toggle() end, { buffer = bufnr })
  press(keys .. "q")
  vim.keymap.del("x", "q", { buffer = bufnr })
end

local function test_toggle()
  local bufnr = set_buffer {
    "foo = foo + 1",
    "print(foo)",
  }
  plugin.toggle()
  eq(#marks_for_symbol(bufnr, "foo"), 3, "toggle creates extmarks")
end

local function test_navigation()
  local bufnr = set_buffer {
    "foo = foo + 1",
    "print(foo)",
  }
  plugin.toggle()
  press("n")
  local cursor = api.nvim_win_get_cursor(0)
  eq(cursor[1], 1, "jump next line")
  eq(cursor[2], 6, "jump next column")
  press("N")
  cursor = api.nvim_win_get_cursor(0)
  eq(cursor[1], 1, "jump prev line")
  eq(cursor[2], 0, "jump prev column")
  eq(#marks_for_symbol(bufnr, "foo"), 3, "marks stay stable after navigation")
end

local function test_refresh_after_edit()
  local bufnr = set_buffer {
    "foo = foo + bar",
    "print(foo, bar)",
  }
  plugin.toggle()
  api.nvim_win_set_cursor(0, { 1, 12 })
  plugin.toggle()
  local bar_ns_before = symbol_entry_for_key(bufnr, "bar").ns_id
  api.nvim_buf_set_text(bufnr, 0, 0, 0, 3, { "bar" })
  core.refresh(bufnr)
  eq(#marks_for_symbol(bufnr, "foo"), 2, "refresh updates extmarks")
  eq(
    symbol_entry_for_key(bufnr, "bar").ns_id,
    bar_ns_before,
    "refresh keeps unaffected symbol namespace"
  )
  eq(#marks_for_symbol(bufnr, "bar"), 3, "refresh preserves unaffected symbol extmarks")
end

local function test_rename_and_clear()
  local bufnr = set_buffer {
    "foo = foo + 1",
    "print(foo)",
  }
  plugin.toggle()
  plugin.rename("zap")
  eq(#marks_for_symbol(bufnr, "foo"), 0, "rename removes old symbol")
  eq(#marks_for_symbol(bufnr, "zap"), 3, "rename creates new symbol")
  plugin.clear()
  eq(#marks_for_symbol(bufnr, "zap"), 0, "clear removes extmarks")
end

local function test_multiline_visual_toggle()
  local bufnr = set_buffer {
    "alpha",
    "beta",
    "separator",
    "alpha",
    "beta",
  }
  api.nvim_win_set_cursor(0, { 1, 0 })
  toggle_visual(bufnr, "Vj")

  local key = first_symbol_key(bufnr)
  ok(key == "alpha\nbeta", "multiline symbol key exists")
  local marks = marks_for_symbol(bufnr, key)
  eq(#marks, 2, "multiline literal toggle creates spanning extmarks")
  eq(marks[1][2], 0, "first multiline mark starts on row 0")
  eq(marks[1][4].end_row, 1, "first multiline mark ends on row 1")
  eq(marks[2][2], 3, "second multiline mark starts on row 3")
end

local function test_word_boundary_only()
  local bufnr = set_buffer {
    "foo foobar barfoo foo",
    "foo_bar foo",
  }
  plugin.toggle()
  local marks = marks_for_symbol(bufnr, "foo")
  eq(#marks, 3, "word boundary matching ignores substrings and underscored identifiers")
  eq(marks[1][2], 0, "first boundary match row")
  eq(marks[1][3], 0, "first boundary match col")
  eq(marks[2][2], 0, "second boundary match row")
  eq(marks[2][3], 18, "second boundary match col")
  eq(marks[3][2], 1, "third boundary match row")
  eq(marks[3][3], 8, "third boundary match col")
end

local function test_wraparound_navigation_and_edges()
  set_buffer {
    "foo x foo",
    "y foo",
  }
  plugin.toggle()
  plugin.jump_last()
  local cursor = api.nvim_win_get_cursor(0)
  eq(cursor[1], 2, "jump_last moves to last line")
  eq(cursor[2], 2, "jump_last moves to last column")
  plugin.jump_next()
  cursor = api.nvim_win_get_cursor(0)
  eq(cursor[1], 1, "jump_next wraps to first line")
  eq(cursor[2], 0, "jump_next wraps to first column")
  plugin.jump_prev()
  cursor = api.nvim_win_get_cursor(0)
  eq(cursor[1], 2, "jump_prev wraps to last line")
  eq(cursor[2], 2, "jump_prev wraps to last column")
  plugin.jump_first()
  cursor = api.nvim_win_get_cursor(0)
  eq(cursor[1], 1, "jump_first returns to first line")
  eq(cursor[2], 0, "jump_first returns to first column")
end

local function test_toggle_scope()
  local bufnr = set_buffer({
    "local function a()",
    "  print(foo)",
    "end",
    "",
    "local function b()",
    "  print(foo)",
    "end",
  }, "lua")
  api.nvim_win_set_cursor(0, { 2, 8 })
  plugin.toggle()
  eq(#marks_for_symbol(bufnr, "foo"), 2, "buffer scope finds all matches")
  plugin.toggle_scope()
  eq(#marks_for_symbol(bufnr, "foo"), 1, "function scope narrows to the current function")
  plugin.toggle_scope()
  eq(#marks_for_symbol(bufnr, "foo"), 2, "scope toggle restores buffer range")
end

local function test_scope_highlight_stays_in_function_after_head_insert()
  local bufnr = set_buffer({
    "function a()",
    "foo()",
    "end",
    "",
    "function b()",
    "foo()",
    "end",
  }, "lua")

  api.nvim_win_set_cursor(0, { 2, 1 })
  plugin.toggle()
  plugin.toggle_scope()

  local before = marks_for_symbol(bufnr, "foo")
  eq(#before, 1, "function scope highlights only the foo in function a before edit")
  eq(before[1][2], 1, "function scope starts on function a foo row before edit")
  eq(before[1][3], 0, "function scope starts at foo column before edit")

  api.nvim_win_set_cursor(0, { 1, 0 })
  press("i<CR><CR><Up>foo<Esc>")

  local after = marks_for_symbol(bufnr, "foo")
  eq(#after, 1, "function scope keeps only the foo in function a after head insert")
  eq(after[1][2], 3, "function scope shifts with function a foo row after head insert")
  eq(after[1][3], 0, "function scope keeps the same foo column after head insert")
end

local function test_toggle_same_symbol_clears_state()
  local bufnr = set_buffer {
    "foo foo",
  }
  plugin.toggle()
  ok(symbol_entry_for_key(bufnr, "foo") ~= nil, "symbol exists after toggle on")
  plugin.toggle()
  eq(#marks_for_symbol(bufnr, "foo"), 0, "second toggle removes extmarks")
  eq(symbol_entry_for_key(bufnr, "foo"), nil, "second toggle removes namespace mapping")
end

local function test_clear_resets_all_state()
  local bufnr = set_buffer {
    "foo bar foo",
    "bar",
  }
  plugin.toggle()
  api.nvim_win_set_cursor(0, { 1, 4 })
  plugin.toggle()
  local state = core.get_buf_state(bufnr)
  ok(next(state.symbols.by_id) ~= nil, "multiple symbols created")
  plugin.clear()
  state = core.get_buf_state(bufnr)
  eq(next(state.symbols.by_id), nil, "clear removes symbols")
  eq(next(state.symbols.by_ns), nil, "clear removes ns_symbol")
end

local function test_partial_refresh_preserves_unaffected_marks()
  local bufnr = set_buffer {
    "foo",
    "foo",
    "foo",
  }
  plugin.toggle()
  local before = marks_for_symbol(bufnr, "foo")
  local first_id = before[1][1]
  local third_id = before[3][1]
  api.nvim_buf_set_text(bufnr, 1, 0, 1, 3, { "bar" })
  core.refresh(bufnr)
  local after = marks_for_symbol(bufnr, "foo")
  eq(#after, 2, "partial refresh updates affected line only")
  eq(after[1][1], first_id, "partial refresh preserves earlier extmark id")
  eq(after[2][1], third_id, "partial refresh preserves later extmark id")
end

local function test_partial_refresh_preserves_unaffected_multiline_literal()
  local bufnr = set_buffer {
    "alpha",
    "beta",
    "separator",
    "alpha",
    "beta",
  }
  api.nvim_win_set_cursor(0, { 1, 0 })
  toggle_visual(bufnr, "Vj")
  local before = marks_for_symbol(bufnr, "alpha\nbeta")
  local second_id = before[2][1]
  api.nvim_buf_set_text(bufnr, 1, 0, 1, 4, { "gamma" })
  core.refresh(bufnr)
  local after = marks_for_symbol(bufnr, "alpha\nbeta")
  eq(#after, 1, "multiline partial refresh removes only affected literal match")
  eq(after[1][1], second_id, "multiline partial refresh preserves unaffected extmark id")
  eq(after[1][2], 3, "remaining multiline match keeps original row")
end

local function test_visual_preview()
  local bufnr = set_buffer {
    "alpha",
    "beta",
    "separator",
    "alpha",
    "beta",
  }
  plugin.setup {
    preview = {
      enabled = true,
      highlight_single = false,
    },
  }

  api.nvim_win_set_cursor(0, { 1, 0 })
  press("Vj")
  core.refresh_preview(bufnr)

  local marks = preview_marks(bufnr)
  eq(#marks, 2, "visual preview renders both multiline matches")

  press("<Esc>")
  core.on_cursor_moved(bufnr)
  eq(#preview_marks(bufnr), 0, "leaving visual clears preview")

  plugin.setup {
    preview = {
      enabled = false,
    },
  }
end

local function test_insert_preview()
  local bufnr = set_buffer {
    "foo = foo + 1",
    "print(foo)",
  }
  plugin.setup {
    preview = {
      enabled = true,
      highlight_single = false,
    },
  }

  press("i")
  core.refresh_preview(bufnr)

  eq(#preview_marks(bufnr), 3, "insert preview renders visible word matches")

  press("<Esc>")
  core.on_cursor_moved(bufnr)
  eq(#preview_marks(bufnr), 0, "leaving insert clears preview")

  plugin.setup {
    preview = {
      enabled = false,
    },
  }
end

local function test_same_key_can_exist_in_multiple_scopes()
  local bufnr = set_buffer({
    "local function a()",
    "  print(foo)",
    "end",
    "",
    "local function b()",
    "  print(foo)",
    "end",
  }, "lua")
  api.nvim_win_set_cursor(0, { 2, 8 })

  plugin.toggle()
  eq(symbol_count_for_key(bufnr, "foo"), 1, "buffer scope starts with one foo symbol")

  plugin.setup {
    preview = {
      enabled = false,
    },
    scope = { "function" },
  }

  plugin.toggle_scope()
  api.nvim_win_set_cursor(0, { 6, 8 })
  plugin.toggle()
  eq(symbol_count_for_key(bufnr, "foo"), 2, "function scope can coexist with buffer scope")
  eq(
    vim.inspect(mark_counts_for_key(bufnr, "foo")),
    vim.inspect { 1, 2 },
    "foo instances keep separate mark sets"
  )

  plugin.clear()
  plugin.setup {
    preview = {
      enabled = false,
    },
    scope = { "function" },
  }
end

local function test_scope_list_cycles_through_configured_modes()
  local bufnr = set_buffer({
    "local function outer()",
    "  local foo = 1",
    "  if foo then",
    "    print(foo)",
    "  end",
    "end",
  }, "lua")
  plugin.setup {
    preview = {
      enabled = false,
    },
    scope = { "if_statement", "function" },
  }

  api.nvim_win_set_cursor(0, { 4, 10 })
  plugin.toggle()
  eq(#marks_for_symbol(bufnr, "foo"), 3, "buffer scope covers every match")

  plugin.toggle_scope()
  eq(#marks_for_symbol(bufnr, "foo"), 2, "if_statement narrows to the conditional block")

  plugin.toggle_scope()
  eq(#marks_for_symbol(bufnr, "foo"), 3, "function scope expands back to the enclosing function")

  plugin.toggle_scope()
  eq(#marks_for_symbol(bufnr, "foo"), 3, "scope cycle returns to buffer")

  plugin.setup {
    preview = {
      enabled = false,
    },
    scope = { "function" },
  }
end

local function test_unavailable_scope_cycles_back_to_buffer()
  local bufnr = set_buffer({
    "local function only()",
    "  print(foo)",
    "end",
  }, "lua")
  plugin.setup {
    preview = {
      enabled = false,
    },
    scope = { "class", "function" },
  }

  api.nvim_win_set_cursor(0, { 2, 8 })
  plugin.toggle()
  plugin.toggle_scope()
  eq(
    #marks_for_symbol(bufnr, "foo"),
    1,
    "missing first scope skips ahead to the next available scope"
  )
  local symbol = symbol_entry_for_key(bufnr, "foo")
  eq(symbol.scope, 2, "fallback lands on the next available configured mode")

  plugin.setup {
    preview = {
      enabled = false,
    },
    scope = { "function" },
  }
end

local function test_overlap_toggle_prefers_more_specific_scope()
  local bufnr = set_buffer({
    "local function a()",
    "  print(foo)",
    "end",
    "",
    "local function b()",
    "  print(foo)",
    "end",
  }, "lua")
  api.nvim_win_set_cursor(0, { 2, 8 })
  plugin.toggle()
  plugin.toggle_scope()

  api.nvim_win_set_cursor(0, { 6, 8 })
  plugin.toggle()
  eq(
    vim.inspect(mark_counts_for_key(bufnr, "foo")),
    vim.inspect { 1, 2 },
    "two foo scopes overlap on function a"
  )

  api.nvim_win_set_cursor(0, { 2, 8 })
  plugin.toggle()
  eq(symbol_count_for_key(bufnr, "foo"), 1, "toggle removes the more specific scope hit")
  eq(
    vim.inspect(mark_counts_for_key(bufnr, "foo")),
    vim.inspect { 2 },
    "buffer scope remains after removing function scope"
  )
end

local function test_visual_literal_cannot_rename()
  local bufnr = set_buffer {
    "alpha",
    "beta",
    "separator",
    "alpha",
    "beta",
  }

  api.nvim_win_set_cursor(0, { 1, 0 })
  toggle_visual(bufnr, "Vj")

  local before_key = first_symbol_key(bufnr)
  local before_marks = marks_for_symbol(bufnr, before_key)
  local messages = {}
  local original_notify = vim.notify
  vim.notify = function(msg, level) messages[#messages + 1] = { msg = msg, level = level } end

  plugin.rename("gamma")

  vim.notify = original_notify

  eq(first_symbol_key(bufnr), before_key, "visual literal rename leaves symbol key unchanged")
  eq(
    #marks_for_symbol(bufnr, before_key),
    #before_marks,
    "visual literal rename leaves extmarks unchanged"
  )
  eq(#messages, 1, "visual literal rename warns once")
  eq(
    messages[1].msg,
    "SymbolMarksRename only supports word symbols",
    "visual literal rename warning text"
  )
  eq(messages[1].level, vim.log.levels.WARN, "visual literal rename warning level")
end

local function test_lualine_shows_current_over_total()
  set_buffer {
    "foo foo",
    "foo",
  }
  plugin.toggle()

  eq(lualine.has(), true, "lualine.has is true on a mark")
  eq(lualine.get(), "1/3", "lualine.get starts on the first mark")

  plugin.jump_next()
  eq(lualine.get(), "2/3", "lualine.get tracks the second mark")

  plugin.jump_next()
  eq(lualine.get(), "3/3", "lualine.get tracks the last mark")
end

local function test_lualine_hides_off_mark()
  set_buffer {
    "foo x foo",
  }
  plugin.toggle()
  api.nvim_win_set_cursor(0, { 1, 4 })

  eq(lualine.has(), false, "lualine.has is false off a mark")
  eq(lualine.get(), "", "lualine.get is empty off a mark")
end

local function test_lualine_survives_refresh_after_insert()
  local bufnr = set_buffer {
    "foo foo",
    "foo",
  }
  plugin.toggle()
  eq(lualine.get(), "1/3", "lualine starts on the first mark before edit")

  api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, { "x" })
  core.refresh(bufnr)

  api.nvim_win_set_cursor(0, { 1, 5 })
  eq(lualine.has(), true, "lualine.has stays true on the remaining mark after refresh")
  eq(lualine.get(), "1/2", "lualine updates total after refresh")

  plugin.jump_next()
  eq(lualine.has(), true, "lualine.has stays true on the shifted mark after jump")
  eq(lualine.get(), "2/2", "lualine tracks shifted marks after refresh")
end

local function run()
  plugin.setup {
    preview = {
      enabled = false,
    },
  }

  test_toggle()
  test_navigation()
  test_refresh_after_edit()
  test_rename_and_clear()
  test_multiline_visual_toggle()
  test_word_boundary_only()
  test_wraparound_navigation_and_edges()
  test_toggle_scope()
  test_scope_highlight_stays_in_function_after_head_insert()
  test_toggle_same_symbol_clears_state()
  test_clear_resets_all_state()
  test_partial_refresh_preserves_unaffected_marks()
  test_partial_refresh_preserves_unaffected_multiline_literal()
  test_visual_preview()
  test_insert_preview()
  test_same_key_can_exist_in_multiple_scopes()
  test_scope_list_cycles_through_configured_modes()
  test_unavailable_scope_cycles_back_to_buffer()
  test_overlap_toggle_prefers_more_specific_scope()
  test_visual_literal_cannot_rename()
  test_lualine_shows_current_over_total()
  test_lualine_hides_off_mark()
  test_lualine_survives_refresh_after_insert()

  print("tests: ok")
  vim.cmd.quitall { bang = true }
end

local ok_run, err = xpcall(run, debug.traceback)
if not ok_run then
  io.stderr:write(err .. "\n")
  vim.cmd.cquit { count = 1 }
end
