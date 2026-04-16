#!/bin/bash
# Render the Blurr: Evolution of Racing video
# Usage: ./scripts/render-blurr.sh [path/to/instrumental.mp3]
#
# Prerequisites:
#   - Seedance clips in public/clips/blurr/seedance_v{1..4}_*.mp4
#   - PDR clips already prepared in public/clips/blurr/
#   - DJI orbit clip in public/clips/blurr/
#
# The script:
#   1. Validates all clip files exist
#   2. Runs the Remotion pipeline with --no-audio (no TTS needed)
#   3. If an instrumental track is provided, mixes it in via ffmpeg

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
PROJECT_DIR="$(realpath "$SCRIPT_DIR/..")"
SCRIPT_JSON="$PROJECT_DIR/scripts/blurr-evolution.json"
INSTRUMENTAL="${1:-}"

echo "=== BLURR: Evolution of Racing ==="
echo ""

# Validate required clips
MISSING=0
CLIPS=(
  "clips/blurr/seedance_v1_heritage.mp4"
  "clips/blurr/seedance_v2_f1tenth.mp4"
  "clips/blurr/seedance_v3_engineering.mp4"
  "clips/blurr/seedance_v4_c8.mp4"
  "clips/blurr/pdr_switchback_071g.mp4"
  "clips/blurr/pdr_foggy_mountain.mp4"
  "clips/blurr/pdr_mountain_vista.mp4"
  "clips/blurr/dji_orbit_c8.mp4"
)

echo "Checking clips..."
for clip in "${CLIPS[@]}"; do
  if [ ! -f "$PROJECT_DIR/public/$clip" ]; then
    echo "  MISSING: $clip"
    MISSING=$((MISSING + 1))
  else
    DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$PROJECT_DIR/public/$clip" 2>/dev/null || echo "?")
    echo "  OK: $clip (${DUR}s)"
  fi
done

if [ "$MISSING" -gt 0 ]; then
  echo ""
  echo "ERROR: $MISSING clip(s) missing. Add Seedance outputs to public/clips/blurr/"
  echo "Expected filenames: seedance_v1_heritage.mp4, seedance_v2_f1tenth.mp4, etc."
  exit 1
fi

echo ""
echo "All clips present. Rendering..."
echo ""

# Render video (no TTS -- instrumental only)
cd "$PROJECT_DIR"
source ~/.env.shared
npx tsx scripts/pipeline.ts --no-audio --script "$SCRIPT_JSON"

# Find the output file (most recent mp4 in output/)
OUTPUT=$(ls -t "$PROJECT_DIR/output/"*.mp4 2>/dev/null | head -1)

if [ -z "$OUTPUT" ]; then
  echo "ERROR: No output file found after render"
  exit 1
fi

echo ""
echo "Render complete: $OUTPUT"

# Mix in instrumental if provided
if [ -n "$INSTRUMENTAL" ]; then
  if [ ! -f "$INSTRUMENTAL" ]; then
    echo "ERROR: Instrumental file not found: $INSTRUMENTAL"
    exit 1
  fi

  FINAL="${OUTPUT%.mp4}-with-music.mp4"
  echo ""
  echo "Mixing instrumental: $INSTRUMENTAL"
  echo "Output: $FINAL"

  # Get video duration to trim/loop the instrumental
  VIDEO_DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUTPUT")

  # Mix: video + instrumental (looped if shorter than video, faded out at end)
  ffmpeg -i "$OUTPUT" -i "$INSTRUMENTAL" \
    -filter_complex "[1:a]aloop=-1:2e+09,atrim=0:$VIDEO_DUR,afade=t=out:st=$(echo "$VIDEO_DUR - 3" | bc):d=3[music]" \
    -map 0:v -map "[music]" \
    -c:v copy -c:a aac -b:a 192k \
    -shortest \
    "$FINAL" -y

  echo ""
  echo "=== DONE ==="
  echo "Final video: $FINAL"
  echo "Duration: ${VIDEO_DUR}s"
else
  echo ""
  echo "=== DONE (no instrumental) ==="
  echo "To add music later:"
  echo "  ./scripts/render-blurr.sh path/to/instrumental.mp3"
  echo "Or manually:"
  echo "  ffmpeg -i $OUTPUT -i music.mp3 -filter_complex '[1:a]afade=t=out:st=<dur-3>:d=3[m]' -map 0:v -map '[m]' -c:v copy -shortest output/blurr-final.mp4"
fi
