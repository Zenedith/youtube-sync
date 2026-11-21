#!/bin/bash

# ============================================================
# youtube-sync.sh
# Synchronizuje kanały oraz ulubione filmy YouTube do lokalnych katalogów.
# Używa dedykowanego kontenera Docker (youtube-sync:latest) z yt-dlp,
# ffmpeg i Deno (rozwiązywanie n-challenge YouTube).
#
# Ulubione filmy (favourites) są pobierane w 2 etapach:
# 1. Manifest / lista JSON wygenerowana bez cookies (export-favourites.js).
# 2. Pobieranie wideo z pliku favourites.json w pełni anonimowo (bez cookies).
# ============================================================

BASE_DIR="/mnt/user/videos/youtube"
TEMP_DIR="/tmp/yt-dlp-tmp"
DOCKER_IMAGE="youtube-sync:latest"
IMAGE_MAX_AGE_DAYS=7
FAVOURITES_JSON="${BASE_DIR}/favourites.json"
FORCE_UPDATE=false

# ============================================================
# LISTA KANAŁÓW PUBLICZNYCH
# Format: "NAZWA_KATALOGU|URL"
# ============================================================
CHANNELS=(
    "partyzanci-lubelszczyzny|https://www.youtube.com/@partyzancilubelszczyzny/videos"
    "czarna_godzina|https://www.youtube.com/@czarna_godzina_official/videos"
    "PolitraumaPL|https://www.youtube.com/@PolitraumaPL/videos"
    "OZE4HOME|https://www.youtube.com/@OZE4HOME/videos"
    # "drugi-kanal|https://www.youtube.com/@przyklad/videos"
)

# ============================================================

GLOBAL_LOG="${BASE_DIR}/sync.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$GLOBAL_LOG"
}

log_channel() {
    local log_file="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$log_file" -a "$GLOBAL_LOG"
}

check_dependencies() {
    if ! command -v docker &>/dev/null; then
        log "ERROR: Docker nie jest zainstalowany lub niedostępny w PATH."
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log "ERROR: Docker daemon nie działa lub brak uprawnień."
        exit 1
    fi

    log "Docker wersja: $(docker --version)"

    # Automatyczne budowanie lub aktualizacja obrazu (gdy starszy niż IMAGE_MAX_AGE_DAYS dni lub użyto --update)
    local need_build=false
    local image_exists=false

    if docker image inspect "$DOCKER_IMAGE" &>/dev/null; then
        image_exists=true
        if [[ "$FORCE_UPDATE" == true ]]; then
            log "Wymuszono aktualizację obrazu ${DOCKER_IMAGE} (--update)..."
            need_build=true
        else
            local created_iso created_ts now_ts age_days
            created_iso=$(docker image inspect -f '{{.Created}}' "$DOCKER_IMAGE" 2>/dev/null)
            created_ts=$(date -d "$created_iso" +%s 2>/dev/null || echo "")
            if [[ -n "$created_ts" ]]; then
                now_ts=$(date +%s)
                age_days=$(( (now_ts - created_ts) / 86400 ))
                if (( age_days >= IMAGE_MAX_AGE_DAYS )); then
                    log "Obraz ${DOCKER_IMAGE} ma ${age_days} dni (>= ${IMAGE_MAX_AGE_DAYS}). Aktualizuję yt-dlp..."
                    need_build=true
                fi
            fi
        fi
    else
        log "Obraz ${DOCKER_IMAGE} nie istnieje. Rozpoczynam budowanie z ${BASE_DIR}/Dockerfile..."
        need_build=true
    fi

    if [[ "$need_build" == true ]]; then
        if [[ -f "${BASE_DIR}/Dockerfile" ]]; then
            if docker build --build-arg "YTDLP_CACHE_BUST=$(date +%s)" -t "$DOCKER_IMAGE" "$BASE_DIR"; then
                log "Obraz ${DOCKER_IMAGE} zaktualizowany pomyślnie."
            else
                if [[ "$image_exists" == true ]]; then
                    log "WARNING: Aktualizacja obrazu ${DOCKER_IMAGE} nie powiodła się. Używam istniejącej wersji."
                else
                    log "ERROR: Budowanie obrazu ${DOCKER_IMAGE} nie powiodło się."
                    exit 1
                fi
            fi
        else
            if [[ "$image_exists" == true ]]; then
                log "WARNING: Brak pliku ${BASE_DIR}/Dockerfile - pomijam aktualizację."
            else
                log "ERROR: Brak pliku ${BASE_DIR}/Dockerfile do zbudowania obrazu."
                exit 1
            fi
        fi
    fi
}

prepare_dirs() {
    mkdir -p "$BASE_DIR"
    mkdir -p "$TEMP_DIR"
    mkdir -p "${BASE_DIR}/favourites"
    touch "$GLOBAL_LOG"
}

count_archive() {
    local archive_file="$1"
    if [[ -f "$archive_file" ]]; then
        wc -l < "$archive_file" | tr -d ' '
    else
        echo "0"
    fi
}

