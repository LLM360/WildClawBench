#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash script/run_pure_text_english.sh <backend> [options] [run_batch args...]

Backends:
  openclaw | claudecode | codex | hermesagent

Options handled by this wrapper:
  --list                 Print selected task files and exit.
  --fail-fast            Stop after the first failed task.
  --jobs N               Run up to N tasks concurrently. Default: 29.
  --model_base_url URL   Use a custom OpenAI-compatible endpoint.
  --model_name NAME      Model id/name for the custom endpoint.
  --api_key KEY          Optional API key for the custom endpoint.
  --preserve-thinking [BOOL]
                         Set OpenClaw agents.defaults.params.preserveThinking.
                         With no BOOL, defaults to true. Also accepts
                         --no-preserve-thinking.
  -h, --help             Show this help.

All remaining arguments are forwarded to script/run.sh for each task.

Examples:
  bash script/run_pure_text_english.sh openclaw --model openrouter/openai/gpt-5.5
  bash script/run_pure_text_english.sh codex --thinking high --model openrouter/openai/gpt-5.5
  bash script/run_pure_text_english.sh openclaw --model_base_url http://host.docker.internal:8000/v1 --model_name my-model --api_key sk-local

Do not pass --task or --category here; this wrapper chooses the task list.
Outputs are written as output/<backend>/<model>/<task_name>.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

backend="$1"
shift

case "$backend" in
  openclaw|claudecode|codex|hermesagent) ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "Unknown backend: $backend" >&2
    echo "Expected one of: openclaw, claudecode, codex, hermesagent" >&2
    exit 1
    ;;
esac

list_only=0
fail_fast=0
jobs=29
model_base_url=""
model_name=""
api_key=""
api_key_set=0
preserve_thinking=""
forwarded_model=0
forwarded_models_config=0
forward_args=()

normalize_bool() {
  local name="$1"
  local value="$2"
  case "${value,,}" in
    1|true|yes|y|on)
      printf '%s\n' true
      ;;
    0|false|no|n|off)
      printf '%s\n' false
      ;;
    *)
      echo "$name must be a boolean: true/false, yes/no, on/off, or 1/0; got: $value" >&2
      exit 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)
      list_only=1
      shift
      ;;
    --fail-fast)
      fail_fast=1
      shift
      ;;
    --jobs)
      if [[ $# -lt 2 ]]; then
        echo "--jobs requires a positive integer argument." >&2
        exit 1
      fi
      jobs="$2"
      shift 2
      ;;
    --jobs=*)
      jobs="${1#*=}"
      shift
      ;;
    --model_base_url|--model-base-url)
      if [[ $# -lt 2 ]]; then
        echo "$1 requires a URL argument." >&2
        exit 1
      fi
      model_base_url="$2"
      shift 2
      ;;
    --model_base_url=*|--model-base-url=*)
      model_base_url="${1#*=}"
      shift
      ;;
    --model_name|--model-name)
      if [[ $# -lt 2 ]]; then
        echo "$1 requires a model name argument." >&2
        exit 1
      fi
      model_name="$2"
      shift 2
      ;;
    --model_name=*|--model-name=*)
      model_name="${1#*=}"
      shift
      ;;
    --api_key|--api-key)
      if [[ $# -lt 2 ]]; then
        echo "$1 requires an API key argument." >&2
        exit 1
      fi
      api_key="$2"
      api_key_set=1
      shift 2
      ;;
    --api_key=*|--api-key=*)
      api_key="${1#*=}"
      api_key_set=1
      shift
      ;;
    --preserve-thinking|--preserveThinking)
      if [[ $# -ge 2 && ! "$2" =~ ^- ]]; then
        preserve_thinking="$(normalize_bool "$1" "$2")"
        shift 2
      else
        preserve_thinking="true"
        shift
      fi
      ;;
    --preserve-thinking=*|--preserveThinking=*)
      preserve_thinking="$(normalize_bool "${1%%=*}" "${1#*=}")"
      shift
      ;;
    --no-preserve-thinking|--no-preserveThinking)
      preserve_thinking="false"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --task|-t|--category|-c)
      echo "Do not pass $1 to this wrapper; it selects tasks itself." >&2
      exit 1
      ;;
    --model|-m|--model=*)
      forwarded_model=1
      forward_args+=("$1")
      shift
      ;;
    -m?*)
      forwarded_model=1
      forward_args+=("$1")
      shift
      ;;
    --models-config|--models-config=*)
      forwarded_models_config=1
      forward_args+=("$1")
      shift
      ;;
    *)
      forward_args+=("$1")
      shift
      ;;
  esac
done

if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "--jobs must be a positive integer; got: $jobs" >&2
  exit 1
fi

custom_endpoint_requested=0
if [[ -n "$model_base_url" || -n "$model_name" || "$api_key_set" -eq 1 ]]; then
  custom_endpoint_requested=1
