#!/usr/bin/env bash
# Claude Code statusLine command.
#
# Two lines. The first: model name, effort level, context-window usage %,
# session cost ($ spent) with the account's usage-credit balance ((used/limit),
# from the local usage cache), 5-hour and weekly rate-limit %, the model-scoped
# weekly rate-limit % (Fable), and the overage limit % (if the CLI ever exposes
# it in the live payload). The second: git branch, user@machine, current
# directory.
#
# Nothing is wrapped or re-flowed here; a window too narrow for a line simply
# clips its tail.
# See the join at the bottom of the file for why measuring is the worse option.
#
# Colors are the literal Claude theme palettes read out of the installed CLI
# (v2.1.239). The /effort ramp, the labels, the git-dirty marker, and the gauge
# follow the active theme; the remaining hues are one palette that holds on
# either background - see the palette section.
#
# Portability: bash 3.2 and POSIX tools, because macOS still ships bash 3.2 and
# the CLI runs this through whatever "bash" is on PATH. So no associative
# arrays, no "grep -P", and nothing that assumes GNU over BSD flags - the two
# places where the implementations genuinely differ (stat, hostname) each carry
# both spellings. Beyond bash the script needs jq, awk, and git; without jq the
# payload simply reads empty and the line falls back to what it can derive
# locally, rather than failing.

input=$(cat)

# awk does every number this line formats, and awk's printf follows LC_NUMERIC:
# under a comma locale the cost renders "$1,23" and the gauges pick up the same
# separator. Reading is unaffected - a -v assignment is converted in the C
# locale either way - so pinning the whole call is enough, and safe: every awk
# program here emits ASCII and escape codes only.
awk() { LC_ALL=C command awk "$@"; }

IFS=$'\t' read -r cwd worktree model_name effort_level cost_usd ctx_pct five_hr_pct weekly_pct overage_pct session_id transcript_path scoped_pct scoped_name <<<"$(
  printf '%s\n' "$input" | jq -r '
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

# The stdin payload's rate_limits carry only percentages (five_hour, seven_day,
# and the model-scoped weekly limit above) - never an absolute balance. The one
# absolute figure the CLI has - the account's usage-credit balance, used/limit in
# dollars - is not in the payload at all; it lives only in the same usage cache
# read above, fetched periodically rather than per redraw. So it is read from
# there, exactly like the scoped weekly limit's fallback, and simply omitted
# for accounts where the credit program is not enabled (spend.enabled false).
credits_used_minor=""; credits_limit_minor=""; credits_exp=""; credits_pct=""
if [ -f "$HOME/.claude.json" ]; then
  IFS=$'\t' read -r credits_used_minor credits_limit_minor credits_exp credits_pct <<<"$(
    jq -r '
      .cachedUsageUtilization.utilization.spend as $s
      | if ($s != null) and ($s.enabled == true)
           and ($s.used.amount_minor != null) and ($s.limit.amount_minor != null)
        then [$s.used.amount_minor, $s.limit.amount_minor,
              ($s.used.exponent // 2), ($s.percent // 0)] | @tsv
        else empty end' "$HOME/.claude.json" 2>/dev/null
  )"
fi

# ---- palette ----
# Every color here is the CLI's own, read out of the theme table in the installed
# binary (v2.1.239) and held in TH under the CLI's key names. The table carries
# the same 5 value formats the CLI accepts, and sgr_for() turns each into an
# escape at the end.
#
# /theme writes its choice to settings.json before the next redraw, so that file
# is the signal - not COLORFGBG, which is captured when the shell starts and
# never updates. "auto" is the one theme this cannot follow: the CLI resolves it
# with an OSC 11 background query, and a status line cannot query a terminal
# whose stdout it is writing. It falls back to dark.
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'

# The theme name lives in settings.json, read with jq rather than a regex so the
# whole file's one parser handles it. A local settings file wins over the user's.
theme=$(jq -r '.theme // empty' "$HOME/.claude/settings.json" 2>/dev/null)
if [ -f "$HOME/.claude/settings.local.json" ]; then
  _t=$(jq -r '.theme // empty' "$HOME/.claude/settings.local.json" 2>/dev/null)
  [ -n "$_t" ] && theme=$_t
fi

# A custom theme is written "custom:<slug>" and lives in ~/.claude/themes as
# <slug>.json, holding { "base": <built-in name>, "overrides": { key: color } }.
# The CLI takes the base's palette and merges the overrides over it, keeping only
# keys the base already carries. An unreadable file or an unknown base means dark.
# A theme a plugin supplies has no file here, so it lands on the same fallback.
_ovr=""
case "$theme" in
  custom:*)
    _base=""
    _tf="$HOME/.claude/themes/${theme#custom:}.json"
    if [ -r "$_tf" ]; then
      _base=$(jq -r '.base // empty' "$_tf" 2>/dev/null)
      _ovr=$(jq -r '(.overrides // {}) | to_entries[] | "\(.key) \(.value)"' "$_tf" 2>/dev/null)
    fi
    case "$_base" in
      dark|light|dark-ansi|light-ansi|dark-daltonized|light-daltonized) theme=$_base ;;
      *) theme=dark ;;
    esac ;;
