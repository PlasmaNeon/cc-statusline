# Claude Code status line

```
Opus 5 (1M context) high ctx 37% · duhuang@host:~/fb-devices-ai  main · $1.23 · 5h 62% 7d 89% Fable 7%
```

Model, effort level, context usage, user@machine, working directory, git branch,
session cost, and the 5-hour / weekly / model-scoped rate limits.

## Install

```sh
git clone https://github.com/PlasmaNeon/cc-statusline.git
cd cc-statusline
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
| effort | the exact per-level colors from the `/effort` picker |
| `ctx NN%` | context window used |
| `user@host:path` | path shortened to `~` and its last 3 components |
| branch | git branch, with `+` staged, `!` modified, `?` untracked, `=` conflict, `<`/`>` behind/ahead |
| `$N.NN` | session cost, from the CLI's own `cost.total_cost_usd` |
| `5h` / `7d` | rate limit usage |
| `Fable NN%` | the model-scoped weekly limit — see *Model-scoped limit* |

Percentages use a six-band color ramp: green `<30`, lime `<50`, gold `<65`,
amber `<80`, orange `<90`, red `90+`.

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

## Theme

Light and dark palettes are both defined, resolved in this order:

1. `CLAUDE_STATUSLINE_THEME` (`light` / `dark`)
2. `theme` in `~/.claude/settings.json`
3. `COLORFGBG`
4. macOS system appearance
5. light

On a remote login `COLORFGBG` is not forwarded and `defaults` does not exist, so
those hosts land on step 5 — set `CLAUDE_STATUSLINE_THEME=dark` there if needed.

## Width and wrapping

The payload carries no terminal width, so it comes from `/dev/tty`, then
`COLUMNS` (what the CLI actually exports), defaulting to 200. Segments wrap onto
extra lines when they do not fit; tight groups such as `user@host:path branch`
never break apart. Override with `CLAUDE_STATUSLINE_WIDTH=100` to test.

## Customizing

All near the top of `statusline-command.sh`:

- `C_*` — segment colors, one block per theme
- `E_*` — effort level colors
- `GAUGE` — the six-band percentage ramp
- `RAINBOW_SUBSTEPS` / `_SPREAD` / `_STEP` — `max` gradient resolution, width, speed

Layout is built from `add_seg "<text>" <separator>` calls in source order.
Separators: `bar` (` · `), `space`, `colon` (`:`). Reorder the calls to reorder
the bar; `space` and `colon` also bind a segment to the previous one for wrapping.

### Branch icon

The glyph before the branch is `U+E725` (Nerd Font devicons). If it renders as a
box, either install a Nerd Font or replace it in the `git_seg=` line with a plain
character.

## Notes

Colors are the literal values from Claude Code's own themes, read out of the
CLI binary (v2.1.231), so the bar matches the rest of the interface. A future
version could rename them.