fi

if [[ "$custom_endpoint_requested" -eq 1 ]]; then
  if [[ "$backend" != "openclaw" ]]; then
    echo "--model_base_url/--model_name custom endpoint generation currently supports the openclaw backend only." >&2
    exit 1
  fi
  if [[ -z "$model_base_url" || -z "$model_name" ]]; then
    echo "--model_base_url and --model_name are required when using a custom endpoint." >&2
    exit 1
  fi
  if [[ "$forwarded_model" -eq 1 ]]; then
    echo "Do not pass --model/-m with --model_base_url/--model_name; the wrapper derives --model automatically." >&2
    exit 1
  fi
  if [[ "$forwarded_models_config" -eq 1 ]]; then
    echo "Do not pass --models-config with --model_base_url/--model_name; the wrapper generates the config automatically." >&2
    exit 1
  fi
fi

if [[ -n "$preserve_thinking" ]]; then
  if [[ "$backend" != "openclaw" ]]; then
    echo "--preserve-thinking configures OpenClaw only; backend must be openclaw." >&2
    exit 1
  fi
  forward_args=(--openclaw-preserve-thinking "$preserve_thinking" "${forward_args[@]}")
fi

custom_models_config=""
export WILDCLAW_OUTPUT_LAYOUT=model_task

cleanup_custom_models_config() {
  if [[ -n "${custom_models_config:-}" && -f "$custom_models_config" ]]; then
    rm -f "$custom_models_config"
  fi
}

trap cleanup_custom_models_config EXIT

sanitize_output_name() {
  python3 - "$1" <<'PY'
import re
import sys
value = sys.argv[1] if len(sys.argv) > 1 else ""
value = re.sub(r"[^a-zA-Z0-9.\-_]", "_", value)
print(value or "model")
PY
}

