FROM python:3.11-slim

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends ffmpeg curl unzip ca-certificates && \
    curl -fsSL https://deno.land/install.sh | sh && \
    apt-get purge -y curl unzip && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.deno/bin:${PATH}"

ARG YTDLP_CACHE_BUST=1
RUN pip install --no-cache-dir --upgrade --root-user-action=ignore "yt-dlp[default]"
