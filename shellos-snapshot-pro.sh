#!/usr/bin/env bash
# shellos-snapshot-pro
# Secure Snapper + Btrfs rollback helper for Arch (works on other distros with snapper + btrfs)
# Features: dry-run, boot-in-snapshot detection, safety snapshot, auto set-default subvolume, GRUB & initramfs update, logging
#
# Usage:
#   shellos-snapshot-pro create      # create snapshots for all snapper configs
#   shellos-snapshot-pro restore     # interactive restore (or pass -n <num> for snapshot id)
# Options:
#   -d, --dry-run     Show actions but don't execute
#   -y, --yes         Assume yes for confirmations
#   -n <id>           Use snapshot number (non-interactive)
#   --no-initramfs    Skip initramfs regen (if you prefer)
#   --no-grub         Skip grub update
#   --force-offline   Allow restore while booted into snapshot (advanced)
set -euo pipefail

LOG="/var/log/shellos-snapshot-pro.log"
DRY_RUN=0
ASSUME_YES=0
SNAP_NUM=""
SKIP_INITRAMFS=0
SKIP_GRUB=0
FORCE_OFFLINE=0

timestamp() { date -u +"%Y-%m-%d %H:%M:%SZ"; }
log() {
  printf '%s %s\n' "$(timestamp)" "$*" | tee -a "$LOG"
}

usage() {
  cat <<EOF
Usage: $0 [options] <create|restore>
Options:
  -d, --dry-run         Dry run (print actions, don't execute)
  -y, --yes             Assume yes to prompts
  -n <id>               Snapshot number to restore (non-interactive)
  --no-initramfs        Skip regenerating initramfs
  --no-grub             Skip updating grub
  --force-offline       Allow restore while booted into a snapshot (dangerous)
EOF
  exit 1
}

# simple CLI parse
if [[ $# -lt 1 ]]; then usage; fi

CMD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    create|restore) CMD="$1"; shift ;;
    -d|--dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -n) SNAP_NUM="$2"; shift 2 ;;
    --no-initramfs) SKIP_INITRAMFS=1; shift ;;
    --no-grub) SKIP_GRUB=1; shift ;;
    --force-offline) FORCE_OFFLINE=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    log "[DRY RUN] $*"
  else
    log "[EXEC] $*"
    eval "$@"
  fi
}

require_cmds() {
  for c in "$@"; do
    if ! command -v "$c" &>/dev/null; then
      log "Required command missing: $c"
      echo "Error: required command not found: $c" >&2
      exit 127
    fi
  done
}

# Detect if we are booted into a snapshot (common pattern: source contains ".snapshots")
booted_in_snapshot() {
  # findmnt -no SOURCE / typically returns something like /dev/mapper/.. or /dev/sd.. or <device>/subvolid=...
  local src
  src="$(findmnt -no SOURCE / || true)"
  if [[ "$src" == *".snapshots"* ]] || [[ "$(realpath /)" == *".snapshots"* ]]; then
    return 0
  fi
  # Another approach: check if /.snapshots exists in root subvolume path (mounted snapshot)
  return 1
}

# get snapper configs
get_snapper_configs() {
  snapper --csvout list-configs 2>/dev/null | awk -F, 'NR>1 {print $1}'
}

# print snapshots for config
list_snapshots() {
  local cfg="$1"
  snapper -c "$cfg" list
}