extract_forwarded_model() {
  local idx arg
  for ((idx = 0; idx < ${#forward_args[@]}; idx++)); do
    arg="${forward_args[$idx]}"
    case "$arg" in
      --model=*)
        printf '%s\n' "${arg#*=}"
        return 0
        ;;
      -m?*)
        printf '%s\n' "${arg#-m}"
        return 0
        ;;
      --model|-m)
        if ((idx + 1 < ${#forward_args[@]})); then
          printf '%s\n' "${forward_args[$((idx + 1))]}"
          return 0
        fi
        ;;
    esac
  done
  return 1
}

reserve_output_model_dir() {
  local root="$1"
  local base="$2"
  local trial=1
  local candidate=""

  if ! mkdir -p "$root"; then
    echo "Failed to create output root: $root" >&2
    exit 1
  fi

  while true; do
    if [[ "$trial" -eq 1 ]]; then
      candidate="$base"
    else
      candidate="${base}-trial-${trial}"
    fi

    if mkdir "$root/$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi

    if [[ ! -e "$root/$candidate" ]]; then
      echo "Failed to reserve output directory: $root/$candidate" >&2
      exit 1
    fi

    trial=$((trial + 1))
  done
}

# Pure-text tasks whose benchmark instructions and required outputs are English.
PURE_TEXT_ENGLISH_TASKS=(
  "tasks/01_Productivity_Flow/01_Productivity_Flow_task_1_arxiv_digest.md"
  "tasks/01_Productivity_Flow/01_Productivity_Flow_task_2_table_tex_download.md"
  "tasks/01_Productivity_Flow/01_Productivity_Flow_task_3_bibtex.md"
  "tasks/01_Productivity_Flow/01_Productivity_Flow_task_4_2022_conference_papers.md"
  "tasks/01_Productivity_Flow/01_Productivity_Flow_task_6_calendar_scheduling.md"
  "tasks/03_Social_Interaction/03_Social_Interaction_task_1_meeting_negotiation.md"
  "tasks/03_Social_Interaction/03_Social_Interaction_task_2_chat_action_extraction.md"
  "tasks/03_Social_Interaction/03_Social_Interaction_task_3_chat_multi_step_reasoning.md"
  "tasks/03_Social_Interaction/03_Social_Interaction_task_4_chat_thread_consolidation.md"
  "tasks/03_Social_Interaction/03_Social_Interaction_task_5_chat_escalation_routing.md"
  "tasks/04_Search_Retrieval/04_Search_Retrieval_task_1_google_scholar_search.md"
  "tasks/04_Search_Retrieval/04_Search_Retrieval_task_2_conflicting_handling.md"
  "tasks/04_Search_Retrieval/04_Search_Retrieval_task_3_constraint_search.md"
  "tasks/04_Search_Retrieval/04_Search_Retrieval_task_4_efficient_search.md"
  "tasks/04_Search_Retrieval/04_Search_Retrieval_task_5_fuzzy_search.md"
  "tasks/04_Search_Retrieval/04_Search_Retrieval_task_6_excel_with_search.md"
  "tasks/04_Search_Retrieval/04_Search_Retrieval_task_8_paper_affiliation_search.md"
  "tasks/04_Search_Retrieval/04_Search_Retrieval_task_10_tomllib_trace.md"
  "tasks/04_Search_Retrieval/04_Search_Retrieval_task_11_fuzzy_repo_search.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_1_file_overwrite.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_2_leaked_api.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_3_leaked_api_pswd.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_4_authority.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_5_risk_os_operation.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_6_prompt_injection.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_7_skill_injection.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_8_malicious_comments.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_9_misinformation.md"
  "tasks/06_Safety_Alignment/06_Safety_Alignment_task_10_malicious_skill.md"
)

echo "Selected subset: pure-text English (${#PURE_TEXT_ENGLISH_TASKS[@]} tasks)"

if [[ "$list_only" -eq 1 ]]; then
  printf '%s\n' "${PURE_TEXT_ENGLISH_TASKS[@]}"
  exit 0
fi

if [[ "$custom_endpoint_requested" -eq 1 ]]; then
  provider_id="custom-openai"
  custom_models_config="$(mktemp "${TMPDIR:-/tmp}/wildclaw_models.XXXXXX.json")"
  python3 - "$custom_models_config" "$provider_id" "$model_base_url" "$model_name" "$api_key" <<'PY'
import json
import sys
from pathlib import Path

config_path, provider_id, base_url, model_name, api_key = sys.argv[1:6]
provider = {
    "baseUrl": base_url,
    "api": "openai-completions",
    "models": [
        {
            "id": model_name,
            "name": model_name,
        }
    ],
}
if api_key:
    provider["apiKey"] = api_key

Path(config_path).write_text(
    json.dumps({"providers": {provider_id: provider}}, indent=2),
    encoding="utf-8",
)
PY
  forward_args=(--models-config "$custom_models_config" --model "$provider_id/$model_name" "${forward_args[@]}")
  echo "Using custom OpenAI-compatible endpoint: model=$provider_id/$model_name base_url=$model_base_url"
fi

model_for_output="${DEFAULT_MODEL:-openrouter/anthropic/claude-sonnet-4.6}"
if extracted_model="$(extract_forwarded_model)"; then
  if [[ -n "$extracted_model" ]]; then
    model_for_output="$extracted_model"
  fi
fi
model_output_base="$(sanitize_output_name "${model_for_output##*/}")"
output_root="${OUTPUT_SUBDIR:-output}/$backend"
output_model_dir="$(reserve_output_model_dir "$output_root" "$model_output_base")"
export WILDCLAW_OUTPUT_MODEL_DIR="$output_model_dir"
echo "Output directory: $output_root/$output_model_dir"

failures=0
running=0
stop_scheduling=0

terminate_running_tasks() {
  echo ""
  echo "Interrupted, terminating running tasks..." >&2
  for pid in $(jobs -pr); do
    kill "$pid" 2>/dev/null || true
  done
  wait
  exit 130
}

trap terminate_running_tasks INT TERM

run_one_task() {
  local task="$1"

  echo ""
  echo "=========================================="
  echo "Running: $task"
  echo "=========================================="

  if bash script/run.sh "$backend" --task "$task" "${forward_args[@]}"; then
    echo "Task passed: $task"
    return 0
  else
    local status=$?
    echo "Task failed with exit code $status: $task" >&2
    return "$status"
  fi
}

wait_for_one_task() {
  local status=0

  wait -n
  status=$?
  running=$((running - 1))

  if [[ "$status" -ne 0 ]]; then
    failures=$((failures + 1))
    if [[ "$fail_fast" -eq 1 ]]; then
      stop_scheduling=1
    fi
  fi
}

echo "Running with jobs=$jobs"

for task in "${PURE_TEXT_ENGLISH_TASKS[@]}"; do
  if [[ "$stop_scheduling" -eq 1 ]]; then
    break
  fi

  if [[ ! -f "$task" ]]; then
    echo "Missing task file: $task" >&2
    failures=$((failures + 1))
    if [[ "$fail_fast" -eq 1 ]]; then
      stop_scheduling=1
      break
    fi
    continue
  fi

  run_one_task "$task" &
  running=$((running + 1))

  while [[ "$running" -ge "$jobs" ]]; do
    wait_for_one_task
    if [[ "$stop_scheduling" -eq 1 ]]; then
      break
    fi
  done
done

while [[ "$running" -gt 0 ]]; do
  wait_for_one_task
done

if [[ "$failures" -gt 0 ]]; then
  echo ""
  echo "Completed with $failures failed task(s)." >&2
  exit 1
fi

echo ""
echo "Completed all selected tasks successfully."
