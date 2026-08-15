#!/bin/bash
# Claude Code statusLine command.
#
# Segments (in order): model name, effort level, context-window usage %,
# user@machine, current directory, git branch, session cost ($ spent),
# 5-hour rate-limit %, weekly (7-day) rate-limit %, the model-scoped weekly
# rate-limit % (Fable), and - if the CLI ever exposes it - the overage limit %.
#
# Colors are the literal Claude theme palettes read out of the installed
# CLI (v2.1.231), and the effort segment reproduces the exact per-level
# colors the /effort picker uses. Both the light and dark palettes are
# defined; the theme is resolved the same way the CLI resolves it.

input=$(cat)

IFS=$'\t' read -r cwd worktree model_name effort_level cost_usd ctx_pct five_hr_pct weekly_pct overage_pct session_id transcript_path scoped_pct scoped_name <<<"$(
  echo "$input" | jq -r '
    # A model-scoped weekly limit (currently Fable). The field names the CLI
    # uses here are not settled, so every plausible spelling is accepted.
    def scoped:
      (.rate_limits.model_scoped // [])
      | map(select((.utilization // .used_percentage // .percent) != null))
      | (map(select(.is_active == true)) + .)[0];
    [ (.workspace.current_dir // "-"),
      (.worktree.branch // "-"),
      (.model.display_name // "-"),
      (.effort.level // "-"),
      (.cost.total_cost_usd // "-"),
      (.context_window.used_percentage // "-"),
      (.rate_limits.five_hour.used_percentage // "-"),
      (.rate_limits.seven_day.used_percentage // "-"),
      (.rate_limits.seven_day_overage_included.used_percentage
        // .rate_limits.overage.used_percentage // "-"),
      (.session_id // "-"),
      (.transcript_path // "-"),
      ((scoped | (.utilization // .used_percentage // .percent)) // "-" | tostring),
      ((scoped | (.display_name // .scope.model.display_name)) // "-")
    ] | @tsv' 2>/dev/null
)"

unset_if_dash() { [ "$1" = "-" ] && echo "" || echo "$1"; }
cwd=$(unset_if_dash "$cwd"); [ -z "$cwd" ] && cwd="$PWD"
worktree=$(unset_if_dash "$worktree")
model_name=$(unset_if_dash "$model_name")
effort_level=$(unset_if_dash "$effort_level")
cost_usd=$(unset_if_dash "$cost_usd")
ctx_pct=$(unset_if_dash "$ctx_pct")
five_hr_pct=$(unset_if_dash "$five_hr_pct")
weekly_pct=$(unset_if_dash "$weekly_pct")
overage_pct=$(unset_if_dash "$overage_pct")
session_id=$(unset_if_dash "$session_id")
transcript_path=$(unset_if_dash "$transcript_path")
scoped_pct=$(unset_if_dash "$scoped_pct")
scoped_name=$(unset_if_dash "$scoped_name")

# The payload does not currently carry the model-scoped weekly limit, but the
# CLI caches it in ~/.claude.json, so fall back to that. Prefer an active limit
# and otherwise take the first one; "Fable" is what lands here today.
if [ -z "$scoped_pct" ] && [ -f "$HOME/.claude.json" ]; then
  IFS=$'\t' read -r scoped_pct scoped_name <<<"$(
    jq -r '
      (.cachedUsageUtilization.utilization.limits // [])
      | map(select(.kind == "weekly_scoped" and .percent != null
                   and .scope.model.display_name != null))
      | (map(select(.is_active == true)) + .)[0]
      | if . then [(.percent | tostring), .scope.model.display_name] | @tsv
        else empty end' "$HOME/.claude.json" 2>/dev/null
  )"
fi

# ---- resolve light vs dark exactly the way the CLI does ----
#   1. CLAUDE_STATUSLINE_THEME, for hosts where nothing can be detected
#   2. an explicit theme in settings.json
#   3. otherwise COLORFGBG's background field (the CLI's own heuristic:
#      background 0-6 or 8 means a dark terminal)
#   4. otherwise the macOS system appearance
#   5. otherwise light
#
# On a remote login COLORFGBG is not forwarded and `defaults` exists only on
# macOS, so such hosts land on step 5; set CLAUDE_STATUSLINE_THEME=dark there
# if the terminal is dark.
resolve_theme() {
  local configured bg
  case "$CLAUDE_STATUSLINE_THEME" in
    light) echo light; return ;;
    dark)  echo dark;  return ;;
  esac
  configured=$(jq -r '.theme // "auto"' "$HOME/.claude/settings.json" 2>/dev/null)
  case "$configured" in
    light*) echo light; return ;;
    dark*)  echo dark;  return ;;
  esac

  bg="${COLORFGBG##*;}"
  if [ -n "$bg" ] && [ "$bg" -eq "$bg" ] 2>/dev/null && [ "$bg" -ge 0 ] && [ "$bg" -le 15 ]; then
    if [ "$bg" -le 6 ] || [ "$bg" -eq 8 ]; then echo dark; else echo light; fi
    return
  fi

  if command -v defaults >/dev/null 2>&1 &&
     [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; then
    echo dark
  else
    echo light
  fi
}
THEME=$(resolve_theme)

RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
fg() { printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"; }

if [ "$THEME" = "light" ]; then
  # ---- Claude light-theme palette ----
  C_CLAUDE=$(fg 215 119 87)    # "claude" terracotta - model name
  C_DIR=$(fg 8 145 178)        # cyan - cwd
  C_BRANCH=$(fg 176 82 114)    # rose - git branch
  C_COST=$(fg 150 108 30)      # "warning" - money spent
  C_LABEL=$(fg 102 102 102)    # "inactive" - labels
  C_ERR=$(fg 171 43 63)        # "error" - git dirty marker
  # gauge ramp, green -> red, anchored on "success"/"warning"/"error"
  GAUGE=("$(fg 44 122 57)" "$(fg 90 140 45)" "$(fg 150 108 30)"
         "$(fg 175 95 30)" "$(fg 190 70 45)" "$(fg 171 43 63)")
  # /effort picker colors, one per level (see Kvl in the CLI)
  E_LOW=$(fg 150 108 30)       # "warning"
  E_MEDIUM=$(fg 44 122 57)     # "success"
  E_HIGH=$(fg 87 105 247)      # "permission"
  E_XHIGH=$(fg 135 0 255)      # "autoAccept" (base under the shimmer)
else
  # ---- Claude dark-theme palette ----
  C_CLAUDE=$(fg 215 119 87)    # "claude" terracotta - model name
  C_DIR=$(fg 0 204 204)        # cyan - cwd
  C_BRANCH=$(fg 196 102 134)   # rose - git branch
  C_COST=$(fg 255 193 7)       # "warning" - money spent
  C_LABEL=$(fg 153 153 153)    # "inactive" - labels
  C_ERR=$(fg 255 107 128)      # "error" - git dirty marker
  # gauge ramp, green -> red, anchored on "success"/"warning"/"error"
  GAUGE=("$(fg 78 186 101)" "$(fg 140 200 90)" "$(fg 255 193 7)"
         "$(fg 255 160 60)" "$(fg 255 130 90)" "$(fg 255 107 128)")
  # /effort picker colors, one per level (see Kvl in the CLI)
  E_LOW=$(fg 255 193 7)        # "warning"
  E_MEDIUM=$(fg 78 186 101)    # "success"
  E_HIGH=$(fg 177 185 249)     # "permission"
  E_XHIGH=$(fg 175 135 255)    # "autoAccept" (base under the shimmer)
fi

# "violet-ripple" (ultracode) and the "rainbow-animated" cycle (max) are
# hardcoded in the CLI rather than themed, so they are shared.
E_SHIMMER=$(fg 208 180 255)   # "#d0b4ff", the shimmer crest
E_ULTRA_BG=$'\033[48;2;140;80;240m'
E_ULTRA_FG=$'\033[38;2;255;255;255m'

# "rainbow-animated" (max). The picker has 7 hue stops and spins them fast
# enough to read as flow; at one frame per message those stops land as three
# clashing letters. So the stops are interpolated into a finer wheel: the
# word becomes a smooth slice of gradient, and each frame rotates it by a
# full stop - subtle within the word, obvious between messages.
RAINBOW_SUBSTEPS=6            # interpolated colors between adjacent stops
RAINBOW_SPREAD=3              # wheel positions between neighbouring letters
RAINBOW_STEP=$RAINBOW_SUBSTEPS  # wheel positions advanced per frame
RAINBOW=()
while IFS= read -r _c; do RAINBOW+=("$_c"); done < <(awk -v n="$RAINBOW_SUBSTEPS" 'BEGIN{
  split("235,95,87 245,139,87 250,195,95 145,200,130 130,170,220 155,130,200 200,130,180", stops, " ")
  for (k = 1; k <= 7; k++) { split(stops[k], c, ","); R[k] = c[1]; G[k] = c[2]; B[k] = c[3] }
  for (k = 1; k <= 7; k++) {
    nx = (k % 7) + 1
    for (j = 0; j < n; j++) {
      t = j / n
      printf "%c[38;2;%d;%d;%dm\n", 27,
        int(R[k] + (R[nx] - R[k]) * t + 0.5),
        int(G[k] + (G[nx] - G[k]) * t + 0.5),
        int(B[k] + (B[nx] - B[k]) * t + 0.5)
    }
  }
}')

# ---- animation frame ----
# The picker animates "xhigh" and "max" on a 100ms timer. A status line only
# redraws on state changes, so the frame advances by one whenever the session
# has visibly done work since the last redraw.
#
# The signal is cost + context + transcript size. Cost and context come
# straight from this payload, so they are already current when the line is
# drawn; the transcript's mtime alone lagged, because a redraw often beats
# the new message to disk and two redraws in a row saw an unchanged file.
anim_frame() {
  local stamp state prev_stamp prev_frame frame
  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    stamp=$(stat -c %s "$transcript_path" 2>/dev/null ||
            stat -f %z "$transcript_path" 2>/dev/null)
  fi
  stamp="${cost_usd}|${ctx_pct}|${stamp}"
  [ "$stamp" = "||" ] && stamp="tick"   # no signal at all: advance every redraw
  state="${TMPDIR:-/tmp}/claude-statusline-anim-${session_id:-default}"
  if [ -r "$state" ]; then read -r prev_stamp prev_frame < "$state"; fi
  if [ "$stamp" = "$prev_stamp" ]; then
    frame=${prev_frame:-0}
  else
    frame=$(( ${prev_frame:-0} + 1 ))
    printf '%s %s\n' "$stamp" "$frame" > "$state" 2>/dev/null
  fi
  echo "$frame"
}
FRAME=$(anim_frame)

# Each segment records the separator that precedes it: "bar" for a dim
# divider, "space" for a single space, and "colon" for a tight ":" - the last
# two group a segment with the one before it.
segments=()
seps=()
add_seg() { segments+=("$1"); seps+=("${2:-bar}"); }

# gauge color: six bands from green to red, so neighbouring readings like
# 55% and 78% no longer land on the same color.
#   <30 green | <50 lime | <65 gold | <80 amber | <90 orange | 90+ red
color_for_pct() {
  local band
  band=$(awk -v p="$1" 'BEGIN{
    p += 0
    if      (p < 30) b = 0
    else if (p < 50) b = 1
    else if (p < 65) b = 2
    else if (p < 80) b = 3
    else if (p < 90) b = 4
    else             b = 5
    print b
  }')
  printf '%s' "${GAUGE[$band]}"
}

# a "<label> <NN%>" gauge segment
gauge_segment() {
  local label="$1" pct="$2" color str
  color=$(color_for_pct "$pct")
  str=$(awk -v p="$pct" 'BEGIN{printf "%.0f", p}')
  printf "${DIM}${C_LABEL}%s${RESET} ${color}%s%%${RESET}" "$label" "$str"
}

# "rainbow-animated" (max): letters sit RAINBOW_SPREAD apart on the wheel and
# the whole word rotates by RAINBOW_STEP each frame.
rainbow_text() {
  local text="$1" len n i=0 ch out=""
  len=${#text}
  n=${#RAINBOW[@]}
  while [ "$i" -lt "$len" ]; do
    ch="${text:$i:1}"
    out="${out}${RAINBOW[$(( (FRAME * RAINBOW_STEP + i * RAINBOW_SPREAD) % n ))]}${ch}"
    i=$((i + 1))
  done
  printf "${BOLD}%s${RESET}" "$out"
}

# "autoAccept-shimmer" (xhigh): a crest travels the word on a period of
# len+4, lit in #d0b4ff with its two neighbours bolded.
shimmer_text() {
  local text="$1" len period crest i=0 ch out=""
  len=${#text}
  period=$((len + 4))
  crest=$((FRAME % period))
  while [ "$i" -lt "$len" ]; do
    ch="${text:$i:1}"
    if [ "$i" -eq "$crest" ]; then
      out="${out}${RESET}${BOLD}${E_SHIMMER}${ch}"
    elif [ "$i" -eq $((crest - 1)) ] || [ "$i" -eq $((crest + 1)) ]; then
      out="${out}${RESET}${BOLD}${E_XHIGH}${ch}"
    else
      out="${out}${RESET}${E_XHIGH}${ch}"
    fi
    i=$((i + 1))
  done
  printf "%s${RESET}" "$out"
}

# ---- model name ----
[ -n "$model_name" ] &&
  add_seg "$(printf "${BOLD}${C_CLAUDE}%s${RESET}" "$model_name")" bar

# ---- effort level, in the /effort picker's per-level color ----
# low/medium/high render at normal weight; the animated levels stay bold.
if [ -n "$effort_level" ]; then
  case "$effort_level" in
    low)       effort_seg=$(printf "${E_LOW}low${RESET}") ;;
    medium)    effort_seg=$(printf "${E_MEDIUM}medium${RESET}") ;;
    high)      effort_seg=$(printf "${E_HIGH}high${RESET}") ;;
    xhigh)     effort_seg=$(shimmer_text "xhigh") ;;
    max)       effort_seg=$(rainbow_text "max") ;;
    ultracode) effort_seg=$(printf "${BOLD}${E_ULTRA_BG}${E_ULTRA_FG} ultracode ${RESET}") ;;
    *)         effort_seg=$(printf "${BOLD}${C_LABEL}%s${RESET}" "$effort_level") ;;
  esac
  add_seg "$effort_seg" space
fi

# ---- context window used %, grouped with the effort level ----
[ -n "$ctx_pct" ] && add_seg "$(gauge_segment ctx "$ctx_pct")" space

# ---- user @ machine ----
# Ambient context that rarely changes, so it is rendered quietly in the label
# grey rather than competing with the path next to it.
user_name="${USER:-$(id -un 2>/dev/null)}"
host_name=$(hostname -s 2>/dev/null)
if [ -n "$user_name" ] || [ -n "$host_name" ]; then
  add_seg "$(printf "${DIM}${C_LABEL}%s@%s${RESET}" "$user_name" "$host_name")" bar
fi

# ---- directory (~-shortened, last 3 path segments) ----
path_display="$cwd"
case "$path_display" in
  "$HOME") path_display="~" ;;
  "$HOME"/*) path_display="~${path_display#"$HOME"}" ;;
esac

IFS='/' read -r -a _parts <<< "$path_display"
_n=${#_parts[@]}
if [ "$_n" -gt 3 ]; then
  path_display="…/${_parts[$((_n-3))]}/${_parts[$((_n-2))]}/${_parts[$((_n-1))]}"
fi

read_only=""
[ -d "$cwd" ] && [ ! -w "$cwd" ] && read_only=" 󰌾"

add_seg "$(printf "${C_DIR}%s${RESET}" "${path_display}${read_only}")" colon

# ---- git branch (icon + name) with dirty / ahead-behind marker ----
branch="$worktree"
[ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --quiet --short HEAD 2>/dev/null)
[ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)

if [ -n "$branch" ]; then
  status_str=""

  porcelain=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
  if [ -n "$porcelain" ]; then
    staged=0; modified=0; untracked=0; conflicted=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      x="${line:0:1}"; y="${line:1:1}"
      case "$x$y" in
        "??") untracked=1 ;;
        "UU"|"AA"|"DD") conflicted=1 ;;
        *)
          [ "$x" != " " ] && staged=1
          [ "$y" != " " ] && modified=1
          ;;
      esac
    done <<< "$porcelain"
    [ "$conflicted" = "1" ] && status_str="${status_str}="
    [ "$staged" = "1" ] && status_str="${status_str}+"
    [ "$modified" = "1" ] && status_str="${status_str}!"
    [ "$untracked" = "1" ] && status_str="${status_str}?"
  fi

  upstream=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [ -n "$upstream" ]; then
    counts=$(git -C "$cwd" --no-optional-locks rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
    behind=$(echo "$counts" | awk '{print $1}')
    ahead=$(echo "$counts" | awk '{print $2}')
    if [ "${ahead:-0}" -gt 0 ] 2>/dev/null && [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
      status_str="${status_str}<>"
    elif [ "${ahead:-0}" -gt 0 ] 2>/dev/null; then
      status_str="${status_str}>"
    elif [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
      status_str="${status_str}<"
    fi
  fi

  git_seg=$(printf "${C_BRANCH} %s${RESET}" "$branch")
  [ -n "$status_str" ] && git_seg="${git_seg}$(printf "${C_ERR}[%s]${RESET}" "$status_str")"
  add_seg "$git_seg" space
fi

# ---- money spent this session (authoritative value from the CLI) ----
if [ -n "$cost_usd" ]; then
  cost_str=$(awk -v c="$cost_usd" 'BEGIN{printf "%.2f", c+0}')
  add_seg "$(printf "${C_COST}\$%s${RESET}" "$cost_str")" bar
fi

# ---- rate limits: 5-hour, weekly, the model-scoped weekly (Fable), and the
# overage limit if the CLI ever exposes it. The scoped limit is labelled with
# its own display name, so it reads "Fable 7%" rather than a fixed abbreviation.
[ -n "$five_hr_pct" ] && add_seg "$(gauge_segment 5h "$five_hr_pct")" bar
[ -n "$weekly_pct" ]  && add_seg "$(gauge_segment 7d "$weekly_pct")" space
[ -n "$scoped_pct" ] && [ -n "$scoped_name" ] &&
  add_seg "$(gauge_segment "$scoped_name" "$scoped_pct")" space
[ -n "$overage_pct" ] && add_seg "$(gauge_segment ovr "$overage_pct")" space

# ---- join: dim divider between segments, one space within a group ----
# Visual width: printable characters only, escape sequences excluded.
vwidth() {
  local plain
  plain=$(printf '%s' "$1" | sed "s/$(printf '\033')\[[0-9;]*m//g")
  printf '%s' "${#plain}"
}

# Terminal width. The payload carries no width field. In practice the CLI
# exports COLUMNS to the status line process, which is the source that works;
# /dev/tty is tried first for other hosts but is normally unavailable here.
# CLAUDE_STATUSLINE_WIDTH overrides everything, and a wide default is used when
# nothing can be detected - better to under-wrap than to wrap a line that fit.
term_width() {
  local w
  for w in "$CLAUDE_STATUSLINE_WIDTH" \
           "$( (stty size < /dev/tty) 2>/dev/null | awk '{print $2}')" \
           "$COLUMNS"; do
    if [ -n "$w" ] && [ "$w" -gt 20 ] 2>/dev/null; then printf '%s' "$w"; return; fi
  done
  printf '%s' 200
}
WIDTH=$(term_width)

# Coalesce segments into units: a unit is a "bar"-separated segment plus any
# tightly-joined ("space"/"colon") segments after it. Units are what wrapping
# may split between; a group like user@host:path never breaks apart.
units=()
uwidths=()
idx=0
while [ "$idx" -lt "${#segments[@]}" ]; do
  if [ "$idx" -eq 0 ] || [ "${seps[$idx]}" = "bar" ]; then
    units+=("${segments[$idx]}")
    uwidths+=("$(vwidth "${segments[$idx]}")")
  else
    last=$(( ${#units[@]} - 1 ))
    if [ "${seps[$idx]}" = "colon" ]; then
      units[$last]="${units[$last]}${DIM}${C_LABEL}:${RESET}${segments[$idx]}"
      uwidths[$last]=$(( ${uwidths[$last]} + 1 + $(vwidth "${segments[$idx]}") ))
    else
      units[$last]="${units[$last]} ${segments[$idx]}"
      uwidths[$last]=$(( ${uwidths[$last]} + 1 + $(vwidth "${segments[$idx]}") ))
    fi
  fi
  idx=$((idx + 1))
done

# Greedy wrap: " · " (3 columns) joins units on a line; when the next
# unit would overflow, continue on the next line.
out=""
line_w=0
idx=0
while [ "$idx" -lt "${#units[@]}" ]; do
  w=${uwidths[$idx]}
  if [ "$idx" -eq 0 ]; then
    out="${units[$idx]}"
    line_w=$w
  elif [ $(( line_w + 3 + w )) -le "$WIDTH" ]; then
    out="$out ${DIM}${C_LABEL}·${RESET} ${units[$idx]}"
    line_w=$(( line_w + 3 + w ))
  else
    out="$out
${units[$idx]}"
    line_w=$w
  fi
  idx=$((idx + 1))
done

printf "%s" "$out"