esac

# The keys behind each segment:
#
#   /effort    low "warning" | medium "success" | high "permission"
#              xhigh "autoAccept-shimmer" | max the 7 "rainbow_*"
#              ultracode "violet-ripple"
#   model      "claude"
#   labels     "inactive"
#   git dirty  "error"
#   gauge      "success" -> "warning" -> "error"
#
# The /effort key names are borrowed hues, not meanings: the picker wanted an
# escalating ramp and reached for the palette entries sitting on it. The gauge's
# 3 are the same kind of borrowing: no CLI element colors a percentage, so the
# ramp takes the palette entries that sit on the arc it wants.
#
# The cwd and the branch stay out of the table. The only keys near their hues are
# cyan_FOR_SUBAGENTS_ONLY and pink_FOR_SUBAGENTS_ONLY, which the CLI reserves
# for subagent labels by name, and neither segment mirrors a CLI element that
# would settle the question.
#
# Each entry is one TH_<key> variable rather than an array element: macOS ships
# bash 3.2, which has no associative arrays, and this script has to run there.
# TH_KEYS is the list of keys the table carries, which is also what decides
# whether a custom theme's override is one the base has.
#
# GAUGE_MODE says how the gauge gets 6 bands out of its 3 anchors, and the
# reason differs per theme. See the gauge section below.
TH_KEYS="warning success permission autoAccept claude inactive error
         rainbow_red rainbow_orange rainbow_yellow rainbow_green
         rainbow_blue rainbow_indigo rainbow_violet"
case "$theme" in
  light)
    TH_warning="rgb(150,108,30)"; TH_success="rgb(44,122,57)"
    TH_permission="rgb(87,105,247)"; TH_autoAccept="rgb(135,0,255)"
    TH_claude="rgb(215,119,87)"
    TH_inactive="rgb(102,102,102)"; TH_error="rgb(171,43,63)"
    GAUGE_MODE=interp ;;
  light-daltonized)
    TH_warning="rgb(255,153,0)"; TH_success="rgb(0,102,153)"
    TH_permission="rgb(51,102,255)"; TH_autoAccept="rgb(135,0,255)"
    TH_claude="rgb(255,153,51)"
    TH_inactive="rgb(102,102,102)"; TH_error="rgb(204,0,0)"
    GAUGE_MODE=pale ;;
  dark-daltonized)
    TH_warning="rgb(255,204,0)"; TH_success="rgb(51,153,255)"
    TH_permission="rgb(153,204,255)"; TH_autoAccept="rgb(175,135,255)"
    TH_claude="rgb(255,153,51)"
    TH_inactive="rgb(153,153,153)"; TH_error="rgb(255,102,102)"
    GAUGE_MODE=dim ;;
  dark-ansi)
    TH_warning="ansi:yellowBright"; TH_success="ansi:greenBright"
    TH_permission="ansi:blueBright"; TH_autoAccept="ansi:magentaBright"
    TH_claude="ansi:redBright"
    TH_inactive="ansi:white"; TH_error="ansi:redBright"
    GAUGE_MODE=pairs ;;
  light-ansi)
    TH_warning="ansi:yellow"; TH_success="ansi:green"
    TH_permission="ansi:blue"; TH_autoAccept="ansi:magenta"
    TH_claude="ansi:redBright"
    TH_inactive="ansi:blackBright"; TH_error="ansi:red"
    GAUGE_MODE=pairs ;;
  *)  # dark, plus "auto" and anything unrecognised
    TH_warning="rgb(255,193,7)"; TH_success="rgb(78,186,101)"
    TH_permission="rgb(177,185,249)"; TH_autoAccept="rgb(175,135,255)"
    TH_claude="rgb(215,119,87)"
    TH_inactive="rgb(153,153,153)"; TH_error="rgb(255,107,128)"
    GAUGE_MODE=interp ;;
