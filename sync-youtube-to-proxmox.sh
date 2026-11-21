#!/bin/bash
# ==============================================================================
# Synchronizacja kanałów YouTube z Unraid na Proxmox (do biblioteki Jellyfin)
# ==============================================================================
set -euo pipefail

LOCK_FILE="/tmp/sync-youtube-to-proxmox.lock"
LOG_FILE="/mnt/user/videos/youtube/sync-youtube-to-proxmox.log"

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Synchronizacja jest już w toku. Pomijam uruchomienie." | tee -a "$LOG_FILE"
    exit 0
fi

SRC_BASE="/mnt/user/videos/youtube"
REMOTE_HOST="root@proxmox"
REMOTE_DIR="/mnt/nvme-data/jellyfin-videos/youtube/"

# Jellyfin w nieuprzywilejowanym kontenerze LXC na Proxmox (UID 107 -> 100107, GID 110 -> 100110)
CHOWN_OPTS="--chown=100107:100110 --chmod=D775,F664"

# Ustaw na true, jeśli chcesz usuwać z Proxmox pliki, których nie ma już na Unraid
DELETE_EXTRANEOUS=false

# Automatyczne wykrywanie wszystkich podkatalogów w SRC_BASE
DIRECTORIES=()
shopt -s nullglob
for dir_path in "${SRC_BASE}"/*/; do
    dir_name="$(basename "$dir_path")"
    [[ "$dir_name" == "@eaDir" ]] && continue
    DIRECTORIES+=("$dir_name")
done
shopt -u nullglob

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "================================================================="
log "Rozpoczynam synchronizację YouTube: Unraid -> Proxmox"
log "Docelowy host: ${REMOTE_HOST}:${REMOTE_DIR}"

# 1. Sprawdzenie katalogów źródłowych
SOURCES=()
for dir in "${DIRECTORIES[@]}"; do
    target_path="${SRC_BASE}/${dir}"
    if [ -d "$target_path" ]; then
        SOURCES+=("$target_path")
        log "Dodano katalog źródłowy: $target_path"
    else
        log "OSTRZEŻENIE: Katalog źródłowy $target_path nie istnieje - pomijam."
    fi
done

if [ ${#SOURCES[@]} -eq 0 ]; then
    log "BŁĄD: Żaden z katalogów źródłowych nie istnieje!"
    exit 1
fi

# 2. Test łączności SSH do Proxmox
if ! ssh -q -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" exit 2>/dev/null; then
    log "BŁĄD: Brak połączenia SSH do $REMOTE_HOST (timeout lub brak autoryzacji kluczem)."
    exit 2
fi

# 3. Upewnienie się, że katalog docelowy istnieje na Proxmox
ssh "$REMOTE_HOST" "mkdir -p \"${REMOTE_DIR}\""

# 3b. Zabezpieczenie: Sprawdzenie wolnego miejsca na Proxmoxie (min. 15 GB)
MIN_FREE_KB=$((15 * 1024 * 1024))
FREE_KB=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$REMOTE_HOST" "df -k \"${REMOTE_DIR}\" | awk 'NR==2 {print \$4}'" 2>/dev/null || echo 0)

if [ "$FREE_KB" -lt "$MIN_FREE_KB" ]; then
    log "BŁĄD: Za mało wolnego miejsca na ${REMOTE_HOST} w ${REMOTE_DIR} (dostępne: $((FREE_KB / 1024 / 1024)) GB, wymagane min. 15 GB). Przerywam transfer, aby zapobiec freeze'owi serwera!"
    exit 3
fi

# 4. Flagi i filtry rsync (ograniczenie pasma do 25 MB/s, tylko pliki wideo)
RSYNC_FLAGS=("-av" "--partial" "--bwlimit=25M")
if [ -t 1 ]; then
    RSYNC_FLAGS+=("--info=progress2")
fi
if [ "$DELETE_EXTRANEOUS" = true ]; then
    RSYNC_FLAGS+=("--delete")
fi

# Filtry rsync: wchodź w podkatalogi, przenoś tylko pliki wideo, pomijaj pliki playlist i pozostałe
RSYNC_FILTERS=(
    "--include=*/"
    "--include=*.mp4"
    "--include=*.mkv"
    "--include=*.webm"
    "--include=*.avi"
    "--include=*.mov"
    "--exclude=*.m3u"
    "--exclude=*.m3u8"
    "--exclude=*.pls"
    "--exclude=*"
)

log "Uruchamianie rsync dla: ${DIRECTORIES[*]} (limit pasma 25 MB/s, tylko wideo)..."
rsync "${RSYNC_FLAGS[@]}" "${RSYNC_FILTERS[@]}" $CHOWN_OPTS "${SOURCES[@]}" "${REMOTE_HOST}:${REMOTE_DIR}" 2>&1 | tee -a "$LOG_FILE"

log "Synchronizacja zakończona sukcesem."
log "================================================================="
