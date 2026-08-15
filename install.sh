#!/usr/bin/env bash
# Installs the Claude Code status line on this machine.
#
#   ./install.sh            install to ~/.claude and wire up settings.json
#   ./install.sh --dry-run  show what would happen, change nothing
#
# Existing settings.json is preserved: only the "statusLine" key is replaced,
# and a timestamped backup is written alongside it.
set -euo pipefail

src_dir=$(cd "$(dirname "$0")" && pwd)
src="$src_dir/statusline-command.sh"
dest_dir="$HOME/.claude"
dest="$dest_dir/statusline-command.sh"
settings="$dest_dir/settings.json"
dry_run=false
[ "${1:-}" = "--dry-run" ] && dry_run=true

say() { printf '%s\n' "$*"; }
run() { if $dry_run; then say "  would: $*"; else eval "$@"; fi; }

command -v jq >/dev/null 2>&1 || {
  say "error: jq is required (brew install jq / apt install jq)"; exit 1; }
[ -f "$src" ] || { say "error: statusline-command.sh not found next to install.sh"; exit 1; }

say "installing to $dest"
run "mkdir -p '$dest_dir'"
run "cp '$src' '$dest'"

stamp=$(date +%Y%m%d-%H%M%S)
if [ -f "$settings" ]; then
  say "merging statusLine into existing $settings (backup: settings.json.$stamp.bak)"
  run "cp '$settings' '$settings.$stamp.bak'"
  run "jq --arg c \"bash \$HOME/.claude/statusline-command.sh\" \
        '.statusLine = {type:\"command\", command:\$c}' '$settings' > '$settings.new'"
  run "mv '$settings.new' '$settings'"
else
  say "creating $settings"
  run "printf '%s\n' '{\"statusLine\":{\"type\":\"command\",\"command\":\"bash '\$HOME'/.claude/statusline-command.sh\"}}' | jq . > '$settings'"
fi

$dry_run && { say "dry run complete, nothing changed"; exit 0; }

say ""
say "preview:"
printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Opus 5"},"effort":{"level":"high"},"cost":{"total_cost_usd":1.23},"context_window":{"used_percentage":37},"rate_limits":{"five_hour":{"used_percentage":62},"seven_day":{"used_percentage":89}}}' "$PWD" \
  | COLUMNS=${COLUMNS:-159} bash "$dest"
say ""
say ""
say "done - restart Claude Code to pick it up"