esac

# The 7 rainbow_* keys hold the same pastels in all 4 truecolor themes and the
# same 7 terminal colors in both ansi themes, so they need no per-theme branch.
case "$theme" in
  dark-ansi|light-ansi)
    TH_rainbow_red="ansi:red";      TH_rainbow_orange="ansi:redBright"
    TH_rainbow_yellow="ansi:yellow"; TH_rainbow_green="ansi:green"
    TH_rainbow_blue="ansi:cyan";    TH_rainbow_indigo="ansi:blue"
    TH_rainbow_violet="ansi:magenta" ;;
  *)
    TH_rainbow_red="rgb(235,95,87)";     TH_rainbow_orange="rgb(245,139,87)"
    TH_rainbow_yellow="rgb(250,195,95)"; TH_rainbow_green="rgb(145,200,130)"
    TH_rainbow_blue="rgb(130,170,220)";  TH_rainbow_indigo="rgb(155,130,200)"
    TH_rainbow_violet="rgb(200,130,180)" ;;
esac

# Merge a custom theme's overrides, on the CLI's 2 conditions: the base already
# carries the key, and the value is one of the 5 accepted forms.
if [ -n "$_ovr" ]; then
  while read -r _k _v; do
    [ -n "$_k" ] || continue
    case " $TH_KEYS " in *[[:space:]]"$_k"[[:space:]]*) ;; *) continue ;; esac
    case "$_v" in
      'rgb('*')'|'ansi256('*')'|'ansi:'*) printf -v "TH_$_k" '%s' "$_v" ;;
      '#'*) case ${#_v} in 4|7) printf -v "TH_$_k" '%s' "$_v" ;; esac ;;
    esac
  done <<<"$_ovr"
fi

# ---- color values to escapes ----
# The 5 forms the CLI accepts: rgb(r,g,b), #rrggbb, #rgb, ansi256(n), ansi:name.
ansi_code() {
  case "$1" in
    black) printf 30 ;; red) printf 31 ;; green) printf 32 ;; yellow) printf 33 ;;
    blue) printf 34 ;; magenta) printf 35 ;; cyan) printf 36 ;; white) printf 37 ;;
    blackBright) printf 90 ;; redBright) printf 91 ;;
    greenBright) printf 92 ;; yellowBright) printf 93 ;;
    blueBright) printf 94 ;; magentaBright) printf 95 ;;
    cyanBright) printf 96 ;; whiteBright) printf 97 ;;
    *) printf 39 ;;
  esac
}

