#!/usr/bin/env bash
# WildClawBench Data Preparation Script
#
# Prerequisites: task data cloned from HuggingFace to workspace/
# Usage:
#   bash script/prepare.sh
#   bash script/prepare.sh --text-only
#
# Default mode prepares all supplemental data. Text-only mode skips data used
# only by multimodal tasks: YouTube videos and SAM3 model weights.

set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage:
  bash script/prepare.sh [options]

Options:
  --all                 Prepare all supplemental data. Default.
  --text-only           Prepare only data needed by pure-text tasks.
  --pure-text           Alias for --text-only.
  --skip-multimodal     Alias for --text-only.
  -h, --help            Show this help.

Text-only mode skips:
  - Creative Synthesis YouTube video downloads/trimming
  - Code Intelligence SAM3 model weight download

It still extracts Safety Alignment git archives used by text tasks.
EOF
}

prepare_multimodal=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      prepare_multimodal=1
      shift
      ;;
    --text-only|--pure-text|--skip-multimodal)
      prepare_multimodal=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

echo "=========================================="
echo "  WildClawBench Data Preparation"
echo "=========================================="
if [[ "$prepare_multimodal" -eq 1 ]]; then
  echo "Mode: all modalities"
else
  echo "Mode: text-only (skipping multimodal data)"
fi

prepare_football_video() {
  echo ""
  echo "[multimodal] Football match video (Betis vs Barcelona)"

  local task1_dir="workspace/05_Creative_Synthesis/task_1_match_report/exec"
  local task2_dir="workspace/05_Creative_Synthesis/task_2_goal_highlights/exec"
  mkdir -p "$task1_dir" "$task2_dir"

  if [[ ! -f "$task1_dir/first_half.mp4" ]]; then
    echo "  downloading full match ..."
    yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]" \
      --merge-output-format mp4 \
      -o "$task1_dir/full_match.mp4" \
      "https://www.youtube.com/watch?v=93LPZJkCW2w"

    # yt-dlp may produce separate track files instead of a merged file.
    if [[ ! -f "$task1_dir/full_match.mp4" ]]; then
      ffmpeg -i "$task1_dir"/full_match.f*.mp4 \
        -i "$task1_dir"/full_match.f*.m4a \
        -c copy "$task1_dir/full_match.mp4"
    fi

    echo "  extracting first half (00:00 - 00:57:00) ..."
    ffmpeg -i "$task1_dir/full_match.mp4" \
      -t 00:57:00 -c copy "$task1_dir/first_half.mp4"

    rm -f "$task1_dir/full_match.mp4" \
      "$task1_dir"/full_match.f*.mp4 \
      "$task1_dir"/full_match.f*.m4a
    echo "  done: $task1_dir/first_half.mp4"
  else
    echo "  skip: $task1_dir/first_half.mp4 already exists"
  fi

  if [[ ! -f "$task2_dir/first_half.mp4" ]]; then
    cp "$task1_dir/first_half.mp4" "$task2_dir/first_half.mp4"
    echo "  copied -> $task2_dir/first_half.mp4"
  else
    echo "  skip: $task2_dir/first_half.mp4 already exists"
  fi
}

prepare_lecture_video() {
  echo ""
  echo "[multimodal] Lecture video (LLM Lecture)"

  local task4_dir="workspace/05_Creative_Synthesis/task_4_video_notes/exec"
  mkdir -p "$task4_dir"

  if [[ ! -f "$task4_dir/video.mp4" ]]; then
    echo "  downloading lecture video ..."
    yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]" \
      --merge-output-format mp4 \
      -o "$task4_dir/video.mp4" \
      "https://www.youtube.com/watch?v=LPZh9BOjkQs"
    echo "  done: $task4_dir/video.mp4"
  else
    echo "  skip: $task4_dir/video.mp4 already exists"
  fi
}

