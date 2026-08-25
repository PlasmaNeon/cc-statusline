# Claude Code status line

Always one line:

```
Opus 5 (1M context) high 󱘲 37% ·  main i@host:~/fb-devices-ai · $1.23(15/300) · 5h 62% 7d 89%
```

Too narrow for the whole thing, and the terminal clips the tail:

```
Opus 5 (1M context) high 󱘲 37% ·  main i@host:~/fb-de…
```

## Install

One line, no checkout needed:

```sh
curl -fsSL https://raw.githubusercontent.com/PlasmaNeon/cc-statusline/main/install.sh | bash
```

Or from a clone:

```sh
./install.sh              # install
./install.sh --dry-run    # preview, change nothing
```

Either way it puts `statusline-command.sh` in `~/.claude/` — copied from the
checkout, or fetched from the same branch when piped — and sets the `statusLine`
key in `~/.claude/settings.json`. An existing settings file is preserved: only
that one key is replaced, and a timestamped `.bak` is written alongside it. The
install ends by rendering a sample line so you can see it before restarting.
Restart Claude Code to pick it up.

Add `-s -- --dry-run` to the piped form (`… | bash -s -- --dry-run`) to see what
it would do without touching anything.

Requires `bash` (3.2 is fine, so stock macOS works), `jq`, `awk`, and `git`
(2.14+, for `--no-optional-locks`). macOS and Linux both work as-is: nothing here
needs GNU over BSD tools, and the two commands whose flags genuinely differ
(`stat`, `hostname`) carry both spellings. Without `jq` the payload reads empty
and the line falls back to the branch, host, and path it can derive locally. A
Nerd Font is needed for three glyphs; without one they show as boxes — see
*Nerd Font glyphs*.

## What it shows

| Segment | Notes |
|---|---|
| model | bold, Claude terracotta |
| effort | the per-level colors from the `/effort` picker, in the active theme |
| `󱘲 NN%` | context window used, grouped with the effort level — the label is `nf-md-database_outline`, so it needs a Nerd Font |
| branch | git branch, with `+` staged, `!` modified, `?` untracked, `=` conflict, `<`/`>` behind/ahead |
| `user@host:path` | path shortened to `~` and its last 3 components |
| `$N.NN` | session cost, from the CLI's own `cost.total_cost_usd` |
| `(used/limit)` | usage-credit balance in dollars, bound tight to the cost — see *Usage credits* |
| `5h` / `7d` | rate limit usage |
| `Fable NN%` | the model-scoped weekly limit — see *Model-scoped limit* |

Percentages use a six-band color ramp at `<30`, `<50`, `<65`, `<80`, `<90`,
`90+`, built from the active theme's `success`, `warning`, and `error` — see
*Theme*.

`xhigh` and `max` are animated in the `/effort` picker, which a status line
cannot reproduce — it only redraws on state changes. They instead advance one
frame whenever the session does work: `max` rotates a rainbow gradient, `xhigh`
sweeps a highlight along the word. State lives in `$TMPDIR/claude-statusline-anim-*`.

## Model-scoped limit

The weekly limit scoped to a single model (today that is Fable) is resolved in
two steps: `rate_limits.model_scoped[]` in the status line payload if the CLI
ever sends it, otherwise `cachedUsageUtilization.utilization.limits[]` in
`~/.claude.json`, which is where the CLI caches it now. An entry marked
`is_active` wins. The segment is labelled with the limit's own display name, so
it follows a rename rather than hardcoding "Fable", and it is omitted entirely
when no such limit exists. A separate `ovr` segment shows the overage limit if
the payload ever carries one.

Both sit at the tail of the line, so they are the first thing a narrow window
clips.

## Usage credits

The stdin payload's `rate_limits` carry percentages only — never an absolute
balance. The one absolute figure the CLI has, the account's usage-credit balance,
is not in the payload at all; it lives in `cachedUsageUtilization.utilization.spend`
in `~/.claude.json`, refreshed periodically rather than per redraw. So it is read
from there, exactly like the model-scoped limit's fallback above, and rendered as
`(used/limit)` in whole dollars glued to the session cost: `$1.23(15/300)`. It
takes the same six-band ramp as the gauges, colored by `spend.percent`.

Accounts without the credit program (`spend.enabled` false, or no `spend` at all)
get no segment — the cost stands alone.

## Layout

Everything is emitted as a single line, in segment order, at whatever length it
comes to. Nothing is measured and nothing is pre-wrapped: the CLI renders each
status line with `wrap="truncate"`, so a line wider than the window is clipped
by the terminal on the way out. That costs only the tail — the rate-limit
gauges — and costs nothing at any width the content already fits.