fg() { printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"; }
sgr() { printf '\033[%sm' "$1"; }

# rgb_of prints "r g b", or nothing when the value names a color instead of
# giving one. The gauge needs numbers, so it checks for an empty result.
rgb_of() {
  local v=$1 h
  case "$v" in
    'rgb('*')') v=${v#rgb(}; v=${v%)}; printf '%s' "${v//,/ }" ;;
    '#'*)
      h=${v#\#}
      if [ ${#h} = 3 ]; then
        printf '%d %d %d' "0x${h:0:1}${h:0:1}" "0x${h:1:1}${h:1:1}" "0x${h:2:1}${h:2:1}"
      elif [ ${#h} = 6 ]; then
        printf '%d %d %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
      fi ;;
  esac
}

sgr_for() {
  local v=$1 rgb
  case "$v" in
    'ansi256('*')') v=${v#ansi256(}; sgr "38;5;${v%)}" ; return ;;
    'ansi:'*) sgr "$(ansi_code "${v#ansi:}")"; return ;;
  esac
  rgb=$(rgb_of "$v")
  [ -n "$rgb" ] && fg $rgb
}

C_CLAUDE=$(sgr_for "$TH_claude")     # model name
C_LABEL=$(sgr_for "$TH_inactive")    # labels
C_ERR=$(sgr_for "$TH_error")         # git dirty marker

# Fixed hues, chosen to clear roughly 3:1 contrast against both white and black
# so they hold up on either background.
C_DIR=$(fg 14 140 158)     # cyan - cwd
C_BRANCH=$(fg 186 92 124)  # rose - git branch
C_COST=$(fg 107 128 104)   # sage #6b8068 - money spent

E_LOW=$(sgr_for "$TH_warning")        # every level is bold, as the picker
E_MEDIUM=$(sgr_for "$TH_success")     # draws the selected one
E_HIGH=$(sgr_for "$TH_permission")
E_XHIGH=$(sgr_for "$TH_autoAccept")   # the base under the shimmer

# ---- gauge ----
# Six bands out of 3 anchors: "success", "warning", "error". How depends on how
# far apart the anchors sit, which is a property of the theme, so GAUGE_MODE is
# set with the palette above.
#
#   interp   dark and light. Their anchors run green to gold to red, so a blend
#            of 2 neighbours stays on that arc. Bands 0, 2, and 5 are the
#            anchors, band 1 sits halfway between the first 2, and bands 3 and 4
#            split the longer run to the third into thirds.
#   dim      dark-daltonized, and pale for light-daltonized. Their anchors are
#   pale     blue and yellow, which are complements, so an interpolated midpoint
#            desaturates to green. A daltonized palette signals state with blue
#            against yellow so the ramp never leans on green, and putting green
#            back in the middle of it defeats that. Each anchor takes 2 bands
#            instead: a weakened step, then the anchor itself. Weakened means
#            0.65x toward black on the dark theme and 45% toward white on the
#            light one, so on either background the second band is the louder.
#   pairs    the 2 ansi themes. A named color has no arithmetic, so each anchor
#            pairs with its bright or normal sibling.
#
# Every mode but interp puts the weaker band of each pair first, so a rising
# reading always moves toward the louder color.
#
# An override can leave a truecolor theme's anchor unusable for arithmetic, by
# naming an ansi color. That falls through to pairs as well, on the anchor names.
_ga=$(rgb_of "$TH_success"); _gb=$(rgb_of "$TH_warning"); _gc=$(rgb_of "$TH_error")
[ -n "$_ga" ] && [ -n "$_gb" ] && [ -n "$_gc" ] || GAUGE_MODE=pairs
case "$GAUGE_MODE" in
  pairs)
    # The sibling of a bright color is its normal form and vice versa; a
    # truecolor anchor that got here has no sibling, so it repeats.
    _sib() {
      local v=${1#ansi:} n
      case "$v" in
        *Bright) n=${v%Bright} ;;
        black|red|green|yellow|blue|magenta|cyan|white) n="${v}Bright" ;;
        *) sgr_for "$1"; return ;;
      esac
      sgr "$(ansi_code "$n")"
    }
    GAUGE=()
    for _k in success warning error; do
      _n="TH_$_k"
      GAUGE+=("$(_sib "${!_n}")" "$(sgr_for "${!_n}")")
    done ;;
  *)
    GAUGE=()
    while IFS= read -r _l; do GAUGE+=("$_l"); done < <(
      awk -v a="$_ga" -v b="$_gb" -v c="$_gc" -v mode="$GAUGE_MODE" 'BEGIN{
        split(a, A, " "); split(b, B, " "); split(c, C, " ")
        for (i = 1; i <= 3; i++) { R[1] = A[1]; G[1] = A[2]; Bl[1] = A[3]
                                   R[2] = B[1]; G[2] = B[2]; Bl[2] = B[3]
                                   R[3] = C[1]; G[3] = C[2]; Bl[3] = C[3] }
        if (mode == "interp") {
          split("1,0 1,0.5 2,0 2,0.33333 2,0.66667 3,0", band, " ")
          for (i = 1; i <= 6; i++) {
            split(band[i], q, ",")
            k = q[1] + 0; t = q[2] + 0; nx = (k < 3 ? k + 1 : 3)
            emit(R[k] + (R[nx] - R[k]) * t, G[k] + (G[nx] - G[k]) * t,
                 Bl[k] + (Bl[nx] - Bl[k]) * t)
          }
        } else {
          # 2 bands per anchor: a weakened step, then the anchor itself.
          for (k = 1; k <= 3; k++) {
            if (mode == "dim")
              emit(R[k] * 0.65, G[k] * 0.65, Bl[k] * 0.65)
            else
              emit(R[k] + (255 - R[k]) * 0.45, G[k] + (255 - G[k]) * 0.45,
                   Bl[k] + (255 - Bl[k]) * 0.45)
            emit(R[k], G[k], Bl[k])
          }
        }
      }
      function emit(r, g, b) {
        printf "%c[38;2;%d;%d;%dm\n", 27, int(r + 0.5), int(g + 0.5), int(b + 0.5)
      }') ;;
esac

# The shimmer crest and "violet-ripple" (ultracode) are literals in the CLI
# rather than theme keys, so they hold one value in every theme and are copied
# verbatim. The ripple's gradient runs rgb(62,22,118) -> rgb(140,80,240); the
# status line only ever shows the settled end, which is the picker's fill for
# the selected row.
E_SHIMMER=$(fg 208 180 255)   # the crest, the CLI's #d0b4ff
E_ULTRA_BG=$'\033[48;2;140;80;240m'
E_ULTRA_FG=$'\033[38;2;255;255;255m'

# "rainbow-animated" (max). The picker has 7 hue stops and spins them fast
# enough to read as flow; at one frame per message those stops land as three
# clashing letters. So the stops are interpolated into a finer wheel: the
# word becomes a smooth slice of gradient, and each frame rotates it by a
# full stop - subtle within the word, obvious between messages.
#
# Interpolating needs numbers. The 2 ansi themes name their stops instead, and so
# can a custom theme's override, so the wheel falls back to the 7 stops
# themselves, advancing one stop per frame.
RAINBOW_STOPS=""
for _k in red orange yellow green blue indigo violet; do
  _n="TH_rainbow_$_k"; _r=$(rgb_of "${!_n}")
  [ -z "$_r" ] && { RAINBOW_STOPS=""; break; }
  RAINBOW_STOPS="$RAINBOW_STOPS ${_r// /,}"
done
if [ -z "$RAINBOW_STOPS" ]; then
  RAINBOW=()
  for _k in red orange yellow green blue indigo violet; do
    _n="TH_rainbow_$_k"; RAINBOW+=("$(sgr_for "${!_n}")")
  done
  RAINBOW_SPREAD=2            # wheel positions between neighbouring letters
  RAINBOW_STEP=1              # wheel positions advanced per frame
else
  RAINBOW_SUBSTEPS=6          # interpolated colors between adjacent stops
  RAINBOW_SPREAD=3
  RAINBOW_STEP=$RAINBOW_SUBSTEPS
  RAINBOW=()
  while IFS= read -r _c; do RAINBOW+=("$_c"); done < <(
    awk -v n="$RAINBOW_SUBSTEPS" -v s="$RAINBOW_STOPS" 'BEGIN{
      split(s, stops, " ")
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
fi

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
#   newline    starts the second line
segments=()
seps=()
add_seg() { segments+=("$1"); seps+=("${2:-bar}"); }

# gauge color: six bands from "success" to "error", so neighbouring readings
# like 55% and 78% no longer land on the same color. The thresholds are
#   <30 | <50 | <65 | <80 | <90 | 90+
# and the hues come from GAUGE, which the theme decides.
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

# a "(used/limit)" gauge segment - same ramp as gauge_segment, but for an
# absolute used/limit balance (minor units + exponent) rather than a percentage
credits_segment() {
  local used_minor="$1" limit_minor="$2" exp="$3" pct="$4" color str
  color=$(color_for_pct "$pct")
  str=$(awk -v u="$used_minor" -v l="$limit_minor" -v e="$exp" \
    'BEGIN{d=10^e; printf "(%.0f/%.0f)", u/d, l/d}')
  printf "${color}%s${RESET}" "$str"
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

# "autoAccept-shimmer" (xhigh): a crest travels the word on a period of len+4,
# lit in #d0b4ff against the autoAccept base.
#
# The CLI also passes bold per character - true on the crest and its two
# neighbours, false elsewhere - but that flag never reaches the terminal: the
# word is wrapped in one bold Text and Ink emits no bold-off code, so the
# wrapper bolds every letter and the per-character flag is dead. Measured off
# the picker: a neighbour and a non-neighbour glyph are pixel-identical. So the
# crest is a color event only, and the whole word is bold.
shimmer_text() {
  local text="$1" len period crest i=0 ch out=""
  len=${#text}
  period=$((len + 4))
  crest=$((FRAME % period))
  while [ "$i" -lt "$len" ]; do
    ch="${text:$i:1}"
    if [ "$i" -eq "$crest" ]; then
      out="${out}${E_SHIMMER}${ch}"
    else
      out="${out}${E_XHIGH}${ch}"
    fi
    i=$((i + 1))
  done
  printf "${BOLD}%s${RESET}" "$out"
}

# ---- model name ----
[ -n "$model_name" ] &&
  add_seg "$(printf "${BOLD}${C_CLAUDE}%s${RESET}" "$model_name")" bar

# ---- effort level, in the /effort picker's per-level color ----
if [ -n "$effort_level" ]; then
  case "$effort_level" in
    low)       effort_seg=$(printf "${BOLD}${E_LOW}low${RESET}") ;;
    medium)    effort_seg=$(printf "${BOLD}${E_MEDIUM}medium${RESET}") ;;
    high)      effort_seg=$(printf "${BOLD}${E_HIGH}high${RESET}") ;;
    xhigh)     effort_seg=$(shimmer_text "xhigh") ;;
    max)       effort_seg=$(rainbow_text "max") ;;
    ultracode) effort_seg=$(printf "${BOLD}${E_ULTRA_BG}${E_ULTRA_FG} ultracode ${RESET}") ;;
    *)         effort_seg=$(printf "${BOLD}${C_LABEL}%s${RESET}" "$effort_level") ;;
  esac
  add_seg "$effort_seg" space
