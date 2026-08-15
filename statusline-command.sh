#!/bin/bash
# Claude Code statusLine command.
#
# Segments (in order): model name, effort level, context-window usage %,
# git branch, user@machine, current directory, the pull request for that
# branch, session cost ($ spent), 5-hour and weekly rate-limit %, the
# model-scoped weekly rate-limit % (Fable), and - if the CLI ever exposes
# it - the overage limit %.
#
# They are always emitted as one line, in that order. Nothing is wrapped or
# re-flowed here; a window too narrow for the whole line simply clips its tail.
# See the join at the bottom of the file for why measuring is the worse option.
#
# Colors started as the literal Claude theme palettes read out of the
# installed CLI (v2.1.231), reconciled into the single palette below - see
# the palette section for why the theme is not detected at all.

input=$(cat)

IFS=$'\t' read -r cwd worktree model_name effort_level cost_usd ctx_pct five_hr_pct weekly_pct overage_pct session_id transcript_path pr_number pr_kind pr_review scoped_pct scoped_name <<<"$(
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
      (.pr.number // "-"),
      (.pr.kind // "-"),
      (.pr.review_state // "-"),
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
pr_number=$(unset_if_dash "$pr_number")
pr_kind=$(unset_if_dash "$pr_kind")
pr_review=$(unset_if_dash "$pr_review")
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

# ---- palette ----
# One palette, not two. The theme cannot be detected reliably from inside a
# status line: COLORFGBG is captured when the shell starts and never updates
# when the terminal's theme changes under a running session, and a remote host
# forwards neither it nor macOS's appearance setting. A palette picked from a
# stale signal is wrong exactly when it matters, so every color here is instead
# chosen to clear roughly 3.5:1 contrast against both white and black. The hues
# are the Claude theme's, pulled to the midpoint of its two palettes.
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
fg() { printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"; }

C_CLAUDE=$(fg 215 119 87)    # "claude" terracotta - model name
C_DIR=$(fg 14 140 158)       # cyan - cwd
C_BRANCH=$(fg 186 92 124)    # rose - git branch
C_COST=$(fg 176 128 18)      # "warning" amber - money spent
C_LABEL=$(fg 128 128 128)    # "inactive" - labels
C_ERR=$(fg 208 72 94)        # "error" - git dirty marker
C_MERGED=$(fg 150 90 235)    # "merged" - a merged PR
C_PR=$(fg 71 130 200)        # "ide" blue - an open PR with no verdict yet
# gauge ramp, green -> red, anchored on "success"/"warning"/"error"
GAUGE=("$(fg 46 140 64)" "$(fg 110 150 45)" "$(fg 176 128 18)"
       "$(fg 196 110 30)" "$(fg 206 84 60)" "$(fg 203 60 80)")
# /effort picker colors, one per level (see Kvl in the CLI). Deliberately
# identical whatever the terminal's theme is, so a level always reads as the
# same color.
E_LOW=$(fg 176 128 18)       # "warning"
E_MEDIUM=$(fg 46 140 64)     # "success"
E_HIGH=$(fg 110 125 240)     # "permission"
E_XHIGH=$(fg 150 90 235)     # "autoAccept" (base under the shimmer)

# "violet-ripple" (ultracode) and the "rainbow-animated" cycle (max) are
# hardcoded in the CLI rather than themed. The CLI can afford pastels because
# it only ever paints them on its own background; these are the same hues held
# to the contrast floor the rest of the palette keeps.
E_SHIMMER=$(fg 168 120 245)   # the shimmer crest: the CLI's #d0b4ff darkened
                              # enough to stay visible on a white background
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
  split("214,82,74 216,118,60 190,140,30 96,160,88 82,130,200 140,110,200 190,100,160", stops, " ")
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

# Each segment records the separator that precedes it:
#   bar        dim " · " divider between two groups
#   bar_tight  the same " · " divider, but bound to the previous segment
#   space      a single space, bound to the previous segment
#   colon      a tight ":", bound to the previous segment
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
  add_seg "$git_seg" bar
  loc_started=1
fi

# ---- user @ machine ----
# Ambient context that rarely changes, so it is rendered quietly in the label
# grey rather than competing with the path next to it.
user_name="${USER:-$(id -un 2>/dev/null)}"
host_name=$(hostname -s 2>/dev/null)
if [ -n "$user_name" ] || [ -n "$host_name" ]; then
  add_seg "$(printf "${DIM}${C_LABEL}%s@%s${RESET}" "$user_name" "$host_name")" "${loc_started:+space}"
  host_shown=1
  loc_started=1
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

# ":" only reads as a path separator directly after the host; behind the
# branch alone it would be nonsense, and first in the group it needs the
# divider the other groups get.
if   [ -n "$host_shown" ];  then dir_sep=colon
elif [ -n "$loc_started" ]; then dir_sep=space
else                             dir_sep=bar
fi
add_seg "$(printf "${C_DIR}%s${RESET}" "${path_display}${read_only}")" "$dir_sep"

# ---- pull request for the current branch ----
# Present only when the CLI resolved a PR (it shells out to `gh`, so this stays
# invisible without gh installed and authenticated). Merged/closed outrank a
# review verdict, which in turn outranks plain draft/open.
if [ -n "$pr_number" ]; then
  pr_label=""
  case "$pr_kind" in
    merged) pr_color="$C_MERGED"; pr_label="merged" ;;
    closed) pr_color="$C_ERR";    pr_label="closed" ;;
    *)
      case "$pr_review" in
        approved)          pr_color="${GAUGE[0]}"; pr_label="approved" ;;
        changes_requested) pr_color="${GAUGE[3]}"; pr_label="changes" ;;
        *)
          if [ "$pr_kind" = "draft" ]; then
            pr_color="$C_LABEL"; pr_label="draft"
          else
            pr_color="$C_PR"
          fi
          ;;
      esac
      ;;
  esac
  if [ -n "$pr_label" ]; then
    add_seg "$(printf "${pr_color}#%s${RESET} ${DIM}${C_LABEL}%s${RESET}" "$pr_number" "$pr_label")" bar
  else
    add_seg "$(printf "${pr_color}#%s${RESET}" "$pr_number")" bar
  fi
