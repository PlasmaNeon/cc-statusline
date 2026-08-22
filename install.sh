#!/usr/bin/env bash
# Installs the Claude Code status line on this machine.
#
#   ./install.sh            install to ~/.claude and wire up settings.json
#   ./install.sh --dry-run  show what would happen, change nothing
#
# Also works piped straight from the repo, with no checkout:
#
#   curl -fsSL https://raw.githubusercontent.com/PlasmaNeon/cc-statusline/main/install.sh | bash
#
# In that case there is no sibling statusline-command.sh to copy, so it is
# fetched from the same branch - see the fallback below.
#
# Existing settings.json is preserved: only the "statusLine" key is replaced,
# and a timestamped backup is written alongside it.
set -euo pipefail

# Piped from curl, "$0" is just "bash" and this lands on $PWD - which is why
# the missing-source case below is a fetch rather than an error.
src_dir=$(cd "$(dirname "$0")" && pwd)
src="$src_dir/statusline-command.sh"
raw="https://raw.githubusercontent.com/PlasmaNeon/cc-statusline/main"
dest_dir="$HOME/.claude"
dest="$dest_dir/statusline-command.sh"
settings="$dest_dir/settings.json"
dry_run=false
[ "${1:-}" = "--dry-run" ] && dry_run=true

say() { printf '%s\n' "$*"; }
run() { if $dry_run; then say "  would: $*"; else eval "$@"; fi; }

command -v jq >/dev/null 2>&1 || {
  say "error: jq is required (brew install jq / apt install jq)"; exit 1; }

# No checkout to copy from - fetch the status line itself. It goes to a temp
# file first, so a truncated transfer cannot leave a half-written script
# installed, and the temp file is removed on the way out either way. A dry run
# fetches too: it costs nothing on disk and proves the URL actually resolves.
if [ ! -f "$src" ]; then
  command -v curl >/dev/null 2>&1 || {
    say "error: no statusline-command.sh next to install.sh, and no curl to fetch one"
    exit 1; }
  tmp=$(mktemp "${TMPDIR:-/tmp}/statusline-command.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  say "fetching statusline-command.sh from $raw"
  curl -fsSL "$raw/statusline-command.sh" -o "$tmp" || {
    say "error: could not download $raw/statusline-command.sh"; exit 1; }
  head -n 1 "$tmp" | grep -q '^#!' || {
    say "error: $raw/statusline-command.sh did not come back as a script"; exit 1; }
  src=$tmp
fi

say "installing to $dest"
run "mkdir -p '$dest_dir'"
# A symlinked install - $dest pointing back at a checkout - is a normal way to
# run this from a working copy, and copying a file onto itself is an error, not
# a no-op ("cp: ... are identical", exit 1), which under set -e would abort the
# install. Leave the link alone; it is already serving the file being installed.
if [ -e "$dest" ] && [ "$src" -ef "$dest" ]; then
  say "  $dest already resolves to $src - leaving it as is"
else
  run "cp '$src' '$dest'"
fi

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
printf '{"workspace":{"current_dir":"%s"},"cwd":"%s","model":{"display_name":"Opus 5"},"effort":{"level":"high"},"cost":{"total_cost_usd":1.23},"context_window":{"used_percentage":37},"rate_limits":{"five_hour":{"used_percentage":62},"seven_day":{"used_percentage":89}}}' "$PWD" "$PWD" \
  | bash "$dest"
say ""
say ""
say "done - restart Claude Code to pick it up"
