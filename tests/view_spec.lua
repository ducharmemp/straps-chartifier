-- Run: busted tests/view_spec.lua

dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")

local view = require("straps_chartifier.view")

local RENDERED = {
  lines = { "Title", "a │██ 2", "b │█  1" },
  spans = {
    { row = 0, col_start = 0, col_end = 5, group = "StrapsChartTitle" },
    { row = 1, col_start = #"a │", col_end = #"a │██", group = "StrapsChartSeries1" },
    { row = 2, col_start = #"b │", col_end = #"b │█", group = "StrapsChartSeries2" },
  },
}

local ns = vim.api.nvim_create_namespace(view.NAMESPACE)

local function marks(b)
  return vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, { details = true })
end

describe("view.open", function()
  it("opens a scratch buffer in a new vertical split without moving focus", function()
    local before_win = vim.api.nvim_get_current_win()
    local before_count = #vim.api.nvim_list_wins()
    local b, win = view.open(RENDERED, { title = "Title" })
    assert.equals(before_win, vim.api.nvim_get_current_win())
    assert.equals(before_count + 1, #vim.api.nvim_list_wins())
    assert.equals(b, vim.api.nvim_win_get_buf(win))
    assert.equals("nofile", vim.bo[b].buftype)
    assert.equals("wipe", vim.bo[b].bufhidden)
    assert.is_false(vim.bo[b].modifiable)
    assert.equals(view.FILETYPE, vim.bo[b].filetype)
    assert.same(RENDERED.lines, vim.api.nvim_buf_get_lines(b, 0, -1, false))
    assert.equals("straps://chart/Title", vim.api.nvim_buf_get_name(b))
    assert.equals("Title", vim.wo[win].winbar)
    assert.is_false(vim.wo[win].wrap)
    assert.equals("row", vim.fn.winlayout()[1])
    vim.api.nvim_win_close(win, true)
  end)

  it("places one extmark per span with the span's group and byte range", function()
    local b, win = view.open(RENDERED, {})
    local got = marks(b)
    assert.equals(#RENDERED.spans, #got)
    for i, m in ipairs(got) do
      local sp = RENDERED.spans[i]
      assert.equals(sp.row, m[2])
      assert.equals(sp.col_start, m[3])
      assert.equals(sp.col_end, m[4].end_col)
      assert.equals(sp.group, m[4].hl_group)
    end
    vim.api.nvim_win_close(win, true)
  end)

  it("skips extmarks when highlight is false", function()
    local b, win = view.open(RENDERED, { highlight = false })
    assert.equals(0, #marks(b))
    vim.api.nvim_win_close(win, true)
  end)

  it("opens a horizontal split on request", function()
    local _, win = view.open(RENDERED, { split = "horizontal" })
    local layout = vim.fn.winlayout()
    assert.equals("col", layout[1])
    assert.equals(win, layout[2][#layout[2]][2])
    vim.api.nvim_win_close(win, true)
  end)

  it("defines the highlight groups with default so a colorscheme can override them", function()
    view.open(RENDERED, {})
    for i = 1, 8 do
      local hl = vim.api.nvim_get_hl(0, { name = "StrapsChartSeries" .. i })
      assert.is_not_nil(hl.fg, "StrapsChartSeries" .. i)
    end
    assert.equals("Comment", vim.api.nvim_get_hl(0, { name = "StrapsChartAxis" }).link)
    assert.equals("DiffAdd", vim.api.nvim_get_hl(0, { name = "StrapsChartPositive" }).link)
    assert.equals("DiffDelete", vim.api.nvim_get_hl(0, { name = "StrapsChartNegative" }).link)
    assert.equals("Title", vim.api.nvim_get_hl(0, { name = "StrapsChartTitle" }).link)
    vim.api.nvim_set_hl(0, "StrapsChartSeries1", { fg = "#000000" })
    view.define_highlights()
    assert.equals(0, vim.api.nvim_get_hl(0, { name = "StrapsChartSeries1" }).fg)
  end)
end)