fi

# ---- context window used %, grouped with the effort level ----
# The label is nf-md-database_outline (U+F1632), the same Material Design set
# the read-only lock above comes from. It needs a Nerd Font; the two gauges
# below stay lettered, so a terminal without one loses this glyph and nothing
# else. Nothing here measures display width - the line is emitted whole and
# clipped by the terminal - so a one-cell glyph in place of three letters is
# purely a rendering change.
[ -n "$ctx_pct" ] && add_seg "$(gauge_segment "󱘲" "$ctx_pct")" space

# ---- money spent this session (authoritative value from the CLI), with the
# account's usage-credit balance bound tightly to it: "$1.23(1502/3000)" ----
money_seg=""
if [ -n "$cost_usd" ]; then
  cost_str=$(awk -v c="$cost_usd" 'BEGIN{printf "%.2f", c+0}')
  money_seg=$(printf "${C_COST}\$%s${RESET}" "$cost_str")
fi
if [ -n "$credits_used_minor" ] && [ -n "$credits_limit_minor" ]; then
  money_seg="${money_seg}$(credits_segment "$credits_used_minor" \
    "$credits_limit_minor" "$credits_exp" "$credits_pct")"
fi
[ -n "$money_seg" ] && add_seg "$money_seg" bar

# ---- rate limits, kept on the same line as the cost ----
# The model-scoped limit is labelled with its own display name, so it reads
# "Fable 7%" rather than a fixed abbreviation, and follows a rename by itself.
[ -n "$five_hr_pct" ] && add_seg "$(gauge_segment 5h "$five_hr_pct")" bar_tight
[ -n "$weekly_pct" ]  && add_seg "$(gauge_segment 7d "$weekly_pct")" space
[ -n "$scoped_pct" ] && [ -n "$scoped_name" ] &&
  add_seg "$(gauge_segment "$scoped_name" "$scoped_pct")" space
