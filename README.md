# Claude Code status line

Always one line:

```
Opus 5 (1M context) high ctx 37% ·  main duhuang@host:~/fb-devices-ai · $1.23 · 5h 62% 7d 89%
```

Too narrow for the whole thing, and the terminal clips the tail:

```
Opus 5 (1M context) high ctx 37% ·  main duhuang@host:~/fb-de…
```

## Install

```sh
./install.sh              # install
./install.sh --dry-run    # preview, change nothing
```

Copies `statusline-command.sh` to `~/.claude/` and sets the `statusLine` key in
`~/.claude/settings.json`. An existing settings file is preserved — only that one
key is replaced, and a timestamped `.bak` is written. Restart Claude Code after.

Requires `bash` (3.2 is fine, so stock macOS works), `jq`, and `git`. A Nerd Font
is needed for the branch glyph; without one it shows as a box — see *Branch icon*.

## What it shows

| Segment | Notes |
|---|---|
| model | bold, Claude terracotta |
| effort | the per-level colors from the `/effort` picker, identical in any theme |
| `ctx NN%` | context window used, grouped with the effort level |
| branch | git branch, with `+` staged, `!` modified, `?` untracked, `=` conflict, `<`/`>` behind/ahead |
| `user@host:path` | path shortened to `~` and its last 3 components |
| `#42 approved` | pull request for the branch, colored by state — needs `gh` installed and authenticated, hidden otherwise |
| `$N.NN` | session cost, from the CLI's own `cost.total_cost_usd` |
| `5h` / `7d` | rate limit usage |
| `Fable NN%` | the model-scoped weekly limit — see *Model-scoped limit* |

Percentages use a six-band color ramp: green `<30`, lime `<50`, gold `<65`,
amber `<80`, orange `<90`, red `90+`. PR states: green approved, amber changes
requested, grey draft, violet merged, red closed.

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

One palette, not two. The theme cannot be detected reliably from inside a status
line:

- `COLORFGBG` is captured when the shell starts and never updates when the
  terminal's theme changes under a running session.
- A remote login forwards neither it nor macOS's `AppleInterfaceStyle`, and
  `defaults` is macOS-only.

So a palette picked from those signals is wrong exactly when it matters — and
the wrong half is dead code the rest of the time. Every color here is instead
chosen to clear roughly 3.5:1 contrast against both white and black. The hues
are Claude Code's own, pulled to the midpoint of its light and dark palettes.

That includes the effort levels, the `xhigh` shimmer crest and the `max`
rainbow: a level always reads as the same color, whatever the terminal is set
to. There is nothing to pin and nothing to configure — `CLAUDE_STATUSLINE_THEME`
and `~/.claude/statusline-theme` are no longer read.

## Customizing

All near the top of `statusline-command.sh`:

- `C_*` — segment colors (one palette, checked against both backgrounds)
- `E_*` — effort level colors
- `GAUGE` — the six-band percentage ramp
- `RAINBOW_SUBSTEPS` / `_SPREAD` / `_STEP` — `max` gradient resolution, width, speed

Layout is built from `add_seg "<text>" <separator>` calls in source order.
Separators: `bar` (` · ` between groups), `bar_tight` (same divider, bound to
the previous segment), `space`, `colon`. Reorder the calls to reorder the bar;
a separator chosen at runtime lets a group open with `bar` whether or not the
segment ahead of it was rendered.

### Branch icon

The glyph before the branch is `U+E725` (Nerd Font devicons). If it renders as a
box, either install a Nerd Font or replace it in the `git_seg=` line with a plain
character.

## Notes

Colors started as the literal values from Claude Code's own themes, read out of
the CLI binary (v2.1.231), and were then reconciled into the single palette
described under *Theme*. A future CLI version could rename them.