fi

# ---- money spent this session (authoritative value from the CLI) ----
if [ -n "$cost_usd" ]; then
  cost_str=$(awk -v c="$cost_usd" 'BEGIN{printf "%.2f", c+0}')
  add_seg "$(printf "${C_COST}\$%s${RESET}" "$cost_str")" bar
fi

# ---- rate limits, kept on the same line as the cost ----
# The model-scoped limit is labelled with its own display name, so it reads
# "Fable 7%" rather than a fixed abbreviation, and follows a rename by itself.
[ -n "$five_hr_pct" ] && add_seg "$(gauge_segment 5h "$five_hr_pct")" bar_tight
[ -n "$weekly_pct" ]  && add_seg "$(gauge_segment 7d "$weekly_pct")" space
[ -n "$scoped_pct" ] && [ -n "$scoped_name" ] &&
  add_seg "$(gauge_segment "$scoped_name" "$scoped_pct")" space
[ -n "$overage_pct" ] && add_seg "$(gauge_segment ovr "$overage_pct")" space



# ---- join: dim divider between segments, one space within a group ----
#
# The line is emitted whole, at whatever length it comes to, and is never
# pre-wrapped to a measured terminal width. The CLI renders each status line
# with wrap="truncate", so a line too wide for the window is clipped by the
# terminal on the way out - which costs only the tail (the rate-limit gauges),
# and costs nothing at all at any width the content already fits.
#
# Measuring instead would be worse, not better. The CLI re-runs this command
# when session state changes - a new message, a token count, a model or effort
# switch - and a terminal resize is not one of those triggers. A layout chosen
# from the width at render time therefore survives the resize that invalidated
# it, and an idle session can sit on a two-line split long after the window
# grew wide enough for one. Clipping is re-evaluated by the terminal on every
# repaint, so it is always current.
out=""
idx=0
while [ "$idx" -lt "${#segments[@]}" ]; do
  if [ "$idx" -eq 0 ]; then
    out="${segments[$idx]}"
  else
    case "${seps[$idx]}" in
      colon) out="${out}${DIM}${C_LABEL}:${RESET}${segments[$idx]}" ;;
      space) out="${out} ${segments[$idx]}" ;;
      *)     out="${out} ${DIM}${C_LABEL}·${RESET} ${segments[$idx]}" ;;
    esac
  fi
  idx=$((idx + 1))
done
printf '%s' "$out"