[ -n "$overage_pct" ] && add_seg "$(gauge_segment ovr "$overage_pct")" space

# ---- second line: git branch, user@machine, directory ----
# The group always opens a new line, whichever of its segments renders first.

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
  add_seg "$git_seg" newline
  loc_started=1
fi

# ---- user @ machine ----
# Ambient context that rarely changes, so it is rendered quietly in the label
# grey rather than competing with the path next to it.
user_name="${USER:-$(id -un 2>/dev/null)}"
# "hostname -s" is the short name on macOS, GNU inetutils, and busybox alike,
# but a stripped-down container may carry no hostname binary at all; bash's own
# HOSTNAME is the fallback, trimmed of any domain the same way.
host_name=$(hostname -s 2>/dev/null)
[ -z "$host_name" ] && host_name="${HOSTNAME%%.*}"
if [ -n "$user_name" ] || [ -n "$host_name" ]; then
  add_seg "$(printf "${DIM}${C_LABEL}%s@%s${RESET}" "$user_name" "$host_name")" \
    "$([ -n "$loc_started" ] && echo space || echo newline)"
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
# branch alone it would be nonsense, and first in the group it opens the line.
if   [ -n "$host_shown" ];  then dir_sep=colon
elif [ -n "$loc_started" ]; then dir_sep=space
else                             dir_sep=newline
fi
add_seg "$(printf "${C_DIR}%s${RESET}" "${path_display}${read_only}")" "$dir_sep"

