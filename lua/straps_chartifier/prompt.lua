local M = {}

M.LAYER = [[# Charts

When a result is numeric and comparative, call show_chart instead of
writing a list of numbers or a markdown table into the reply: counts per
file, timings before and after, sizes, durations, a distribution of
samples, a value over time. The chart opens in a split beside the
transcript; the reply still states the one or two numbers the decision
turns on and points at the chart for the rest.

Kinds: bar for ranked categories (sort="desc" puts the largest first);
stacked for parts of a total per category (time per stage, bytes per
section); diverging for one delta per label, before minus after,
negatives left of the zero axis; column for a few categories side by
side, or several series per category; stacked_column when the reader
compares totals and parts at once; line for a value over an ordered axis
(commits, dates, iterations); scatter for one numeric variable against
another (each series carries an x array); sparkline for a compact trend
per series; histogram for raw samples, which it bins itself. Negative
values go to diverging, line, scatter or sparkline. Two or more series
share one labels array. Keep labels under 12 characters and pass the unit
once in `unit`.

Keep a markdown table in the reply for exact values with mixed units,
non-numeric columns, or fewer than three rows. skill.charting is the long
form.]]

M.SKILL = [[Charting guidance for show_chart, the long form of the "# Charts" prompt section.

Choose the kind from the shape of the data:
- bar: one value per category, ranked. sort="desc" for "which is largest"; keep the input order when the
  order itself carries meaning (pipeline stages, directories in path order).
- stacked: parts of a total per category, one bar per label with the series end to end and the total
  printed. sort orders by the total. Segments are told apart by highlight only, so the legend matters;
  with more than four series, or when the parts are what the reader compares, use column instead.
- diverging: one delta per label (after minus before, regression minus baseline). Negatives draw left of
  a zero axis in StrapsChartNegative, positives right in StrapsChartPositive, each side scaled to its own
  extreme. Takes exactly one series; sort="desc" puts the largest gain first.
- column: a few categories compared side by side, or several series per category (before/after per file).
  Column width shrinks with the label count; past about 15 labels switch to bar.
- stacked_column: one column per label, the series stacked bottom to top, scaled to the largest total.
  Use it when both the totals and their composition are the point; the row total is not printed, so add
  `unit` and keep the label count under about 12 so the columns stay two cells wide.
- line: a value over an ordered axis. Several series draw in different highlight groups; the y range is
  shared, so series with different magnitudes belong in separate charts.
- scatter: one numeric variable against another, no labels; every series carries `x` as long as `values`
  ("does file size predict parse time"). `unit` labels the y axis, `x_unit` the x axis ends. Points share
  one x range and one y range across series.
- sparkline: a one-row trend per series, for many series or for a glance. The row prints min..max; the
  shape is relative to the series' own range.
- histogram: pass the raw samples as one series and let the tool bin them (bins defaults to 10). Use it for
  latency samples, file sizes, line counts: anything where the distribution matters more than each value.

Inputs the chart needs to read well:
- labels: short, distinct, and in the order you want them drawn. A file path label should be the basename
  or the path relative to the repo root; a date label should be the shortest unambiguous form.
- unit: pass it once ("ms", "KB", "%"); every printed number carries it. Do not put units into labels or
  series names.
- series names: name every series when there are two or more; the legend prints them.
- width and height: the defaults fit a vertical split. Raise height for line charts with many points,
  lower width for a horizontal split beside a narrow window.

What goes in the reply next to the chart: the conclusion and the one or two numbers it rests on
("parse() takes 68% of the run; the chart ranks the rest"). Do not transcribe the chart into prose.

Pair a chart with set_findings when each bar maps to a file:line, so the user can jump from the ranking to
the code. Pair it with show_diff when the chart compares before and after a change you made.

Keep a markdown table in the reply when exact values matter more than their ranking, when columns carry
different units, when a column is text, or when there are fewer than three rows.]]

return M
