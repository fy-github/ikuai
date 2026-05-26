#!/bin/sh
set -eu

json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/'"$(printf '\r')"'/\\r/g; s/'"$(printf '\n')"'/\\n/g'
}

send_json() {
  status="$1"
  body="$2"
  printf 'HTTP/1.1 %s\r\n' "$status"
  printf 'Content-Type: application/json; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf 'Connection: close\r\n'
  printf 'Content-Length: %s\r\n' "$(printf '%s' "$body" | wc -c | tr -d ' ')"
  printf '\r\n'
  printf '%s' "$body"
}

send_text() {
  status="$1"
  body="$2"
  printf 'HTTP/1.1 %s\r\n' "$status"
  printf 'Content-Type: text/plain; charset=utf-8\r\n'
  printf 'Cache-Control: no-store\r\n'
  printf 'Connection: close\r\n'
  printf 'Content-Length: %s\r\n' "$(printf '%s' "$body" | wc -c | tr -d ' ')"
  printf '\r\n'
  printf '%s' "$body"
}

trim_cr() {
  printf '%s' "$1" | sed 's/\r$//'
}

request_line=""
IFS= read -r request_line || true
request_line="$(trim_cr "$request_line")"
method="$(printf '%s' "$request_line" | awk '{print $1}')"
path="$(printf '%s' "$request_line" | awk '{print $2}')"

content_length=0
chat_token=""
sender_id="lan-user"
session_id="lan-chat"

while IFS= read -r line; do
  line="$(trim_cr "$line")"
  [ -n "$line" ] || break
  header_name="$(printf '%s' "$line" | awk -F':' '{print $1}' | tr '[:upper:]' '[:lower:]')"
  header_value="$(printf '%s' "$line" | sed 's/^[^:]*:[[:space:]]*//')"
  case "$header_name" in
    content-length) content_length="$header_value" ;;
    x-chat-token) chat_token="$header_value" ;;
    x-sender-id) sender_id="$header_value" ;;
    x-session-id) session_id="$header_value" ;;
  esac
done

if [ "$method" = "GET" ] && [ "$path" = "/health" ]; then
  send_json "200 OK" '{"status":"ok"}'
  exit 0
fi

if [ "$method" != "POST" ] || [ "$path" != "/chat" ]; then
  send_json "404 Not Found" '{"error":"not found"}'
  exit 0
fi

expected_token="${NULLCLAW_GATEWAY_TOKENS%%,*}"
if [ -z "$expected_token" ] || [ "$chat_token" != "$expected_token" ]; then
  send_json "401 Unauthorized" '{"error":"unauthorized"}'
  exit 0
fi

if [ "$content_length" -le 0 ] 2>/dev/null; then
  send_json "400 Bad Request" '{"error":"empty body"}'
  exit 0
fi

body_file="$(mktemp)"
stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "$body_file" "$stdout_file" "$stderr_file"' EXIT

dd bs=1 count="$content_length" of="$body_file" 2>/dev/null
message="$(cat "$body_file")"

if [ -z "$(printf '%s' "$message" | tr -d '[:space:]')" ]; then
  send_json "400 Bad Request" '{"error":"empty message"}'
  exit 0
fi

NULLCLAW_CONFIG_PATH=/nullclaw-data/config.json \
  nullclaw agent -m "$message" >"$stdout_file" 2>"$stderr_file" || true

stdout_text="$(cat "$stdout_file")"
stderr_text="$(cat "$stderr_file")"

if [ -z "$stdout_text" ]; then
  send_json "500 Internal Server Error" "$(printf '{"error":"agent_run_failed","details":"%s"}' "$(json_escape "$stderr_text")")"
  exit 0
fi

send_text "200 OK" "$stdout_text"
