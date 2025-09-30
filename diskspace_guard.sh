#!/usr/bin/env bash
# diskspace_guard.sh — auto-clean when disk space is low
# Default thresholds (change via CLI flags below):
THRESHOLD_GB="${THRESHOLD_GB:-60}"        # trigger if free < this many GB
THRESHOLD_FREE_PCT="${THRESHOLD_FREE_PCT:-15}"  # or if free% < this

LOGFILE="${LOGFILE:-$HOME/Library/Logs/diskspace-guard.log}"
CLEANMYMAC_APP="${CLEANMYMAC_APP:-CleanMyMac X}"  # change if localized name
RUN_CLEANMYMAC="${RUN_CLEANMYMAC:-1}"      # set 0 to disable
RUN_TM_SNAPSHOT_THIN="${RUN_TM_SNAPSHOT_THIN:-1}" # set 0 to disable
RUN_CLEAR_CACHES="${RUN_CLEAR_CACHES:-1}"  # set 0 to disable
RUN_EMPTY_TRASH="${RUN_EMPTY_TRASH:-1}"    # set 0 to disable
RUN_PRUNE_XCODE="${RUN_PRUNE_XCODE:-1}"    # set 0 to disable

# --- CLI flags ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold-gb) THRESHOLD_GB="$2"; shift 2 ;;
    --percent-free) THRESHOLD_FREE_PCT="$2"; shift 2 ;;
    --no-cleanmymac) RUN_CLEANMYMAC=0; shift ;;
    --no-tm) RUN_TM_SNAPSHOT_THIN=0; shift ;;
    --no-caches) RUN_CLEAR_CACHES=0; shift ;;
    --no-trash) RUN_EMPTY_TRASH=0; shift ;;
    --no-xcode) RUN_PRUNE_XCODE=0; shift ;;
    --logfile) LOGFILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

log() { printf "%s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOGFILE"; }

bytes_to_gb() {
  # prints integer GB rounded down
  awk -v b="$1" 'BEGIN { printf("%d", b/1024/1024/1024) }'
}

get_disk_stats() {
  # POSIX-friendly df output for root filesystem
  # Fields: Filesystem 1K-blocks Used Available Use% Mounted on
  df -kP / | tail -1
}

free_bytes() {
  get_disk_stats | awk '{print $4*1024}'
}

free_pct() {
  # 100 - Use%
  local usedpct
  usedpct=$(get_disk_stats | awk '{print $5}' | tr -d '%')
  echo $((100 - usedpct))
}

human_free() {
  # pretty print free (GB)
  local fb; fb=$(free_bytes)
  bytes_to_gb "$fb"
}

before_free="$(free_bytes)"
before_free_gb="$(human_free)"
before_pct="$(free_pct)"

log "Check: free=${before_free_gb}GB, free%=${before_pct}% (thresholds: <${THRESHOLD_GB}GB or <${THRESHOLD_FREE_PCT}%)"

trigger=0
if [[ "$before_free_gb" -lt "$THRESHOLD_GB" ]]; then trigger=1; fi
if [[ "$before_pct" -lt "$THRESHOLD_FREE_PCT" ]]; then trigger=1; fi

if [[ "$trigger" -eq 0 ]]; then
  log "OK: thresholds not crossed; no action."
  exit 0
fi

log "ALERT: thresholds crossed — starting cleanup."

# --- Step 1: Empty user Trash (safe) ---
if [[ "$RUN_EMPTY_TRASH" -eq 1 ]]; then
  if [[ -d "$HOME/.Trash" ]]; then
    TRASH_BEFORE=$(du -sk "$HOME/.Trash" 2>/dev/null | awk '{print $1}')
    rm -rf "$HOME/.Trash/"* "$HOME/.Trash/".* 2>/dev/null
    TRASH_AFTER=$(du -sk "$HOME/.Trash" 2>/dev/null | awk '{print $1}')
    log "Trash emptied (was ${TRASH_BEFORE:-0}K, now ${TRASH_AFTER:-0}K)."
  else
    log "Trash folder not found; skipping."
  fi
