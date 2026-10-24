# straps-chartifier

A `show_chart` tool for [straps.nvim](https://github.com/ducharmemp/straps) agents, plus a `# Charts` system-prompt section and a `skill.charting` entry that send the agent to the tool whenever a result is numeric and comparative: counts per file, timings before and after, sizes, a distribution, a value over time. The chart opens in a scratch split beside the transcript, one highlight group per series, and the agent's reply keeps the one or two numbers the decision turns on.

```
Parse time
lexer │█████████████████ 40 ms
señal │████████▌         20 ms
ast   │                  0 ms
```

## Kinds

| Kind | Draws | Takes |
| --- | --- | --- |
| `bar` | One horizontal bar per label, eighth-cell precision; several series stack as sub-rows under each label. | values >= 0 |
| `stacked` | One horizontal bar per label with the series laid end to end, each segment in its own highlight group, the row total printed; `sort` orders by the total. | values >= 0 |
| `diverging` | One series of deltas: negatives draw left of a zero axis in `StrapsChartNegative`, positives right in `StrapsChartPositive`, each side scaled to its own extreme, values signed. | one series, any number |
| `column` | Vertical columns, one gutter with the maximum and `0`, labels under the axis or numbered with a legend when they do not fit. | values >= 0 |
| `stacked_column` | One column per label, the series stacked bottom to top and scaled to the largest total; `sort` orders by the total. | values >= 0 |
| `line` | Braille dots at 2x4 resolution per cell, several series in different highlight groups, min and max on the gutter. | any number |
| `scatter` | Braille 2x2 dot clusters of `x` against `values` per series on one shared grid; every series carries an `x` array; `x_unit` labels the x extremes under the axis. No labels. | any number |
| `sparkline` | One row per series: `name ▁▃█▁ min..max`, scaled to the series' own range. | any number |
| `histogram` | One series of raw samples, binned by the tool (`bins`, default 10), drawn as a bar chart of counts. | any number |

Every kind takes the same input: `labels` (one per data point; histogram and scatter need none) and `series` (`{ name, values, x? }`, every `values` as long as `labels`; scatter's `x` as long as `values`). `title`, `unit`, `x_unit`, `sort` (`asc`/`desc` by the first series, or by the row total for the stacked kinds), `bins`, `width`, `height` and `split` are optional. Bad input comes back as a `show_chart: <reason>` string so the agent can correct it.

## Install

With nixvim, import the module next to straps':

```nix
imports = [ straps.nixvimModules.default straps-chartifier.nixvimModules.default ];
plugins.straps.enable = true;
plugins.straps-chartifier.enable = true;
plugins.straps-chartifier.settings.split = "horizontal";
```

With any other plugin manager, put this repository on the runtimepath after straps and call, after `require("straps").setup()`:

```lua
require("straps_chartifier").setup({})
```

The order matters for the prompt section. straps composes the system prompt from `fn.system_prompt_layer.*` entries in registration order, so `register()` defines `fn.system_prompt_layer.chartifier` only once straps' own layers exist. The plugin file registers at load and again on `VimEnter`, which covers a straps whose `setup()` ran at startup; a straps loaded later needs the explicit `setup()` call. `require("straps_chartifier").status().prompt_layer` reports `registered`, `disabled by config.prompt_layer`, or `not registered: straps setup() has not run`.

`show_chart` carries `capability = "read"`, so straps' confirmation gate auto-allows it like `show_buffer`.

## Configuration

Every key of `require("straps_chartifier").config` (`lua/straps_chartifier/init.lua`) can be passed to `setup()`:

| Key | Default | Meaning |
| --- | --- | --- |
| `max_width` | `100` | Chart width cap in cells; `width` in a call clamps to it. |
| `height` | `8` | Plot height in rows for `column` and `line` when the call passes none. |
| `max_bars` | `60` | Label count cap; more is refused with a message asking the agent to aggregate. |
| `highlight` | `true` | Place extmarks from the renderer's spans. |
| `prompt_layer` | `true` | Emit the `# Charts` section; `false` makes the layer return nil. |
| `split` | `"vertical"` | Default split direction; a call's `split` overrides it. |

Highlight groups `StrapsChartSeries1`..`StrapsChartSeries8`, `StrapsChartAxis` (links to `Comment`), `StrapsChartTitle` (links to `Title`), `StrapsChartPositive` (`DiffAdd`) and `StrapsChartNegative` (`DiffDelete`) are defined with `default = true`; a colorscheme or `nvim_set_hl` call wins.

## Registry entries

| Entry | Signature | Default |
| --- | --- | --- |
| `tool.show_chart` | `(input, ctx) -> string` | Normalize the input, draw through `fn.chartifier_render`, open the split; capability `read`. |
| `fn.chartifier_render` | `(spec) -> { lines, spans }` | `lua/straps_chartifier/render.lua`. `spans` are `{ row, col_start, col_end, group }`, 0-based bytes, `col_end` exclusive. `:StrapsEdit fn.chartifier_render` swaps the drawing. |
| `fn.system_prompt_layer.chartifier` | `(opts) -> string\|nil` | `lua/straps_chartifier/prompt.lua` `LAYER`. |
| `skill.charting` | prose | `lua/straps_chartifier/prompt.lua` `SKILL`: picking a kind, labels, units, what to say beside a chart. |

## Tests

```sh
nix develop
busted tests/render_spec.lua
for t in tests/*_spec.lua; do busted "$t" || exit 1; done
```

`STRAPS_ROOT` names the straps checkout the specs load; the devShell sets it to the flake input, and `tests/helpers.lua` falls back to `.ref/straps` then `../straps`. One busted process per spec file: the specs assume a fresh Neovim.