# ask confirm
confirm() {
  local prompt="$1"
  if [[ $ASSUME_YES -eq 1 ]]; then
    log "Auto-confirm enabled: proceeding"
    return 0
  fi
  read -r -p "$prompt [y/N]: " ans
  case "$ans" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

# Find btrfs subvolume ID for a snapper snapshot number.
# This handles layouts where snapshots are under @/.snapshots or /.snapshots or @home/.snapshots.
find_snapshot_subvol_id() {
  local cfg="$1"
  local snapnum="$2"
  # snapper info prints "Path : /.snapshots/NN/snapshot" (or @/.snapshots)
  local path
  path="$(snapper -c "$cfg" info "$snapnum" 2>/dev/null | awk -F': ' '/Path/ {print $2}' | tr -d '[:space:]')"
  if [[ -z "$path" ]]; then
    echo ""
    return 1
  fi
  # btrfs subvolume list root and match path suffix
  # Sometimes the path is relative to subvol like @/.snapshots/NN/snapshot. We'll search for any subvolume whose path ends with the path's tail
  local tail
  tail="${path##*/@}"   # attempt to strip leading parts
  # list and find exact match using grep on the path column
  local match
  match="$(sudo btrfs subvolume list -o / | awk '{for(i=9;i<=NF;i++) printf $i" "; print ""}' | nl -w1 -s'|' | sed 's/^[ \t]*//' )" || true
  # Simpler: use btrfs subvolume list / and grep for the path
  local full_entry
  full_entry="$(sudo btrfs subvolume list / | awk -v p="$path" '$0 ~ p {print $2" "$0; exit}')"
  if [[ -n "$full_entry" ]]; then
    # full_entry format: "ID ... path <path>"
    # Extract ID (first numeric token after "ID")
    local id
    id="$(echo "$full_entry" | awk '{for(i=1;i<=NF;i++) if($i=="ID") {print $(i+1); exit}}')"
    # fallback: sometimes output begins with "ID 298 gen ..."
    if [[ -z "$id" ]]; then
      id="$(echo "$full_entry" | awk '{print $2}')"
    fi
    echo "$id"
    return 0
  fi

  # Fallback: attempt to grep partial snapshot pattern (e.g., ".snapshots/<num>/snapshot")
  local tailpattern
  # extract last two components like ".snapshots/NN/snapshot"
  tailpattern="$(echo "$path" | awk -F'/' '{n=NF; if(n>=3) print $(n-2)"/"$(n-1)"/"$(n); else print $0}')"
  local entry
  entry="$(sudo btrfs subvolume list / | grep -F "$tailpattern" | head -n1 || true)"
  if [[ -n "$entry" ]]; then
    # parse ID
    local found
    found="$(echo "$entry" | awk '{print $2}')"
    echo "$found"
    return 0
  fi

  # as final fallback, iterate all and try to match path suffix
  while read -r line; do
    # capture ID and path portion after "path"
    local vid vpath
    vid="$(echo "$line" | awk '{print $2}')"
    vpath="$(echo "$line" | sed -n 's/.*path //p')"
    if [[ "$vpath" == *"$path" ]] || [[ "$vpath" == *"$tailpattern" ]]; then
      echo "$vid"
      return 0
    fi
  done < <(sudo btrfs subvolume list /)
  echo ""
  return 1
}

# create a safety snapshot (readonly) of current default root before changing
create_safety_snapshot() {
  local cfg="$1"
  log "Creating safety snapshot (before rollback) using snapper config '$cfg'..."
  if [[ $DRY_RUN -eq 1 ]]; then
    log "[DRY] snapper -c $cfg create -c pre -d \"Pre-rollback backup $(date +'%Y-%m-%d %H:%M:%S')\""
  else
    sudo snapper -c "$cfg" create -c pre -d "Pre-rollback backup $(date +'%Y-%m-%d %H:%M:%S')"
  fi
}

########################
### Main: create flow ###
########################
if [[ "$CMD" == "create" ]]; then
  require_cmds snapper btrfs
  log "Snapshot create mode started"
  configs=( $(get_snapper_configs) )
  if [[ ${#configs[@]} -eq 0 ]]; then
    echo "No snapper configs found." >&2
    exit 1
  fi
  for cfg in "${configs[@]}"; do
    log "Creating snapshot for config: $cfg"
    if [[ $DRY_RUN -eq 1 ]]; then
      log "[DRY] sudo snapper -c $cfg create -c number -d \"$DESC\""
    else
      sudo snapper -c "$cfg" create -c number -d "Snapshot created by shellos-snapshot-pro $(date +'%Y-%m-%d %H:%M:%S')"
    fi
  done
  if systemctl is-active --quiet grub-btrfsd.service && [[ $DRY_RUN -eq 0 ]]; then
    log "Restarting grub-btrfsd to refresh GRUB entries"
    sudo systemctl restart grub-btrfsd.service || true
  fi
  log "Snapshot create complete"
  exit 0
fi

#########################
### Main: restore flow ###
#########################
if [[ "$CMD" == "restore" ]]; then
  require_cmds snapper btrfs findmnt
  log "Restore mode started"

  if booted_in_snapshot && [[ $FORCE_OFFLINE -ne 1 ]]; then
    echo "You appear to be booted from a snapshot. For safety, perform restore from the real system root or use --force-offline."
    log "Abort: booted inside snapshot and --force-offline not set"
    exit 1
  fi

  configs=( $(get_snapper_configs) )
  if [[ ${#configs[@]} -eq 0 ]]; then
    echo "No snapper configs found." >&2
    exit 1
  fi

  # pick config
  if [[ ${#configs[@]} -gt 1 ]]; then
    echo "Available configs: ${configs[*]}"
    if [[ -n "$SNAP_NUM" ]]; then
      # non-interactive requires a config in context; choose 'root' if exists else first
      if printf '%s\n' "${configs[@]}" | grep -qx "root"; then
        CONFIG="root"
      else
        CONFIG="${configs[0]}"
      fi
    else
      read -r -p "Select config to restore (default: root if present): " CONFIG
      CONFIG="${CONFIG:-$(printf '%s\n' "${configs[@]}" | awk 'NR==1{print $1}')}"
    fi
  else
    CONFIG="${configs[0]}"
  fi

  log "Selected snapper config: $CONFIG"

  # list snapshots for chosen config
  echo "Snapshots for config $CONFIG:"
  snapper -c "$CONFIG" list
  if [[ -z "$SNAP_NUM" ]]; then
    read -r -p "Enter snapshot number to restore: " SNAP_NUM
  fi

  if [[ -z "$SNAP_NUM" ]]; then
    echo "No snapshot number provided." >&2
    exit 1
  fi

  # sanity confirm
  echo "You are about to rollback config '$CONFIG' to snapshot #$SNAP_NUM"
  confirm "Proceed with rollback?" || { log "User cancelled"; exit 0; }

  # create safety snapshot (pre-rollback)
  create_safety_snapshot "$CONFIG"

  # perform snapper rollback
  log "Running snapper rollback - this will create a rollback snapshot pair"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "[DRY] sudo snapper -c $CONFIG rollback $SNAP_NUM"
  else
    sudo snapper -c "$CONFIG" rollback "$SNAP_NUM"
  fi

  # After snapper rollback, find the subvolume id that corresponds to the snapshot we just rolled back to.
  log "Attempting to find btrfs subvolume ID for snapshot $SNAP_NUM (config $CONFIG)"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "[DRY] find_snapshot_subvol_id $CONFIG $SNAP_NUM"
    echo "Dry-run complete — no default changed."
    exit 0
  fi

  NEW_ID="$(find_snapshot_subvol_id "$CONFIG" "$SNAP_NUM" || true)"
  if [[ -z "$NEW_ID" ]]; then
    log "Failed to find matching subvolume ID for snapshot $SNAP_NUM. Listing btrfs subvolumes for manual inspection:"
    sudo btrfs subvolume list /
    echo "Unable to auto-detect the snapshot subvolume. Inspect above output and set default manually with:"
    echo "  sudo btrfs subvolume set-default <ID> /"
    exit 1
  fi

  log "Found snapshot subvolume ID: $NEW_ID"

  # Backup the current default id
  OLD_DEFAULT="$(sudo btrfs subvolume get-default / | awk '{print $NF}' || true)"
  if [[ -n "$OLD_DEFAULT" ]]; then
    log "Current default subvolume ID: $OLD_DEFAULT"
  else
    log "No default subvolume ID appears to be set"
  fi

  # Set the snapshot subvolume as default
  log "Setting subvolume $NEW_ID as default for root (/)"
  sudo btrfs subvolume set-default "$NEW_ID" /

  # Update GRUB entries if requested
  if [[ $SKIP_GRUB -eq 0 ]]; then
    if systemctl is-active --quiet grub-btrfsd.service; then
      log "Restarting grub-btrfsd to refresh GRUB"
      sudo systemctl restart grub-btrfsd.service || true
    fi
    if command -v grub-mkconfig &>/dev/null; then
      log "Updating GRUB config"
      sudo grub-mkconfig -o /boot/grub/grub.cfg || log "grub-mkconfig failed (non-fatal)"
    else
      log "grub-mkconfig not found; skipping"
    fi
  else
    log "Skipping GRUB update (user requested)"
  fi

  # Regenerate initramfs (Arch: mkinitcpio). Optional.
  if [[ $SKIP_INITRAMFS -eq 0 ]]; then
    if command -v mkinitcpio &>/dev/null; then
      log "Regenerating initramfs images (mkinitcpio -P)"
      sudo mkinitcpio -P || log "mkinitcpio returned non-zero (non-fatal)"
    else
      log "mkinitcpio not found, skipping initramfs regeneration"
    fi
  else
    log "Skipping initramfs regeneration (user requested)"
  fi

  log "Rollback completed. Recommend rebooting the machine now."
  echo "Rollback finished. Reboot now to activate the rolled-back snapshot: sudo reboot"
  exit 0
fi

usage
