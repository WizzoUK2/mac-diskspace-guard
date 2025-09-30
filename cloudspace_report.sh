#!/usr/bin/env bash
set -euo pipefail

LOGFILE="${LOGFILE:-$HOME/Library/Logs/cloudspace-report.log}"
TS="$(date '+%Y-%m-%d %H:%M:%S')"
log(){ printf "%s %s\n" "$TS" "$*" | tee -a "$LOGFILE"; }

# Common cloud locations on modern macOS (File Provider)
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
CLOUDSTORAGE="$HOME/Library/CloudStorage"   # Dropbox, Google Drive, OneDrive (new)
DROPBOX_GUESS="$HOME/Library/CloudStorage/Dropbox"
GDRIVE_GUESS=$(ls "$HOME/Library/CloudStorage" 2>/dev/null | grep -i 'GoogleDrive' | sed "s|^|$HOME/Library/CloudStorage/|")
ONEDRIVE_GUESS=$(ls "$HOME/Library/CloudStorage" 2>/dev/null | grep -i 'OneDrive' | sed "s|^|$HOME/Library/CloudStorage/|")

HDR="Provider,Path,On-Disk (GB),Items"
printf "%s\n" "$HDR" | tee -a "$LOGFILE"

report_dir(){
  local name="$1"; local path="$2"
  if [[ -d "$path" ]]; then
    # On-disk footprint (materialized bytes). Fast estimate: du -sk
    local kb items
    kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
    items=$(find "$path" -xdev -type f -print 2>/dev/null | wc -l | tr -d ' ')
    local gb=$(( kb / 1024 / 1024 ))
    printf "%s,%s,%s,%s\n" "$name" "$path" "$gb" "$items" | tee -a "$LOGFILE"
  fi
}

report_dir "iCloud" "$ICLOUD"
report_dir "Dropbox" "$DROPBOX_GUESS"
for p in $GDRIVE_GUESS; do report_dir "GoogleDrive" "$p"; done
for p in $ONEDRIVE_GUESS; do report_dir "OneDrive" "$p"; done

# Also enumerate all providers under CloudStorage (covers any additional accounts)
if [[ -d "$CLOUDSTORAGE" ]]; then
  while IFS= read -r -d '' d; do
    base=$(basename "$d")
    [[ "$d" == "$DROPBOX_GUESS" ]] && continue
    [[ "$d" == "$ICLOUD" ]] && continue
    printf "FileProvider,%s," "$d" | tee -a "$LOGFILE" >/dev/null
    kb=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
    gb=$(( kb / 1024 / 1024 ))
    items=$(find "$d" -xdev -type f -print 2>/dev/null | wc -l | tr -d ' ')
    printf "%s,%s\n" "$gb" "$items" | tee -a "$LOGFILE"
  done < <(find "$CLOUDSTORAGE" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
fi

# Mountain Duck mounts typically appear in /Volumes/<Name>
if mount | grep -qi "mountainduck"; then
  log "Mountain Duck mounts detected:"
fi

while IFS= read -r -d '' vol; do
  # Try df on the mount
  df -H "$vol" 2>/dev/null | awk 'NR==2{printf "  %s — Used:%s Free:%s Use%%:%s\n",$6,$3,$4,$5}' | tee -a "$LOGFILE"
done < <(find /Volumes -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

exit 0
