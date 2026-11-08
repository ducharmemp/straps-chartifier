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

  it("deletes the buffer and closes the new window when opening fails", function()
    local bufs = #vim.api.nvim_list_bufs()
    local wins = #vim.api.nvim_list_wins()
    local bad = { lines = { "x" }, spans = { { row = 5, col_start = 0, col_end = 1, group = "X" } } }
    local ok, err = pcall(view.open, bad, { title = "Broken" })
    assert.is_false(ok)
    assert.is_string(err)
    assert.equals(bufs, #vim.api.nvim_list_bufs())
    assert.equals(wins, #vim.api.nvim_list_wins())
    assert.equals(-1, vim.fn.bufnr("straps://chart/Broken"))
    local b, win = view.open(RENDERED, { title = "Broken" })
    assert.equals("straps://chart/Broken", vim.api.nvim_buf_get_name(b))
    vim.api.nvim_win_close(win, true)
  end)

  it("preserves the current chart when another tab owns the requested name", function()
    local focus = vim.api.nvim_get_current_win()
    local original, win = view.open(RENDERED, { title = "Original" })
    local tab = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabnew")
    local collision, other_win = view.open(RENDERED, { title = "Collision" })
    vim.api.nvim_set_current_tabpage(tab)
    local count = #vim.api.nvim_list_bufs()
    local ok, err = pcall(view.open, RENDERED, { title = "Collision" })
    assert.is_false(ok)
    assert.matches("cannot name the chart buffer", err, 1, true)
    assert.is_true(vim.api.nvim_buf_is_valid(original))
    assert.equals("straps://chart/Original", vim.api.nvim_buf_get_name(original))
    assert.same(RENDERED.lines, vim.api.nvim_buf_get_lines(original, 0, -1, false))
    assert.equals(original, vim.api.nvim_win_get_buf(win))
    assert.equals("Original", vim.wo[win].winbar)
    assert.equals(collision, vim.api.nvim_win_get_buf(other_win))
    assert.equals(count, #vim.api.nvim_list_bufs())
    assert.equals(focus, vim.api.nvim_get_current_win())
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_set_current_win(other_win)
    vim.cmd("tabclose!")
  end)

  it("replaces its own named chart after preparing the candidate", function()
    local focus = vim.api.nvim_get_current_win()
    local original, win = view.open(RENDERED, { title = "Same" })
    local replacement = { lines = { "Changed" }, spans = {} }
    local b, reused = view.open(replacement, { title = "Same" })
    assert.equals(win, reused)
    assert.is_false(vim.api.nvim_buf_is_valid(original))
    assert.equals(b, vim.api.nvim_win_get_buf(win))
    assert.equals("straps://chart/Same", vim.api.nvim_buf_get_name(b))
    assert.same(replacement.lines, vim.api.nvim_buf_get_lines(b, 0, -1, false))
    assert.equals(focus, vim.api.nvim_get_current_win())
    vim.api.nvim_win_close(win, true)
  end)

  it("restores its own name when candidate installation fails", function()
    local original, win = view.open(RENDERED, { title = "Restore" })
    local set_buf = vim.api.nvim_win_set_buf
    vim.api.nvim_win_set_buf = function() error("installation failed") end
    local ok = pcall(view.fill, win, RENDERED, { title = "Restore" })
    vim.api.nvim_win_set_buf = set_buf
    assert.is_false(ok)
    assert.equals(original, vim.api.nvim_win_get_buf(win))
    assert.equals("straps://chart/Restore", vim.api.nvim_buf_get_name(original))
    assert.same(RENDERED.lines, vim.api.nvim_buf_get_lines(original, 0, -1, false))
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
    for i = 1, 8 do
      local hl = vim.api.nvim_get_hl(0, { name = "StrapsChartSeries" .. i })
      assert.is_number(hl.ctermfg, "StrapsChartSeries" .. i)
    end
    vim.api.nvim_set_hl(0, "StrapsChartSeries1", { fg = "#000000" })
    view.define_highlights()
    assert.equals(0, vim.api.nvim_get_hl(0, { name = "StrapsChartSeries1" }).fg)
  end)
end)