fi

# --- Step 2: Clear user caches (generally safe; apps may rebuild caches) ---
if [[ "$RUN_CLEAR_CACHES" -eq 1 ]]; then
  if [[ -d "$HOME/Library/Caches" ]]; then
    CACHES_BEFORE=$(du -sk "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
    # Delete only contents, keep the directory
    find "$HOME/Library/Caches" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
    CACHES_AFTER=$(du -sk "$HOME/Library/Caches" 2>/dev/null | awk '{print $1}')
    log "User caches cleared (was ${CACHES_BEFORE:-0}K, now ${CACHES_AFTER:-0}K)."
  else
    log "User caches folder not found; skipping."
  fi
fi

# --- Step 3: Prune Xcode DerivedData (if present) ---
if [[ "$RUN_PRUNE_XCODE" -eq 1 ]]; then
  if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
    XCODE_BEFORE=$(du -sk "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | awk '{print $1}')
    rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/* 2>/dev/null
    XCODE_AFTER=$(du -sk "$HOME/Library/Developer/Xcode/DerivedData" 2>/dev/null | awk '{print $1}')
    log "Xcode DerivedData cleared (was ${XCODE_BEFORE:-0}K, now ${XCODE_AFTER:-0}K)."
  else
    log "No Xcode DerivedData found; skipping."
  fi
fi

# --- Step 4: Thin Time Machine local snapshots (safe on laptops) ---
if [[ "$RUN_TM_SNAPSHOT_THIN" -eq 1 ]]; then
  if command -v tmutil >/dev/null 2>&1; then
    # Try targeted thin (~10GB) up to 4 passes; tmutil decides what to free
    log "Thinning Time Machine local snapshots (~10GB target, up to 4 passes)."
    tmutil thinlocalsnapshots / 10000000000 4 2>&1 | tee -a "$LOGFILE"
  else
    log "tmutil not available; skipping snapshot thinning."
  fi
fi

# --- Step 5: Trigger CleanMyMac X Smart Cleanup (best-effort) ---
if [[ "$RUN_CLEANMYMAC" -eq 1 ]]; then
  if osascript -e 'id of application "'"$CLEANMYMAC_APP"'"' >/dev/null 2>&1; then
    # Try launching with args (if supported); otherwise just open the app.
    if open -a "$CLEANMYMAC_APP" --args --scan --clean >/dev/null 2>&1; then
      log "CleanMyMac X launched with --scan --clean (if supported)."
    else
      open -a "$CLEANMYMAC_APP"
      log "CleanMyMac X launched (no CLI flags supported on this build)."
    fi
  else
    log "CleanMyMac X not found; skipping."
  fi
fi

# --- Step 6: Cloud eviction (File Provider clouds) ---
# Evict the largest materialised files from iCloud/Dropbox/GDrive/OneDrive if still low
if [[ "$after_free_gb" -lt "$THRESHOLD_GB" ]]; then
  if command -v "$HOME/bin/cloudspace_evict.sh" >/dev/null 2>&1; then
    log "Space still low; attempting File Provider eviction of large files."
    "$HOME/bin/cloudspace_evict.sh" --apply | tee -a "$LOGFILE"
    sleep 5
    # Recalculate after eviction
    after_free="$(free_bytes)"
    after_free_gb="$(human_free)"
    delta_gb=$(( after_free_gb - before_free_gb ))
  else
    log "cloudspace_evict.sh not found; skipping eviction."
  fi
fi

# --- Report freed space ---
sleep 5  # give the system a moment to reclaim space
after_free="$(free_bytes)"
after_free_gb="$(human_free)"
delta_gb=$(( after_free_gb - before_free_gb ))
log "Cleanup finished. Free before: ${before_free_gb}GB; after: ${after_free_gb}GB; delta: ${delta_gb}GB."

# Optional: macOS notification
osascript -e 'display notification "Freed ~'"$delta_gb"' GB. Free space: '"$after_free_gb"' GB" with title "Diskspace Guard"'
exit 0