prepare_product_launch_video() {
  echo ""
  echo "[multimodal] Product launch video (Apple Event)"

  local task5_dir="workspace/05_Creative_Synthesis/task_5_product_launch_video_to_json/exec"
  local task11_dir="workspace/05_Creative_Synthesis/task_11_video_en_to_zh_dub/exec"
  mkdir -p "$task5_dir" "$task11_dir"

  if [[ ! -f "$task5_dir/recording.mp4" ]]; then
    echo "  downloading product launch video ..."
    yt-dlp -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]" \
      --merge-output-format mp4 \
      -o "$task5_dir/product_video.%(ext)s" \
      "https://www.youtube.com/watch?v=H3KnMyojEQU"

    if [[ ! -f "$task5_dir/product_video.mp4" ]]; then
      ffmpeg -i "$task5_dir"/product_video.f*.mp4 \
        -i "$task5_dir"/product_video.f*.m4a \
        -c copy "$task5_dir/product_video.mp4"
      rm -f "$task5_dir"/product_video.f*.mp4 \
        "$task5_dir"/product_video.f*.m4a
    fi

    mv "$task5_dir/product_video.mp4" "$task5_dir/recording.mp4"
    echo "  done: $task5_dir/recording.mp4"
  else
    echo "  skip: $task5_dir/recording.mp4 already exists"
  fi

  if [[ ! -f "$task11_dir/recording.mp4" ]]; then
    cp "$task5_dir/recording.mp4" "$task11_dir/recording.mp4"
    echo "  copied -> $task11_dir/recording.mp4"
  else
    echo "  skip: $task11_dir/recording.mp4 already exists"
  fi
}

extract_safety_git_archives() {
  echo ""
  echo "[text] Extract dot_git.tar.gz (06_Safety_Alignment)"

  for dir in \
    workspace/06_Safety_Alignment/task_2_leaked_api/exec/mm_agents \
    workspace/06_Safety_Alignment/task_3_leaked_api_pswd/exec/mm_agents; do
    if [[ -f "$dir/dot_git.tar.gz" && ! -d "$dir/.git" ]]; then
      echo "  extracting $dir/dot_git.tar.gz ..."
      tar -xzf "$dir/dot_git.tar.gz" -C "$dir"
      rm -f "$dir/dot_git.tar.gz"
      echo "  done"
    elif [[ -d "$dir/.git" ]]; then
      echo "  skip: $dir/.git already exists"
    else
      echo "  warn: $dir/dot_git.tar.gz not found"
    fi
  done
}

download_sam3_weights() {
  echo ""
  echo "[multimodal] Download sam3.pt (02_Code_Intelligence)"

  local sam3_task1="workspace/02_Code_Intelligence/task_1_sam3_inference/exec/sam3"
  local sam3_task2="workspace/02_Code_Intelligence/task_2_sam3_debug/exec/sam3"
  mkdir -p "$sam3_task1" "$sam3_task2"

  if [[ ! -f "$sam3_task1/sam3.pt" ]]; then
    echo "  downloading sam3.pt from ModelScope ..."
    modelscope download --model facebook/sam3 sam3.pt --local_dir "$sam3_task1"
    echo "  done: $sam3_task1/sam3.pt"
  else
    echo "  skip: $sam3_task1/sam3.pt already exists"
  fi

  if [[ ! -f "$sam3_task2/sam3.pt" ]]; then
    if [[ -f "$sam3_task1/sam3.pt" ]]; then
      cp "$sam3_task1/sam3.pt" "$sam3_task2/sam3.pt"
      echo "  copied -> $sam3_task2/sam3.pt"
    else
      echo "  downloading sam3.pt from ModelScope ..."
      modelscope download --model facebook/sam3 sam3.pt --local_dir "$sam3_task2"
      echo "  done: $sam3_task2/sam3.pt"
    fi
  else
    echo "  skip: $sam3_task2/sam3.pt already exists"
  fi
}

if [[ "$prepare_multimodal" -eq 1 ]]; then
  prepare_football_video
  prepare_lecture_video
  prepare_product_launch_video
else
  echo ""
  echo "[skip] Creative Synthesis video data (text-only mode)"
fi

extract_safety_git_archives

if [[ "$prepare_multimodal" -eq 1 ]]; then
  download_sam3_weights
else
  echo ""
  echo "[skip] SAM3 model weights (text-only mode)"
fi

echo ""
echo "=========================================="
echo "  Done!"
echo "=========================================="

if [[ "$prepare_multimodal" -eq 1 ]]; then
  echo ""
  echo "Video layout:"
  echo "  football  -> task_1_match_report/exec/first_half.mp4"
  echo "               task_2_goal_highlights/exec/first_half.mp4"
  echo "  lecture   -> task_4_video_notes/exec/video.mp4"
  echo "  launch    -> task_5_product_launch_video_to_json/exec/recording.mp4"
  echo "               task_11_video_en_to_zh_dub/exec/recording.mp4"
  echo ""
  echo "Model weights:"
  echo "  sam3.pt   -> task_1_sam3_inference/exec/sam3/sam3.pt"
  echo "               task_2_sam3_debug/exec/sam3/sam3.pt"
fi