Measuring would be worse, not better. The CLI re-runs this command when *session
state* changes — a new message, a token count, a model or effort switch — and a
terminal resize is not one of those triggers. A layout chosen from the width at
render time therefore outlives the resize that invalidated it, and an idle
session sits on a stale two-line split long after the window grew wide enough
for one. Clipping is re-evaluated by the terminal on every repaint, so it is
always current.

Order it front to back, then: the segments you always want visible go first.

## Theme

The line follows `/theme`. Every value is the CLI's own, read out of the theme
table in the installed binary and keyed by the CLI's own names, so a segment
reads the same here as the element it borrows its color from.

`/theme` writes its choice to `settings.json` before the next redraw, so that
file is the signal — not `COLORFGBG`, which is captured when the shell starts and
never updates when the terminal's theme changes under a running session.
`settings.local.json` wins over `settings.json`, as it does for the CLI.

| Segment | Color |
|---|---|
| model | `claude` |
| effort | per level — see below |
| gauges (`󱘲`, `5h`, `7d`, scoped, credits) | the six-band ramp |
| labels and separators | `inactive`, dimmed |
| git-dirty marker | `error` |
| branch, path, cost | fixed, not themed |

The effort ramp is `warning` / `success` / `permission` / `autoAccept` for
`low`…`xhigh` and the seven `rainbow_*` stops for `max`; the `xhigh` shimmer
crest (`#d0b4ff`) and `ultracode`'s violet fill are CLI literals rather than
theme keys, so they are the same in every theme. The gauge takes `success` →
`warning` → `error` and splits them into six bands, three ways depending on the
theme: `interp` blends neighbouring anchors (`dark`, `light`); the daltonized
themes cannot, since their blue-to-yellow anchors interpolate through the green
a daltonized palette exists to avoid, so each anchor gets a weakened band and
then itself; and the two `ansi` themes have no arithmetic at all, so each anchor
pairs with its bright or normal sibling.

Three cases fall back to `dark`: `auto`, which the CLI resolves with an OSC 11
background query that a status line writing to that same terminal cannot make; a
theme supplied by a plugin, which has no file to read; and an unreadable or
unknown custom theme. A custom theme otherwise resolves the way the CLI resolves
it — `~/.claude/themes/<slug>.json`, its `base` palette with `overrides` merged
over it, keeping only keys the base carries and values in one of the five
accepted forms (`rgb(r,g,b)`, `#rrggbb`, `#rgb`, `ansi256(n)`, `ansi:name`).

The three fixed colors — branch, path, cost — have no CLI element to mirror, so
they stay one hue chosen to clear roughly 3:1 contrast against both white and
black.

Nothing is configurable by environment: `CLAUDE_STATUSLINE_THEME` and
`~/.claude/statusline-theme` are not read.

## Customizing

All near the top of `statusline-command.sh`:

- `TH_*` — the per-theme table, one variable per CLI key
- `C_DIR` / `C_BRANCH` / `C_COST` — the three theme-independent segment colors
- `E_*` — effort level colors, derived from `TH_*`
- `GAUGE` / `GAUGE_MODE` — the six-band percentage ramp and how it is built
- `RAINBOW_SUBSTEPS` / `_SPREAD` / `_STEP` — `max` gradient resolution, width, speed

Layout is built from `add_seg "<text>" <separator>` calls in source order.
Separators: `bar` (` · ` between groups), `bar_tight` (same divider, bound to
the previous segment), `space`, `colon`. Reorder the calls to reorder the bar;
a separator chosen at runtime lets a group open with `bar` whether or not the
segment ahead of it was rendered.

### Nerd Font glyphs

Three glyphs need a Nerd Font. If any renders as a box, either install one or
replace that character with plain text.

| Glyph | Codepoint | Where |
|---|---|---|
| `` | `U+E725` — `dev-git_branch` | before the branch, in the `git_seg=` line |
| `󱘲` | `U+F1632` — `md-database_outline` | the context-window label, in the `gauge_segment` call |
| `󰌾` | `U+F033E` — `md-lock` | after the path, only when the directory is read-only |

The rate-limit gauges stay lettered (`5h`, `7d`), so a terminal without a Nerd
Font still reads correctly everywhere else.

## Notes

Colors are the literal values from Claude Code's own themes, read out of the CLI
binary (v2.1.239) and verified against it. A future CLI version could change or
rename them; the fallbacks all land on `dark`, so a rename degrades to the dark
palette rather than to no color.