sync_favourites_from_json() {
    local name="favourites"
    local output_dir="${BASE_DIR}/${name}"
    local archive_file="${BASE_DIR}/${name}.archive"
    local log_file="${BASE_DIR}/${name}.log"
    local container_name="yt-dlp-${name}"

    if [[ ! -f "$FAVOURITES_JSON" ]]; then
        log "Brak pliku ${FAVOURITES_JSON} - pomijam synchronizację ulubionych."
        log "Wskazówka: Użyj skryptu export-favourites.js w przeglądarce, aby wygenerować plik."
        return 0
    fi

    # Format nazw: tylko tytuł filmu (bez daty i bez nazwy kanału)
    local output_template="/downloads/%(title)s [%(id)s].%(ext)s"

    mkdir -p "$output_dir"
    touch "$archive_file"
    touch "$log_file"

    log_channel "$log_file" "========================================================"
    log_channel "$log_file" "Rozpoczynam synchronizację: ${name} z pliku ${FAVOURITES_JSON}"
    log_channel "$log_file" "Katalog docelowy: ${output_dir}"
    log_channel "$log_file" "Już pobrane: $(count_archive "$archive_file") filmów"
    log_channel "$log_file" "Pobieranie w pełni anonimowe (brak cookies - brak ryzyka blokady konta)"
    log_channel "$log_file" "========================================================"

    # Wyodrębnienie URLi z pliku JSON i pobieranie w kontenerze
    docker run \
        --rm \
        --name "$container_name" \
        -v "${output_dir}:/downloads" \
        -v "${BASE_DIR}:/archive" \
        -v "${TEMP_DIR}:/tmp" \
        --network host \
        "$DOCKER_IMAGE" \
        bash -c '
            python3 -c "import json; [print(x.get(\"url\")) for x in json.load(open(\"/archive/favourites.json\")) if x.get(\"url\")]" > /tmp/favourites_urls.txt
            yt-dlp \
                --ignore-errors \
                --no-abort-on-error \
                -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best" \
                --merge-output-format mp4 \
                --download-archive "/archive/'"$name"'.archive" \
                --continue \
                --part \
                --paths "temp:/tmp" \
                --embed-thumbnail \
                --embed-metadata \
                --add-metadata \
                -o "'"$output_template"'" \
                --retries 10 \
                --fragment-retries 10 \
                --retry-sleep 5 \
                --print "before_dl:Pobieranie: %(title)s" \
                --no-progress \
                --batch-file /tmp/favourites_urls.txt
        ' 2>&1 | tee -a "$log_file" | grep -v "^$" >&2

    local exit_code=${PIPESTATUS[0]}

    log_channel "$log_file" "Zakończono: ${name} | kod wyjścia: ${exit_code} | łącznie w archiwum: $(count_archive "$archive_file") filmów"
    log_channel "$log_file" "========================================================"

    return $exit_code
}

sync_channel() {
    local name="$1"
    local url="$2"

    local output_dir="${BASE_DIR}/${name}"
    local archive_file="${BASE_DIR}/${name}.archive"
    local log_file="${BASE_DIR}/${name}.log"
    local container_name="yt-dlp-${name}"

    local output_template="/downloads/%(upload_date>%Y-%m-%d)s - %(title)s [%(id)s].%(ext)s"

    mkdir -p "$output_dir"
    touch "$archive_file"
    touch "$log_file"

    log_channel "$log_file" "========================================================"
    log_channel "$log_file" "Kanał: ${name}"
    log_channel "$log_file" "URL: ${url}"
    log_channel "$log_file" "Katalog docelowy: ${output_dir}"
    log_channel "$log_file" "Już pobrane: $(count_archive "$archive_file") filmów"
    log_channel "$log_file" "========================================================"

    docker run \
        --rm \
        --name "$container_name" \
        -v "${output_dir}:/downloads" \
        -v "${BASE_DIR}:/archive" \
        -v "${TEMP_DIR}:/tmp" \
        --network host \
        "$DOCKER_IMAGE" \
        yt-dlp \
            --ignore-errors \
            --no-abort-on-error \
            -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best" \
            --merge-output-format mp4 \
            --download-archive "/archive/${name}.archive" \
            --continue \
            --part \
            --paths "temp:/tmp" \
            --embed-thumbnail \
            --embed-metadata \
            --add-metadata \
            -o "${output_template}" \
            --retries 10 \
            --fragment-retries 10 \
            --retry-sleep 5 \
            --print "before_dl:[%(upload_date>%Y-%m-%d)s] Pobieranie: %(title)s" \
            --no-progress \
            "${url}" \
        2>&1 | tee -a "$log_file" | grep -v "^$" >&2

    local exit_code=${PIPESTATUS[0]}

    log_channel "$log_file" "Zakończono kanał: ${name} | kod wyjścia: ${exit_code} | łącznie w archiwum: $(count_archive "$archive_file") filmów"
    log_channel "$log_file" "========================================================"

    return $exit_code
}

stop_all_containers() {
    local all_names=("favourites")
    for entry in "${CHANNELS[@]}"; do
        all_names+=("${entry%%|*}")
    done

    for name in "${all_names[@]}"; do
        local container_name="yt-dlp-${name}"
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            log "Zatrzymywanie kontenera ${container_name}..."
            docker stop "$container_name" &>/dev/null
        fi
    done
}

# ============================================================
# MAIN
# ============================================================

for arg in "$@"; do
    case "$arg" in
        -u|--update)
            FORCE_UPDATE=true
            ;;
    esac
done

trap 'log "Przerwano przez użytkownika."; stop_all_containers; exit 130' INT TERM

check_dependencies
prepare_dirs

log "###################################################"
log "Rozpoczynam synchronizację YouTube"
log "###################################################"

overall_exit=0

# 1. Synchronizacja ulubionych (z pliku favourites.json)
sync_favourites_from_json
if [[ $? -ne 0 ]]; then
    overall_exit=1
fi

# 2. Synchronizacja kanałów
for entry in "${CHANNELS[@]}"; do
    name="${entry%%|*}"
    url="${entry##*|}"
    sync_channel "$name" "$url"
    if [[ $? -ne 0 ]]; then
        overall_exit=1
    fi
done

log "###################################################"
log "Wszystkie pozycje przetworzone. Kod wyjścia: ${overall_exit}"
log "###################################################"

exit $overall_exit
