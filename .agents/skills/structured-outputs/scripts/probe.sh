#!/usr/bin/env bash
# Probe structured outputs on an OpenAI-compatible endpoint (bash 3.2+, curl, jq).
# Usage: probe.sh BASE_URL MODEL [shape]
#   BASE_URL  e.g. http://127.0.0.1:8000/v1
#   shape     response_format (default) | vllm | sglang-regex | ollama-native
# Auth: LLM_API_KEY_FILE (path to a 0600 file) or LLM_API_KEY; the key is never printed.
# Output: HTTP status, finish_reason, whether content parses as JSON and has the required keys.
set -euo pipefail

base="${1:?usage: probe.sh BASE_URL MODEL [shape]}"
model="${2:?usage: probe.sh BASE_URL MODEL [shape]}"
shape="${3:-response_format}"
base="${base%/}"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

key=""
if [ -n "${LLM_API_KEY_FILE:-}" ]; then
  [ -r "$LLM_API_KEY_FILE" ] || { echo "cannot read LLM_API_KEY_FILE" >&2; exit 2; }
  key="$(tr -d '\r\n' <"$LLM_API_KEY_FILE")"
elif [ -n "${LLM_API_KEY:-}" ]; then
  key="$LLM_API_KEY"
fi

schema='{"type":"object","properties":{"name":{"type":"string"},"population":{"type":"integer"}},"required":["name","population"],"additionalProperties":false}'
prompt='Give the capital of France and its population as JSON with keys name and population.'
url="$base/chat/completions"

case "$shape" in
  response_format)
    body="$(jq -n --arg m "$model" --arg p "$prompt" --argjson s "$schema" \
      '{model:$m,temperature:0,max_tokens:512,messages:[{role:"user",content:$p}],response_format:{type:"json_schema",json_schema:{name:"capital",schema:$s}}}')" ;;
  vllm)
    body="$(jq -n --arg m "$model" --arg p "$prompt" --argjson s "$schema" \
      '{model:$m,temperature:0,max_tokens:512,messages:[{role:"user",content:$p}],structured_outputs:{json:$s}}')" ;;
  sglang-regex)
    body="$(jq -n --arg m "$model" \
      '{model:$m,temperature:0,max_tokens:16,messages:[{role:"user",content:"What is the capital of France?"}],regex:"(Paris|London)"}')" ;;
  ollama-native)
    url="${base%/v1}/api/chat"
    body="$(jq -n --arg m "$model" --arg p "$prompt" --argjson s "$schema" \
      '{model:$m,stream:false,options:{temperature:0},messages:[{role:"user",content:$p}],format:$s}')" ;;
  *) echo "unknown shape: $shape" >&2; exit 2 ;;
esac

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
args=(-sS -o "$tmp" -w '%{http_code}' -H 'Content-Type: application/json' -d "$body")
[ -n "$key" ] && args+=(-H "Authorization: Bearer $key")
code="$(curl "${args[@]}" "$url")" || { echo "request failed"; exit 1; }

echo "http_status: $code"
if [ "$code" != "200" ]; then
  jq -r '.error.message? // .error? // .' "$tmp" 2>/dev/null | head -c 600
  echo
  exit 1
fi

content="$(jq -r '.choices[0].message.content? // .message.content? // empty' "$tmp")"
echo "finish_reason: $(jq -r '.choices[0].finish_reason? // .done_reason? // "n/a"' "$tmp")"
echo "content: $content"
if [ "$shape" = "sglang-regex" ]; then
  printf '%s' "$content" | grep -Eq '^(Paris|London)$' && echo "regex_match: yes" || echo "regex_match: NO"
else
  if printf '%s' "$content" | jq -e 'has("name") and has("population") and (.population|type=="number")' >/dev/null 2>&1; then
    echo "valid_json_with_required_keys: yes"
  else
    echo "valid_json_with_required_keys: NO"
    exit 1
  fi
fi
