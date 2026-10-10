#!/usr/bin/env bash
# Repo Rescue — safely work around unreachable pacman repositories for one transaction.
# This script temporarily comments out repository sections whose database download fails,
# performs a full sync/upgrade + requested install, then restores pacman.conf automatically.
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.0.0"
CONFIG="/etc/pacman.conf"
PACMAN="${PACMAN:-pacman}"
DRY_RUN=0
NO_UPGRADE=0
KEEP_DISABLED=0
PACKAGES=()

usage() {
  cat <<'EOF'
Repo Rescue — temporary workaround for unreachable pacman repository databases

Usage:
  repo-rescue.sh [options] package [package ...]

Options:
  -n, --dry-run       Show planned actions; do not change configuration or install.
      --no-upgrade    Install requested packages without a full system upgrade.
                      WARNING: Arch partial upgrades are unsupported; use only knowingly.
      --keep-disabled Leave failing repositories disabled after the operation.
  -h, --help          Show this help.

Examples:
  ./scripts/repo-rescue.sh xterm
  ./scripts/repo-rescue.sh --dry-run xterm
  ./scripts/repo-rescue.sh git base-devel

What it does:
  1. Makes a timestamped backup of /etc/pacman.conf.
  2. Tries to synchronize repository databases.
  3. If a repository database fails to download, temporarily comments out only
     the matching repository section(s).
  4. Runs pacman -Syu --needed <packages> (or -S --needed with --no-upgrade).
  5. Restores the original config automatically, including after most failures.

Limitations:
  - Packages available only from a disabled repository cannot be installed.
  - It cannot fix DNS, general connectivity, keyring, signature, or mirror problems.
  - Review the proposed repositories before approving changes.
  - Do not use this to permanently hide a broken repository; repair its URL/connectivity.
EOF
}

log() { printf '[repo-rescue] %s\n' "$*"; }
die() { printf '[repo-rescue] ERROR: %s\n' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    --no-upgrade) NO_UPGRADE=1; shift ;;
    --keep-disabled) KEEP_DISABLED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; PACKAGES+=("$@"); break ;;
    -*) die "Unknown option: $1 (use --help)" ;;
    *) PACKAGES+=("$1"); shift ;;
  esac
done

((${#PACKAGES[@]})) || { usage; die "Provide at least one package name."; }
[[ $EUID -eq 0 ]] || die "Run with sudo: sudo $0 package [package ...]"
[[ -f "$CONFIG" ]] || die "Cannot find $CONFIG"
command -v "$PACMAN" >/dev/null 2>&1 || die "pacman was not found."

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/etc/pacman.conf.repo-rescue.${STAMP}.bak"
WORK="$(mktemp -d)"
ORIGINAL="$WORK/pacman.conf.original"
cp -a "$CONFIG" "$BACKUP"
cp -a "$CONFIG" "$ORIGINAL"
CHANGED=0
RESTORE_NEEDED=0

restore_config() {
  local rc=$?
  if (( RESTORE_NEEDED )) && (( ! KEEP_DISABLED )); then
    if cp -a "$ORIGINAL" "$CONFIG"; then
      log "Restored original pacman.conf."
    else
      printf '[repo-rescue] CRITICAL: automatic restore failed. Backup: %s\n' "$BACKUP" >&2
      printf '[repo-rescue] Restore manually with: sudo cp %q %q\n' "$BACKUP" "$CONFIG" >&2
      rc=1
    fi
  elif (( RESTORE_NEEDED && KEEP_DISABLED )); then
    log "Leaving failing repositories disabled as requested. Backup: $BACKUP"
  fi
  rm -rf "$WORK"
  exit "$rc"
}
trap restore_config EXIT INT TERM HUP

# Extract failing repository database names from pacman's output, e.g. ryoku.db.
sync_log="$WORK/sync.log"
log "Checking repository database synchronization..."
set +e
"$PACMAN" -Syy 2>&1 | tee "$sync_log"
sync_rc=${PIPESTATUS[0]}
set -e

if (( sync_rc == 0 )); then
  log "All repository databases synchronized."
else
  mapfile -t FAILED_DBS < <(
    sed -nE \
      -e "s/.*failed to retrieve file ['\"]?([^'\"]+\\.db)['\"]?.*/\1/p" \
      -e "s/.*failed retrieving file ['\"]?([^'\"]+\\.db)['\"]?.*/\1/p" \
      -e "s/.*database file for ['\"]?([^'\"]+)['\"]? does not exist.*/\1.db/p" \
      "$sync_log" | sort -u
  )
  ((${#FAILED_DBS[@]})) || die "Sync failed, but no failed *.db name could be identified. No config changes made."

  # Map database filename (repo-name.db) to a repository section in pacman.conf.
  mapfile -t FAILED_REPOS < <(
    for db in "${FAILED_DBS[@]}"; do
      printf '%s\n' "${db%.db}"
    done | sort -u
  )

  log "Repository database(s) that failed: ${FAILED_DBS[*]}"
  log "Candidate repository section(s): ${FAILED_REPOS[*]}"
  if (( DRY_RUN )); then
    log "Dry run: no configuration changes or installation performed."
    exit 0
  fi

  printf '\nThe script can temporarily disable only these repository sections for this install:\n'
  printf '  - %s\n' "${FAILED_REPOS[@]}"
  printf 'A backup will be kept at: %s\n' "$BACKUP"
  read -r -p "Continue? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || die "Cancelled by user."

  # Use awk to comment each failed repository section and its settings until the next section.
  # Preserve every line's content by adding # only to the selected section.
  awk -v repos="$(IFS=,; echo "${FAILED_REPOS[*]}")" '
    BEGIN {
      n = split(repos, r, ",")
      for (i = 1; i <= n; i++) target[r[i]] = 1
      active = 0
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*([#].*)?$/ {
      name = $0
      sub(/^[[:space:]]*\[/, "", name)
      sub(/\].*$/, "", name)
      active = (name in target)
      if (active) { print "#" $0; next }
    }
    active { print "#" $0; next }
    { print }
  ' "$CONFIG" > "$WORK/pacman.conf.modified"

  # Confirm that each target section was found before replacing the config.
  for repo in "${FAILED_REPOS[@]}"; do
    if ! grep -Eq "^[[:space:]]*\\[$repo\\][[:space:]]*$" "$CONFIG"; then
      die "Repository section [$repo] was not found exactly; refusing to modify config."
    fi
  done

  cp -a "$WORK/pacman.conf.modified" "$CONFIG"
  CHANGED=1
  RESTORE_NEEDED=1
  log "Temporarily disabled: ${FAILED_REPOS[*]}"
  log "Retrying database synchronization..."
  "$PACMAN" -Syy
fi

if (( DRY_RUN )); then
  log "Dry run complete; no package installation performed."
  exit 0
fi

if (( NO_UPGRADE )); then
  log "Installing requested package(s) without a full upgrade, as requested."
  log "WARNING: partial upgrades are unsupported on Arch Linux."
  "$PACMAN" -S --needed -- "${PACKAGES[@]}"
else
  log "Running a full system upgrade and installing: ${PACKAGES[*]}"
  "$PACMAN" -Syu --needed -- "${PACKAGES[@]}"
fi

log "Package transaction completed."
log "Original config will be restored automatically unless --keep-disabled was specified."