# ---- join: dim divider between segments, one space within a group ----
#
# Each line is emitted whole, at whatever length it comes to, and is never
# pre-wrapped to a measured terminal width. The CLI renders each status line
# with wrap="truncate", so a line too wide for the window is clipped by the
# terminal on the way out - which costs only its tail (the rate-limit gauges on
# the first, the path on the second), and costs nothing at all at any width the
# content already fits.
#
# Measuring instead would be worse, not better. The CLI re-runs this command
# when session state changes - a new message, a token count, a model or effort
# switch - and a terminal resize is not one of those triggers. A layout chosen
# from the width at render time therefore survives the resize that invalidated
# it, and an idle session can sit on a wrapped line long after the window
# grew wide enough to hold it. Clipping is re-evaluated by the terminal on every
# repaint, so it is always current.
out=""
idx=0
while [ "$idx" -lt "${#segments[@]}" ]; do
  if [ "$idx" -eq 0 ]; then
    out="${segments[$idx]}"
  else
    case "${seps[$idx]}" in
      colon)   out="${out}${DIM}${C_LABEL}:${RESET}${segments[$idx]}" ;;
      newline) out="${out}"$'\n'"${segments[$idx]}" ;;
      space)   out="${out} ${segments[$idx]}" ;;
      *)       out="${out} ${DIM}${C_LABEL}·${RESET} ${segments[$idx]}" ;;
    esac
  fi
  idx=$((idx + 1))
done
printf '%s' "$out"
