#!/usr/bin/env bash
set -euo pipefail

# Config
LOGFILE="${LOGFILE:-$HOME/Library/Logs/cloudspace-evict.log}"
# Directories to scan for eviction candidates (edit as needed)
SCAN_DIRS=(
  "$HOME/Library/Mobile Documents/com~apple~CloudDocs"
  "$HOME/Library/CloudStorage"
)
# Skip these (patterns). Add project dirs you never want evicted.
SKIP_PATTERNS=(
  "/Library/CloudStorage/.*Caches"
  "/Library/Mobile Documents/com~apple~CloudDocs/Important"
)

# Candidate size threshold (bytes) — consider eviction if >= 200 MB
MIN_SIZE_BYTES=$((200 * 1024 * 1024))
# Max files to evict per run
MAX_EVICT=50

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

log(){ printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOGFILE"; }

require() {
  command -v "$1" >/dev/null 2>&1 || { log "Missing dependency: $1"; exit 1; }
}

require fileproviderctl
require find
require stat

log "Starting eviction scan (min-size: $((MIN_SIZE_BYTES/1024/1024))MB, max: $MAX_EVICT, apply:$APPLY)"

# Build find predicates
skip_expr=()
for pat in "${SKIP_PATTERNS[@]}"; do
  skip_expr+=( -not -path "$HOME$pat" )
done

# Gather candidates
mapfile -d '' CANDIDATES < <(
  for root in "${SCAN_DIRS[@]}"; do
    [[ -d "$root" ]] || continue
    find "$root" -xdev -type f "${skip_expr[@]}" -size +"$((MIN_SIZE_BYTES/1024))"k -print0 2>/dev/null
  done
)

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  log "No candidates found."
  exit 0
fi

# Compute sizes and sort desc
TMPLIST="$(mktemp)"
trap 'rm -f "$TMPLIST"' EXIT

i=0
while [[ $i -lt ${#CANDIDATES[@]} ]]; do
  f="${CANDIDATES[$i]}"
  # size in bytes (GNU/BSD stat compatibility)
  if stat -f '%z' "$f" >/dev/null 2>&1; then
    sz=$(stat -f '%z' "$f")
  else
    sz=$(stat -c '%s' "$f")
  fi
  printf "%s\t%s\n" "$sz" "$f" >> "$TMPLIST"
  i=$((i+1))
done

# Sort by size desc and take top N
mapfile -t TOP < <(sort -nr "$TMPLIST" | head -n "$MAX_EVICT")

TOTAL=0
COUNT=0
for line in "${TOP[@]}"; do
  sz="${line%%	*}"
  f="${line#*	}"

  # Heuristic: only attempt to evict if file seems materialized (has data fork)
  # If it's already online-only, evict will just be a no-op.
  mb=$(( sz/1024/1024 ))
  log "Candidate: ${mb}MB — $f"
  if [[ "$APPLY" -eq 1 ]]; then
    if fileproviderctl evict "$f" >/dev/null 2>&1; then
      log "  Evicted."
      TOTAL=$((TOTAL + sz))
      COUNT=$((COUNT + 1))
    else
      log "  Evict failed (maybe not a FileProvider file)."
    fi
  fi
done

if [[ "$APPLY" -eq 1 ]]; then
  log "Evicted $COUNT files, ~$((TOTAL/1024/1024))MB freed (will finalize as macOS reclaims)."
else
  log "Dry-run complete. Use --apply to perform eviction."
fi

exit 0
