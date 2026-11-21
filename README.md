# youtube-sync

Zestaw skryptów do synchronizacji publicznych kanałów oraz ulubionych filmów z YouTube do lokalnych katalogów (np. na serwerze Unraid), oparty o dedykowany kontener Docker (`yt-dlp[default]` + `ffmpeg` + silnik JS `Deno`).

## Pliki w repozytorium

- **`youtube-sync.sh`** – główny skrypt synchronizujący:
  - pobiera kanały z tablicy `CHANNELS` (`YYYY-MM-DD - Tytuł [ID].mp4`),
  - pobiera ulubione filmy z manifestu `favourites.json` do katalogu `favourites/` (`Tytuł [ID].mp4`) w pełni anonimowo (bez cookies),
  - wspiera wznawianie przerwanych pobierań (`--continue`, `--part`) oraz pomijanie już pobranych materiałów (`--download-archive`),
  - automatycznie buduje obraz `youtube-sync:latest` z `Dockerfile` i odświeża `yt-dlp`, gdy obraz ma >= 7 dni (lub natychmiast z flagą `--update` / `-u`).
- **`Dockerfile`** – lekki obraz oparty na `python:3.11-slim` z `ffmpeg`, `Deno` (do rozwiązywania wyzwań JS YouTube / `n-challenge`) oraz `yt-dlp[default]`.
- **`export-favourites.js`** – skrypt JS do uruchomienia w konsoli przeglądarki na liście [Polubione filmy](https://www.youtube.com/playlist?list=LL), który zbiera filmy bez konieczności eksportowania ciasteczek.
- **`sync-youtube-to-proxmox.sh`** – pomocniczy skrypt `rsync` synchronizujący wybrane katalogi z Unraid na Proxmox (np. do biblioteki Jellyfin).
- **`favourites.example.json`** – przykładowy format pliku `favourites.json`.

## Użycie

### 1. Uruchomienie synchronizacji

```bash
chmod +x youtube-sync.sh
./youtube-sync.sh
```

Wymuszenie aktualizacji `yt-dlp` w obrazie Dockera:

```bash
./youtube-sync.sh --update
```

### 2. Eksport ulubionych (`favourites.json`)

1. Otwórz w przeglądarce `https://www.youtube.com/playlist?list=LL` i przewiń listę do załadowania pożądanych filmów.
2. W konsoli przeglądarki (DevTools) wygeneruj listę za pomocą `export-favourites.js` (lub wklej jednolinijkowiec z użyciem `copy(...)`).
3. Zapisz wynik jako `favourites.json` w katalogu docelowym (`BASE_DIR`, domyślnie `/mnt/user/videos/youtube/favourites.json`).
