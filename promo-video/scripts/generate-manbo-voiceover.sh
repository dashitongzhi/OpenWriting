#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VIDEO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EDGE_TTS="$VIDEO_ROOT/.venv/bin/edge-tts"

if [[ ! -x "$EDGE_TTS" ]]; then
  echo "edge-tts is missing. Run: python3 -m venv .venv && .venv/bin/pip install edge-tts" >&2
  exit 1
fi

"$EDGE_TTS" \
  --voice zh-CN-XiaoyiNeural \
  --rate=+18% \
  --pitch=+8Hz \
  --file "$VIDEO_ROOT/voiceover-manbo.txt" \
  --write-media "$VIDEO_ROOT/public/audio/voiceover-manbo.mp3" \
  --write-subtitles "$VIDEO_ROOT/public/audio/voiceover-manbo.vtt"

perl -0pi -e 's/\s+\z/\n/' "$VIDEO_ROOT/public/audio/voiceover-manbo.vtt"

node "$VIDEO_ROOT/scripts/vtt-to-captions.mjs" \
  public/audio/voiceover-manbo.vtt \
  public/audio/captions-manbo.json

ffprobe -v error \
  -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 \
  "$VIDEO_ROOT/public/audio/voiceover-manbo.mp3"
