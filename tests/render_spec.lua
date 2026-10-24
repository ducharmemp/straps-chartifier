-- Run: busted tests/render_spec.lua

dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")

local render = require("straps_chartifier.render")

local CONFIG = { max_width = 100, height = 8, max_bars = 60 }

local function spec(input)
  local s, err = render.normalize(input, CONFIG)
  assert(s, err)
  return s
end

local function draw(input)
  return render.render(spec(input))
end

local function span_text(out, sp)
  return out.lines[sp.row + 1]:sub(sp.col_start + 1, sp.col_end)
end

describe("normalize", function()
  it("rejects an unknown kind, naming the kinds", function()
    local s, err = render.normalize({ kind = "pie", labels = { "a" }, series = { { values = { 1 } } } }, CONFIG)
    assert.is_nil(s)
    assert.matches("kind must be one of bar, stacked, diverging, column, stacked_column, line, scatter, sparkline,"
      .. " histogram %(got pie%)", err)
  end)

  it("rejects missing or empty series and labels", function()
    local _, err = render.normalize({ kind = "bar", labels = { "a" } }, CONFIG)
    assert.matches("series must be a non%-empty array", err)
    _, err = render.normalize({ kind = "bar", series = { { values = { 1 } } } }, CONFIG)
    assert.matches("labels must be a non%-empty array", err)
    _, err = render.normalize({ kind = "bar", labels = {}, series = { { values = {} } } }, CONFIG)
    assert.matches("labels must be a non%-empty array", err)
  end)

  it("rejects non-number values with their position", function()
    local _, err = render.normalize({ kind = "bar", labels = { "a", "b" }, series = { { values = { 1, "2" } } } },
      CONFIG)
    assert.equals('series[1].values[2] is "2", expected a finite number', err)
    _, err = render.normalize({ kind = "bar", labels = { "a" }, series = { { values = { 0 / 0 } } } }, CONFIG)
    assert.matches("series%[1%].values%[1%] is", err)
    _, err = render.normalize({ kind = "line", labels = { "a" }, series = { { values = { math.huge } } } }, CONFIG)
    assert.equals("series[1].values[1] is inf, expected a finite number", err)
    _, err = render.normalize({ kind = "line", labels = { "a" }, series = { { values = { -math.huge } } } }, CONFIG)
    assert.equals("series[1].values[1] is -inf, expected a finite number", err)
  end)

  it("rejects a length mismatch between labels and values", function()
    local _, err = render.normalize({ kind = "line", labels = { "a", "b" }, series = { { values = { 1 } } } },
      CONFIG)
    assert.equals("series[1] has 1 values but there are 2 labels", err)
  end)

  it("rejects non-string labels", function()
    local _, err = render.normalize({ kind = "bar", labels = { "a", 2 }, series = { { values = { 1, 1 } } } },
      CONFIG)
    assert.equals("labels[2] is number, expected a string", err)
  end)

  it("caps the label count at max_bars", function()
    local labels, values = {}, {}
    for i = 1, 61 do
      labels[i] = tostring(i)
      values[i] = i
    end
    local _, err = render.normalize({ kind = "bar", labels = labels, series = { { values = values } } }, CONFIG)
    assert.equals("61 labels exceed max_bars=60; aggregate the data or raise max_bars", err)
    assert.is_truthy(render.normalize({ kind = "bar", labels = labels, series = { { values = values } } },
      { max_bars = 61 }))
  end)

  it("rejects negative values for the non-negative kinds and names the alternatives", function()
    for _, kind in ipairs({ "bar", "stacked", "column", "stacked_column" }) do
      local _, err = render.normalize({ kind = kind, labels = { "a" }, series = { { values = { -3 } } } }, CONFIG)
      assert.equals(kind .. " charts take values >= 0 (found -3); use diverging, line or sparkline for negative data",
        err)
    end
    for _, kind in ipairs({ "diverging", "line", "sparkline" }) do
      assert.is_truthy(render.normalize({ kind = kind, labels = { "a" }, series = { { values = { -3 } } } },
        CONFIG))
    end
  end)

  it("scatter needs an x array per series as long as values, and no labels", function()
    local s = spec({ kind = "scatter", x_unit = "KB", series = { { x = { 1, 2 }, values = { 3, 4 } } } })
    assert.same({ 1, 2 }, s.series[1].x)
    assert.equals("KB", s.x_unit)
    assert.is_nil(s.labels)
    local _, err = render.normalize({ kind = "scatter", series = { { values = { 3, 4 } } } }, CONFIG)
    assert.equals("series[1] needs an x array as long as values (scatter plots x against values)", err)
    _, err = render.normalize({ kind = "scatter", series = { { x = { 1 }, values = { 3, 4 } } } }, CONFIG)
    assert.equals("series[1] needs an x array as long as values (scatter plots x against values)", err)
    _, err = render.normalize({ kind = "scatter", series = { { x = { 1, "2" }, values = { 3, 4 } } } }, CONFIG)
    assert.equals('series[1].x[2] is "2", expected a finite number', err)
    _, err = render.normalize({ kind = "scatter", series = { { x = {}, values = {} } } }, CONFIG)
    assert.equals("series[1] has no points", err)
  end)

  it("diverging takes exactly one series", function()
    local _, err = render.normalize({ kind = "diverging", labels = { "a" },
      series = { { values = { 1 } }, { values = { 2 } } } }, CONFIG)
    assert.equals("diverging takes exactly one series; pass the delta per label", err)
  end)

  it("validates sort and split", function()
    local base = { kind = "bar", labels = { "a" }, series = { { values = { 1 } } } }
    local _, err = render.normalize(vim.tbl_extend("force", base, { sort = "up" }), CONFIG)
    assert.equals('sort must be "none", "asc" or "desc"', err)
    _, err = render.normalize(vim.tbl_extend("force", base, { split = "diagonal" }), CONFIG)
    assert.equals('split must be "vertical" or "horizontal"', err)
    assert.equals("horizontal", spec(vim.tbl_extend("force", base, { split = "horizontal" })).split)
    assert.is_nil(spec(base).split)
  end)

  it("sorts labels and every series by the first series", function()
    local s = spec({
      kind = "bar", sort = "desc", labels = { "a", "b", "c" },
      series = { { values = { 2, 9, 5 } }, { values = { 20, 90, 50 } } },
    })
    assert.same({ "b", "c", "a" }, s.labels)
    assert.same({ 9, 5, 2 }, s.series[1].values)
    assert.same({ 90, 50, 20 }, s.series[2].values)
    s = spec({ kind = "bar", sort = "asc", labels = { "a", "b", "c" }, series = { { values = { 2, 9, 5 } } } })
    assert.same({ "a", "c", "b" }, s.labels)
    s = spec({ kind = "bar", sort = "none", labels = { "a", "b", "c" }, series = { { values = { 2, 9, 5 } } } })
    assert.same({ "a", "b", "c" }, s.labels)
  end)

  it("names unnamed series by index and clamps width and height", function()
    local s = spec({ kind = "bar", labels = { "a" },
      series = { { values = { 1 } }, { name = "x", values = { 1 } } },
      width = 5, height = 1000 })
    assert.equals("series 1", s.series[1].name)
    assert.equals("x", s.series[2].name)
    assert.equals(20, s.width)
    assert.equals(40, s.height)
    s = spec({ kind = "bar", labels = { "a" }, series = { { values = { 1 } } }, width = 500 })
    assert.equals(100, s.width)
    assert.equals(8, s.height)
  end)

  it("histogram takes one series of samples and a bin count, no labels", function()
    local s = spec({ kind = "histogram", series = { { values = { 1, 2, 3 } } }, bins = 4 })
    assert.equals(4, s.bins)
    assert.is_nil(s.labels)
    local _, err = render.normalize({ kind = "histogram", series = { { values = { 1 } }, { values = { 2 } } } },
      CONFIG)
    assert.equals("histogram takes exactly one series of raw samples", err)
    _, err = render.normalize({ kind = "histogram", series = { { values = {} } } }, CONFIG)
    assert.equals("histogram needs at least one sample", err)
    assert.equals(10, spec({ kind = "histogram", series = { { values = { 1 } } } }).bins)
  end)
end)

