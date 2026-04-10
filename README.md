# symbol-marks.nvim

Extmarks-based symbol highlighting for Neovim.

The plugin combines the useful parts of `symbol-overlay` and `interestingwords.nvim`:

- multiple pinned symbols at the same time
- idle preview highlight
- forced `n` / `N` navigation for the active symbol

## Status

Implemented:

- toggle current word
- clear all
- next / prev / first / last
- scope toggle
- rename
- preview highlight

## Install

With `lazy.nvim`:

```lua
{
  "roife/symbol-marks.nvim"
  config = function()
    require("symbol_marks").setup()
  end,
}
```

## Setup

```lua
require("symbol_marks").setup({
  colors = { "#aeee00", "#ff0000", "#0000ff", "#b88823" },
  preview = {
    enabled = true,
    highlight_single = false,
  },
  scope = { "function" },
})
```

- Preview timing follows Neovim's `updatetime`.
- Preview highlighting always uses the internal `SymbolMarksPreview` highlight group.

## Default Mappings

- `n`: next match for active symbol
- `N`: previous match for active symbol

## Commands

- `:SymbolMarksToggle`
- `:SymbolMarksClear`
- `:SymbolMarksNext`
- `:SymbolMarksPrev`
- `:SymbolMarksFirst`
- `:SymbolMarksLast`
- `:SymbolMarksToggleScope`
- `:SymbolMarksRename`

## lualine

Show the current match index and total matches when the cursor is on a mark:

```lua
local symbol_marks = require("symbol_marks")

require("lualine").setup({
  sections = {
    lualine_c = {
      {
        symbol_marks.lualine.get,
        cond = symbol_marks.lualine.has,
      },
    },
  },
})
```

## Test

```sh
nvim --headless -u NONE -c "set rtp+=." -l tests/run.lua
```