describe("format_number", function()
  it("prints integers without decimals and other values with two, trimmed", function()
    assert.equals("42", render.format_number(42))
    assert.equals("-7", render.format_number(-7))
    assert.equals("0", render.format_number(0))
    assert.equals("3.14", render.format_number(3.14159))
    assert.equals("2.5", render.format_number(2.5))
    assert.equals("0.1", render.format_number(0.1))
    assert.equals("100", render.format_number(99.999))
  end)

  it("separates alphabetic units with a space and symbols without", function()
    assert.equals("42 ms", render.with_unit(42, "ms"))
    assert.equals("42%", render.with_unit(42, "%"))
    assert.equals("42", render.with_unit(42, nil))
  end)
end)

describe("bar", function()
  local out = draw({
    kind = "bar", title = "Parse time", unit = "ms", width = 30,
    labels = { "lexer", "señal", "ast" }, series = { { values = { 40, 20, 0 } } },
  })

  it("prints the title, one row per label, the widest value filling the bar", function()
    assert.same({
      "Parse time",
      "lexer │█████████████████ 40 ms",
      "señal │████████▌         20 ms",
      "ast   │                  0 ms",
    }, out.lines)
    for _, line in ipairs(out.lines) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= 30, line)
    end
  end)

  it("spans cover the title and exactly the block cells, by byte offset", function()
    assert.equals(3, #out.spans)
    assert.same({ row = 0, col_start = 0, col_end = #"Parse time", group = "StrapsChartTitle" }, out.spans[1])
    assert.equals(("█"):rep(17), span_text(out, out.spans[2]))
    assert.equals("StrapsChartSeries1", out.spans[2].group)
    assert.equals(("█"):rep(8) .. "▌", span_text(out, out.spans[3]))
    assert.equals(2, out.spans[3].row)
    assert.equals(#"señal │", out.spans[3].col_start)
  end)

  it("draws partial eighths and never drops a positive value to nothing", function()
    local o = draw({ kind = "bar", width = 24, labels = { "a", "b", "c" },
      series = { { values = { 16, 3, 0.01 } } } })
    assert.equals("a │████████████████ 16", o.lines[1])
    assert.equals("b │███              3", o.lines[2])
    assert.equals("c │▏                0.01", o.lines[3])
  end)

  it("draws several series as sub-rows under each label with a legend", function()
    local o = draw({
      kind = "bar", width = 29, labels = { "x", "y" },
      series = { { name = "before", values = { 10, 5 } }, { name = "after", values = { 2, 5 } } },
    })
    assert.same({
      "x",
      "  before │████████████████ 10",
      "  after  │███▎             2",
      "y",
      "  before │████████         5",
      "  after  │████████         5",
      "■ before  ■ after",
    }, o.lines)
    local groups = {}
    for _, sp in ipairs(o.spans) do groups[#groups + 1] = sp.group end
    assert.same({ "StrapsChartSeries1", "StrapsChartSeries2", "StrapsChartSeries1", "StrapsChartSeries2",
      "StrapsChartSeries1", "StrapsChartSeries2" }, groups)
    local legend = o.spans[#o.spans]
    assert.equals("■", span_text(o, legend))
    assert.equals("StrapsChartSeries2", legend.group)
  end)

  it("honors width", function()
    for _, w in ipairs({ 20, 40, 100 }) do
      local o = draw({ kind = "bar", width = w, labels = { "a" }, series = { { values = { 1 } } } })
      assert.equals(w, vim.fn.strdisplaywidth(o.lines[1]))
    end
  end)
end)

describe("stacked", function()
  local o = draw({
    kind = "stacked", unit = "ms", width = 25, labels = { "a", "b", "c" },
    series = {
      { name = "p", values = { 8, 4, 0 } },
      { name = "q", values = { 8, 0, 0 } },
      { name = "r", values = { 0, 4, 1 } },
    },
  })

  it("draws one bar per label, the series end to end, scaled to the largest total", function()
    assert.same({
      "a │████████████████ 16 ms",
      "b │████████         8 ms",
      "c │█                1 ms",
      "■ p  ■ q  ■ r",
    }, o.lines)
  end)

  it("colors each segment by its series and skips zero segments", function()
    local segs = {}
    for _, sp in ipairs(o.spans) do
      if sp.row < 3 then segs[#segs + 1] = { sp.row, sp.group, span_text(o, sp) } end
    end
    assert.same({
      { 0, "StrapsChartSeries1", ("█"):rep(8) },
      { 0, "StrapsChartSeries2", ("█"):rep(8) },
      { 1, "StrapsChartSeries1", ("█"):rep(4) },
      { 1, "StrapsChartSeries3", ("█"):rep(4) },
      { 2, "StrapsChartSeries3", "█" },
    }, segs)
    assert.equals(#"a │", o.spans[1].col_start)
    assert.equals(#("a │" .. ("█"):rep(8)), o.spans[2].col_start)
  end)

  it("keeps the total exact: a partial cell closes the last segment and a sliver is never dropped", function()
    local p = draw({ kind = "stacked", width = 24, labels = { "x", "y" },
      series = { { values = { 3, 0.01 } }, { values = { 1, 0 } } } })
    assert.equals("x │████████████████ 4", p.lines[1])
    assert.equals("y │▏                0.01", p.lines[2])
    assert.equals(("█"):rep(12), span_text(p, p.spans[1]))
    assert.equals(("█"):rep(4), span_text(p, p.spans[2]))
    assert.equals("▏", span_text(p, p.spans[3]))
    assert.equals("StrapsChartSeries1", p.spans[3].group)
    local q = draw({ kind = "stacked", width = 21, labels = { "x" },
      series = { { values = { 5 } }, { values = { 2 } } } })
    assert.equals("x │████████████████ 7", q.lines[1])
    assert.equals(("█"):rep(11), span_text(q, q.spans[1]))
    assert.equals(("█"):rep(5), span_text(q, q.spans[2]))
  end)

  it("emits no empty span for a middle series too small for a cell", function()
    local o = draw({ kind = "stacked", width = 25, labels = { "x" },
      series = { { values = { 8 } }, { values = { 0.01 } }, { values = { 8 } } } })
    assert.equals("x │████████████████ 16.01", o.lines[1])
    local groups = {}
    for _, sp in ipairs(o.spans) do
      if sp.row == 0 then
        assert.is_true(sp.col_end > sp.col_start, sp.group)
        groups[#groups + 1] = sp.group
      end
    end
    assert.same({ "StrapsChartSeries1", "StrapsChartSeries3" }, groups)
  end)

  it("sorts by the row total and refuses negative values", function()
    local s = spec({ kind = "stacked", sort = "desc", labels = { "a", "b" },
      series = { { values = { 9, 1 } }, { values = { 0, 10 } } } })
    assert.same({ "b", "a" }, s.labels)
    assert.same({ 1, 9 }, s.series[1].values)
    local _, err = render.normalize({ kind = "stacked", labels = { "a" }, series = { { values = { -1 } } } },
      CONFIG)
    assert.equals("stacked charts take values >= 0 (found -1); use diverging, line or sparkline for negative data",
      err)
  end)
end)

describe("diverging", function()
  local o = draw({ kind = "diverging", width = 24, unit = "ms", labels = { "a", "b", "c", "d" },
    series = { { values = { -4, 8, 0, 2 } } } })

  it("draws negatives left of a zero axis and positives right, signed values, each side to its own extreme",
    function()
      assert.same({
        "a █████│           -4 ms",
        "b      │██████████ +8 ms",
        "c      │           0 ms",
        "d      │██▌        +2 ms",
      }, o.lines)
    end)

  it("highlights the negative side, the axis and the positive side separately", function()
    local got = {}
    for _, sp in ipairs(o.spans) do got[#got + 1] = { sp.row, sp.group, span_text(o, sp) } end
    assert.same({
      { 0, "StrapsChartNegative", ("█"):rep(5) },
      { 0, "StrapsChartAxis", "│" },
      { 1, "StrapsChartAxis", "│" },
      { 1, "StrapsChartPositive", ("█"):rep(10) },
      { 2, "StrapsChartAxis", "│" },
      { 3, "StrapsChartAxis", "│" },
      { 3, "StrapsChartPositive", "██▌" },
    }, got)
    assert.equals(#"a ", o.spans[1].col_start)
  end)

  it("puts the axis at the edge when every value has the same sign", function()
    local p = draw({ kind = "diverging", width = 24, labels = { "a", "b" }, series = { { values = { 3, 1 } } } })
    assert.same({ "a │██████████████████ +3", "b │██████             +1" }, p.lines)
    local n = draw({ kind = "diverging", width = 24, labels = { "a", "b" }, series = { { values = { -3, -1 } } } })
    assert.same({ "a ██████████████████│ -3", "b             ██████│ -1" }, n.lines)
    assert.equals("StrapsChartNegative", n.spans[1].group)
    assert.equals(#"b             ", n.spans[3].col_start)
  end)

  it("keeps one cell for the minority side so a small opposite value still shows", function()
    local o = draw({ kind = "diverging", width = 24, labels = { "a", "b" }, series = { { values = { -100, 0.5 } } } })
    assert.same({ "a ███████████████│  -100", "b                │█ +0.5" }, o.lines)
    local p = draw({ kind = "diverging", width = 24, labels = { "a", "b" }, series = { { values = { 100, -0.5 } } } })
    assert.same({ "a  │███████████████ +100", "b █│                -0.5" }, p.lines)
  end)
end)

describe("stacked_column", function()
  local o = draw({ kind = "stacked_column", width = 30, height = 4, labels = { "a", "b", "c" },
    series = {
      { name = "p", values = { 2, 1, 0 } },
      { name = "q", values = { 2, 0, 0 } },
      { name = "r", values = { 0, 3, 1 } },
    } })

  it("draws one column per label scaled to the largest total", function()
    assert.same({
      "4│██ ██    ",
      " │██ ██    ",
      " │██ ██    ",
      "0│██ ██ ██ ",
      " └─────────",
      "  a  b  c",
      "■ p  ■ q  ■ r",
    }, o.lines)
  end)

  it("owns each cell by the series whose cumulative range covers it", function()
    local owners = {}
    for _, sp in ipairs(o.spans) do
      if sp.group:match("Series") and sp.row < 4 then
        owners[#owners + 1] = ("r%d c%d %s"):format(sp.row, sp.col_start, sp.group:sub(-1))
      end
    end
    assert.same({
      "r0 c4 2", "r0 c11 3",
      "r1 c4 2", "r1 c11 3",
      "r2 c4 1", "r2 c11 3",
      "r3 c4 1", "r3 c11 1", "r3 c18 3",
    }, owners)
  end)

  it("sorts by the row total", function()
    local s = spec({ kind = "stacked_column", sort = "asc", labels = { "a", "b" },
      series = { { values = { 9, 1 } }, { values = { 0, 10 } } } })
    assert.same({ "a", "b" }, s.labels)
    s = spec({ kind = "stacked_column", sort = "desc", labels = { "a", "b" },
      series = { { values = { 9, 1 } }, { values = { 0, 10 } } } })
    assert.same({ "b", "a" }, s.labels)
  end)
end)

describe("scatter", function()
  it("plots x against values on a shared braille grid with x extremes under the axis", function()
    local o = draw({ kind = "scatter", width = 14, height = 2, unit = "ms", x_unit = "KB",
      series = { { x = { 0, 10 }, values = { 0, 4 } }, { name = "j", x = { 10 }, values = { 0 } } } })
    assert.same({
      "4 ms│              ⠛",
      "0 ms│⣤             ⣤",
      "    └───────────────",
      "     0 KB      10 KB",
      "■ series 1  ■ j",
    }, o.lines)
    assert.equals("StrapsChartSeries1", o.spans[1].group)
    assert.equals("⠛", span_text(o, o.spans[1]))
    assert.equals("StrapsChartSeries2", o.spans[3].group)
    assert.equals("⣤", span_text(o, o.spans[3]))
  end)

  it("draws each point as a 2x2 dot cluster that stays inside the grid at the edges", function()
    local o = draw({ kind = "scatter", width = 12, height = 1, series = { { x = { 0, 1 }, values = { 0, 1 } } } })
    local plot = o.lines[1]:sub(#"1│" + 1)
    assert.equals("⣤", plot:sub(1, 3))
    assert.equals("⠛", plot:sub(-3))
    local bits = vim.fn.char2nr("⣤") - 0x2800
    assert.equals(0x04 + 0x20 + 0x40 + 0x80, bits)
  end)

  it("widens a degenerate range so a single point still draws", function()
    local o = draw({ kind = "scatter", width = 12, height = 1, series = { { x = { 5 }, values = { 7 } } } })
    assert.equals("8│", o.lines[1]:sub(1, #"8│"))
    assert.is_not_nil(o.lines[1]:sub(#"8│" + 1):find("[\226][\160-\163][\128-\191]"))
    assert.equals("  4" .. (" "):rep(16) .. "6", o.lines[3])
  end)
end)

describe("column", function()
  it("draws columns scaled to the height with the max and zero on the gutter", function()
    local o = draw({ kind = "column", height = 4, width = 30, labels = { "a", "b", "c" },
      series = { { values = { 4, 2, 0 } } } })
    assert.same({
      "4│██       ",
      " │██       ",
      " │██ ██    ",
      "0│██ ██    ",
      " └─────────",
      "  a  b  c",
    }, o.lines)
    assert.equals(7, #o.spans)
    assert.equals("██", span_text(o, o.spans[1]))
    assert.equals(3, o.spans[6].row)
    assert.equals(#"0│██ ", o.spans[6].col_start)
    assert.equals("StrapsChartSeries1", o.spans[1].group)
    local axis = o.spans[#o.spans]
    assert.equals("StrapsChartAxis", axis.group)
    assert.equals("└─────────", span_text(o, axis))
  end)

  it("uses partial blocks for the top cell", function()
    local o = draw({ kind = "column", height = 2, width = 30, labels = { "a" }, series = { { values = { 1 } } } })
    assert.same({ "1│██ ", "0│██ ", " └───", "  a" }, o.lines)
    o = draw({ kind = "column", height = 2, width = 30, labels = { "a", "b" }, series = { { values = { 8, 3 } } } })
    assert.equals("8│██    ", o.lines[1])
    assert.equals("0│██ ▆▆ ", o.lines[2])
  end)

  it("widens columns to the label width up to seven cells", function()
    local o = draw({ kind = "column", height = 1, width = 40, labels = { "alpha", "be" },
      series = { { values = { 1, 1 } } } })
    assert.same({ "1│█████ █████ ", " └────────────", "  alpha be" }, o.lines)
  end)

  it("numbers the columns and prints a legend when labels do not fit", function()
    local o = draw({ kind = "column", height = 1, width = 24, labels = { "first-label", "second-label" },
      series = { { values = { 1, 1 } } } })
    assert.same({
      "1│███████ ███████ ",
      " └────────────────",
      "  1       2",
      "1  first-label",
      "2  second-label",
    }, o.lines)
  end)

  it("interleaves several series per label and appends the legend", function()
    local o = draw({ kind = "column", height = 2, width = 30, labels = { "a", "b" },
      series = { { name = "p", values = { 2, 1 } }, { name = "q", values = { 1, 2 } } } })
    assert.same({
      "2│█   █ ",
      "0│██ ██ ",
      " └──────",
      "  a  b",
      "■ p  ■ q",
    }, o.lines)
    assert.equals("StrapsChartSeries2", o.spans[2].group)
    assert.equals("StrapsChartSeries1", o.spans[1].group)
  end)

  it("refuses data that cannot fit the width", function()
    local labels, values = {}, {}
    for i = 1, 30 do
      labels[i] = "l" .. i
      values[i] = i
    end
    local out, err = render.render(spec({ kind = "column", width = 20, labels = labels,
      series = { { values = values } } }))
    assert.is_nil(out)
    assert.equals("30 labels x 1 series do not fit in width 20; raise width or reduce the data", err)
  end)
end)

describe("line", function()
  it("plots braille dots with min and max on the gutter and labels under the axis", function()
    local o = draw({ kind = "line", height = 2, width = 20, labels = { "jan", "feb", "mar" },
      series = { { values = { 0, 10, 0 } } } })
    assert.equals(4, #o.lines)
    assert.equals("10│", o.lines[1]:sub(1, #"10│"))
    assert.equals(" 0│", o.lines[2]:sub(1, #" 0│"))
    assert.equals("  └" .. ("─"):rep(17), o.lines[3])
    assert.equals("   jan     feb   mar", o.lines[4])
    local dots = 0
    for _, line in ipairs({ o.lines[1], o.lines[2] }) do
      for ch in line:gmatch("[\226][\160-\163][\128-\191]") do dots = dots + 1 end
    end
    assert.is_true(dots >= 9, "expected a connected line across the plot, got " .. dots .. " braille cells")
    local function cell(line, idx)
      local chars = vim.fn.split(line:sub(#"10│" + 1), "\\zs")
      return chars[idx + 1]
    end
    local function has_dot(ch, bit)
      local cp = vim.fn.char2nr(ch)
      return cp >= 0x2800 and math.floor((cp - 0x2800) / bit) % 2 == 1
    end
    local peak = cell(o.lines[1], 8)
    assert.is_true(has_dot(peak, 0x01) or has_dot(peak, 0x08), "peak column top row carries a top dot: " .. peak)
    local first = cell(o.lines[2], 0)
    assert.is_true(has_dot(first, 0x40) or has_dot(first, 0x80),
      "first column bottom row carries a bottom dot: " .. first)
  end)

  it("handles negative values and a flat series", function()
    local o = draw({ kind = "line", height = 2, width = 10, labels = { "a", "b" },
      series = { { values = { -5, 5 } } } })
    assert.equals(" 5│", o.lines[1]:sub(1, #" 5│"))
    assert.equals("-5│", o.lines[2]:sub(1, #"-5│"))
    o = draw({ kind = "line", height = 2, width = 10, labels = { "a", "b" }, series = { { values = { 3, 3 } } } })
    assert.equals("4│", o.lines[1]:sub(1, #"4│"))
    assert.equals("2│", o.lines[2]:sub(1, #"2│"))
  end)

  it("colors each series separately and draws the legend", function()
    local o = draw({ kind = "line", height = 1, width = 8, labels = { "a", "b" },
      series = { { name = "up", values = { 0, 1 } }, { name = "down", values = { 1, 0 } } } })
    local groups = {}
    for _, sp in ipairs(o.spans) do groups[sp.group] = true end
    assert.is_true(groups.StrapsChartSeries1)
    assert.is_true(groups.StrapsChartSeries2)
    assert.equals("■ up  ■ down", o.lines[#o.lines])
    for _, sp in ipairs(o.spans) do
      if sp.group:match("Series") and sp.row == 0 then
        assert.matches("^[\226][\160-\163][\128-\191]", span_text(o, sp))
      end
    end
  end)
end)

describe("sparkline", function()
  it("draws one row per series scaled to its own range with min..max", function()
    local o = draw({ kind = "sparkline", unit = "ms", labels = { "a", "b", "c", "d" },
      series = { { name = "p50", values = { 1, 4, 8, 1 } }, { name = "p99", values = { -2, 0, 0, 2 } } } })
    assert.same({ "p50 ▁▄█▁ 1 ms..8 ms", "p99 ▁▅▅█ -2 ms..2 ms" }, o.lines)
    assert.equals("▁▄█▁", span_text(o, o.spans[1]))
    assert.equals("StrapsChartSeries1", o.spans[1].group)
    assert.equals("▁▅▅█", span_text(o, o.spans[2]))
    assert.equals("StrapsChartSeries2", o.spans[2].group)
  end)

  it("draws a flat series at mid height", function()
    local o = draw({ kind = "sparkline", labels = { "a", "b" }, series = { { values = { 5, 5 } } } })
    assert.equals("series 1 ▄▄ 5..5", o.lines[1])
  end)
end)

describe("histogram", function()
  it("bins the samples and draws a bar chart of counts", function()
    local o = draw({ kind = "histogram", bins = 2, width = 30, labels = nil,
      series = { { values = { 1, 2, 3, 4, 4 } } } })
    assert.same({
      "1..2.5 │█████████████▍       2",
      "2.5..4 │████████████████████ 3",
    }, o.lines)
  end)

  it("puts the maximum sample in the last bin and collapses identical samples into one bin", function()
    local labels, counts = render.histogram_bins({ 0, 10 }, 10)
    assert.equals(1, counts[1])
    assert.equals(1, counts[10])
    assert.equals("9..10", labels[10])
    labels, counts = render.histogram_bins({ 7, 7, 7 }, 5, "ms")
    assert.same({ "7 ms" }, labels)
    assert.same({ 3 }, counts)
  end)
end)
