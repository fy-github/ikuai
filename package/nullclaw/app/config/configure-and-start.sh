#!/bin/sh
set -eu

CONFIG_PATH="${NULLCLAW_CONFIG_PATH:-/nullclaw-data/config.json}"
TMP_PATH="${CONFIG_PATH}.tmp"

json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

is_set() {
  eval "value=\${$1:-}"
  [ -n "$value" ]
}

bool_value() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

json_string_array() {
  raw="${1:-}"
  if [ -z "$raw" ]; then
    printf '[]'
    return
  fi

  old_ifs=$IFS
  IFS=','
  set -f
  first=1
  printf '['
  for item in $raw; do
    trimmed="$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$trimmed" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "$trimmed")"
  done
  printf ']'
  set +f
  IFS=$old_ifs
}

json_nullable_string() {
  raw="${1:-}"
  if [ -z "$raw" ]; then
    printf 'null'
  else
    printf '"%s"' "$(json_escape "$raw")"
  fi
}

write_provider() {
  name="$1"
  api_key="$2"
  base_url="$3"
  api_mode="$4"
  native_tools="$5"
  printf '      "%s": {' "$(json_escape "$name")" >> "$TMP_PATH"
  comma=0
  if [ -n "$api_key" ]; then
    printf '"api_key": "%s"' "$(json_escape "$api_key")" >> "$TMP_PATH"
    comma=1
  fi
  if [ -n "$base_url" ]; then
    [ "$comma" -eq 0 ] || printf ', ' >> "$TMP_PATH"
    printf '"base_url": "%s"' "$(json_escape "$base_url")" >> "$TMP_PATH"
    comma=1
  fi
  if [ -n "$api_mode" ]; then
    [ "$comma" -eq 0 ] || printf ', ' >> "$TMP_PATH"
    printf '"api_mode": "%s"' "$(json_escape "$api_mode")" >> "$TMP_PATH"
    comma=1
  fi
  if [ -n "$native_tools" ]; then
    [ "$comma" -eq 0 ] || printf ', ' >> "$TMP_PATH"
    printf '"native_tools": %s' "$(bool_value "$native_tools")" >> "$TMP_PATH"
  fi
  printf '}'
}

provider="${NULLCLAW_PROVIDER:-openrouter}"
model="${NULLCLAW_MODEL:-openrouter/anthropic/claude-sonnet-4}"
provider_api_key="${NULLCLAW_PROVIDER_API_KEY:-${OPENROUTER_API_KEY:-}}"
provider_base_url="${NULLCLAW_PROVIDER_BASE_URL:-}"
provider_api_mode="${NULLCLAW_PROVIDER_API_MODE:-chat_completions}"
provider_native_tools="${NULLCLAW_PROVIDER_NATIVE_TOOLS:-true}"

rewrite_trusted_private_base_url() {
  raw_url="${1:-}"
  [ -n "$raw_url" ] || return 1

  host="$(printf '%s' "$raw_url" | sed -n 's#^https\{0,1\}://\([^/:?]*\).*#\1#p')"
  path_and_more="$(printf '%s' "$raw_url" | sed -n 's#^https\{0,1\}://[^/]*##p')"
  [ -n "$host" ] || return 1

  case "$host" in
    localhost|127.*|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
      printf '%s' "$raw_url"
      return 0
      ;;
  esac

  resolved_ip="$(getent hosts "$host" 2>/dev/null | awk 'NR==1 {print $1}')"
  if [ -z "$resolved_ip" ]; then
    resolved_ip="$(nslookup "$host" 2>/dev/null | awk '/^Address[ :]+/ {print $NF}' | tail -n 1)"
  fi
  case "$resolved_ip" in
    10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
      proxy_ip="$(getent hosts model-proxy 2>/dev/null | awk 'NR==1 {print $1}')"
      if [ -z "$proxy_ip" ]; then
        proxy_ip="$(nslookup model-proxy 2>/dev/null | awk '/^Address[ :]+/ {print $NF}' | tail -n 1)"
      fi
      case "$proxy_ip" in
        10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
          printf 'http://%s:8081' "$proxy_ip"
          return 0
          ;;
      esac
      return 1
      ;;
  esac
  return 1
}

if rewritten_base_url="$(rewrite_trusted_private_base_url "$provider_base_url")"; then
  provider_base_url="$rewritten_base_url"
fi

mkdir -p "$(dirname "$CONFIG_PATH")" /nullclaw-data/workspace

cat > "$TMP_PATH" <<EOF
{
  "default_temperature": ${NULLCLAW_TEMPERATURE:-0.7},
  "agents": {
    "defaults": {
      "provider": "$(json_escape "$provider")",
      "model": {
        "primary": "$(json_escape "$model")"
      }
    }
  },
  "models": {
    "providers": {
EOF

write_provider "$provider" "$provider_api_key" "$provider_base_url" "$provider_api_mode" "$provider_native_tools" >> "$TMP_PATH"
if [ "$provider" != "openrouter" ] && [ -n "${OPENROUTER_API_KEY:-}" ]; then
  printf ',\n' >> "$TMP_PATH"
  write_provider "openrouter" "$OPENROUTER_API_KEY" "" "chat_completions" "true" >> "$TMP_PATH"
fi
if [ "$provider" != "openai" ] && [ -n "${OPENAI_API_KEY:-}" ]; then
  printf ',\n' >> "$TMP_PATH"
  write_provider "openai" "$OPENAI_API_KEY" "${OPENAI_BASE_URL:-}" "chat_completions" "true" >> "$TMP_PATH"
fi
if [ "$provider" != "azure" ] && [ -n "${AZURE_OPENAI_API_KEY:-}" ]; then
  printf ',\n' >> "$TMP_PATH"
  write_provider "azure" "$AZURE_OPENAI_API_KEY" "${AZURE_OPENAI_BASE_URL:-}" "chat_completions" "true" >> "$TMP_PATH"
fi

cat >> "$TMP_PATH" <<EOF
    }
  },
  "gateway": {
    "port": 3000,
    "host": "::",
    "allow_public_bind": true,
    "require_pairing": $(bool_value "${NULLCLAW_GATEWAY_REQUIRE_PAIRING:-false}"),
    "paired_tokens": $(json_string_array "${NULLCLAW_GATEWAY_TOKENS:-}"),
    "max_body_size_bytes": ${NULLCLAW_GATEWAY_MAX_BODY_SIZE_BYTES:-1048576},
    "request_timeout_secs": ${NULLCLAW_GATEWAY_REQUEST_TIMEOUT_SECS:-60}
  },
  "webhook": {
    "port": 3000,
    "secret": "$(json_escape "${NULLCLAW_WEBHOOK_SECRET:-}")"
  },
  "cron": {
    "enabled": $(bool_value "${NULLCLAW_CRON_ENABLED:-false}"),
    "interval_minutes": ${NULLCLAW_CRON_INTERVAL_MINUTES:-30},
    "max_run_history": ${NULLCLAW_CRON_MAX_RUN_HISTORY:-50}
  },
  "a2a": {
    "enabled": $(bool_value "${NULLCLAW_A2A_ENABLED:-false}"),
    "name": "$(json_escape "${NULLCLAW_A2A_NAME:-NullClaw}")",
    "description": "$(json_escape "${NULLCLAW_A2A_DESCRIPTION:-AI assistant}")",
    "url": "$(json_escape "${NULLCLAW_A2A_URL:-}")",
    "version": "$(json_escape "${NULLCLAW_A2A_VERSION:-1.0.0}")"
  },
  "channels": {
    "cli": true
EOF

if is_set NULLCLAW_TELEGRAM_BOT_TOKEN; then
cat >> "$TMP_PATH" <<EOF
    ,
    "telegram": {
      "accounts": {
        "default": {
          "bot_token": "$(json_escape "${NULLCLAW_TELEGRAM_BOT_TOKEN}")",
          "allow_from": $(json_string_array "${NULLCLAW_TELEGRAM_ALLOW_FROM:-}"),
          "group_allow_from": $(json_string_array "${NULLCLAW_TELEGRAM_GROUP_ALLOW_FROM:-}"),
          "group_policy": "$(json_escape "${NULLCLAW_TELEGRAM_GROUP_POLICY:-allowlist}")",
          "proxy": "$(json_escape "${NULLCLAW_TELEGRAM_PROXY:-}")",
          "require_mention": $(bool_value "${NULLCLAW_TELEGRAM_REQUIRE_MENTION:-false}"),
          "streaming": $(bool_value "${NULLCLAW_TELEGRAM_STREAMING:-true}"),
          "draft_previews": $(bool_value "${NULLCLAW_TELEGRAM_DRAFT_PREVIEWS:-false}")
        }
      }
    }
EOF
fi

if is_set NULLCLAW_WHATSAPP_ACCESS_TOKEN; then
cat >> "$TMP_PATH" <<EOF
    ,
    "whatsapp": {
      "accounts": {
        "default": {
          "access_token": "$(json_escape "${NULLCLAW_WHATSAPP_ACCESS_TOKEN}")",
          "phone_number_id": "$(json_escape "${NULLCLAW_WHATSAPP_PHONE_NUMBER_ID:-}")",
          "verify_token": "$(json_escape "${NULLCLAW_WHATSAPP_VERIFY_TOKEN:-}")",
          "app_secret": "$(json_escape "${NULLCLAW_WHATSAPP_APP_SECRET:-}")",
          "allow_from": $(json_string_array "${NULLCLAW_WHATSAPP_ALLOW_FROM:-}"),
          "group_allow_from": $(json_string_array "${NULLCLAW_WHATSAPP_GROUP_ALLOW_FROM:-}"),
          "group_policy": "$(json_escape "${NULLCLAW_WHATSAPP_GROUP_POLICY:-allowlist}")"
        }
      }
    }
EOF
fi

if is_set NULLCLAW_WHATSAPP_WEB_BRIDGE_URL; then
cat >> "$TMP_PATH" <<EOF
    ,
    "external": {
      "accounts": {
        "whatsapp-web": {
          "runtime_name": "whatsapp_web",
          "transport": {
            "command": "$(json_escape "${NULLCLAW_WHATSAPP_WEB_COMMAND:-nullclaw-plugin-whatsapp-web}")",
            "args": ["--stdio"],
            "timeout_ms": ${NULLCLAW_WHATSAPP_WEB_TIMEOUT_MS:-10000},
            "env": {
              "PLUGIN_TOKEN": "$(json_escape "${NULLCLAW_WHATSAPP_WEB_PLUGIN_TOKEN:-}")"
            }
          },
          "config": {
            "bridge_url": "$(json_escape "${NULLCLAW_WHATSAPP_WEB_BRIDGE_URL}")",
            "allow_from": $(json_string_array "${NULLCLAW_WHATSAPP_WEB_ALLOW_FROM:-*}")
          }
        }
      }
    }
EOF
fi

if is_set NULLCLAW_SLACK_BOT_TOKEN; then
cat >> "$TMP_PATH" <<EOF
    ,
    "slack": {
      "accounts": {
        "default": {
          "mode": "$(json_escape "${NULLCLAW_SLACK_MODE:-http}")",
          "bot_token": "$(json_escape "${NULLCLAW_SLACK_BOT_TOKEN}")",
          "app_token": "$(json_escape "${NULLCLAW_SLACK_APP_TOKEN:-}")",
          "signing_secret": "$(json_escape "${NULLCLAW_SLACK_SIGNING_SECRET:-}")",
          "webhook_path": "$(json_escape "${NULLCLAW_SLACK_WEBHOOK_PATH:-/slack/events}")",
          "channel_id": "$(json_escape "${NULLCLAW_SLACK_CHANNEL_ID:-}")",
          "allow_from": $(json_string_array "${NULLCLAW_SLACK_ALLOW_FROM:-}"),
          "dm_policy": "$(json_escape "${NULLCLAW_SLACK_DM_POLICY:-pairing}")",
          "group_policy": "$(json_escape "${NULLCLAW_SLACK_GROUP_POLICY:-mention_only}")"
        }
      }
    }
EOF
fi

if is_set NULLCLAW_LARK_APP_ID; then
cat >> "$TMP_PATH" <<EOF
    ,
    "lark": {
      "accounts": {
        "default": {
          "app_id": "$(json_escape "${NULLCLAW_LARK_APP_ID}")",
          "app_secret": "$(json_escape "${NULLCLAW_LARK_APP_SECRET:-}")",
          "encrypt_key": "$(json_escape "${NULLCLAW_LARK_ENCRYPT_KEY:-}")",
          "verification_token": "$(json_escape "${NULLCLAW_LARK_VERIFICATION_TOKEN:-}")",
          "use_feishu": $(bool_value "${NULLCLAW_LARK_USE_FEISHU:-false}"),
          "receive_mode": "$(json_escape "${NULLCLAW_LARK_RECEIVE_MODE:-webhook}")",
          "allow_from": $(json_string_array "${NULLCLAW_LARK_ALLOW_FROM:-}")
        }
      }
    }
EOF
fi

if is_set NULLCLAW_WECHAT_CALLBACK_TOKEN; then
cat >> "$TMP_PATH" <<EOF
    ,
    "wechat": {
      "accounts": {
        "default": {
          "callback_token": "$(json_escape "${NULLCLAW_WECHAT_CALLBACK_TOKEN}")",
          "encoding_aes_key": "$(json_escape "${NULLCLAW_WECHAT_ENCODING_AES_KEY:-}")",
          "app_id": "$(json_escape "${NULLCLAW_WECHAT_APP_ID:-}")",
          "app_secret": "$(json_escape "${NULLCLAW_WECHAT_APP_SECRET:-}")",
          "allow_from": $(json_string_array "${NULLCLAW_WECHAT_ALLOW_FROM:-}")
        }
      }
    }
EOF
fi

if is_set NULLCLAW_WECOM_WEBHOOK_URL; then
cat >> "$TMP_PATH" <<EOF
    ,
    "wecom": {
      "accounts": {
        "default": {
          "webhook_url": "$(json_escape "${NULLCLAW_WECOM_WEBHOOK_URL}")",
          "callback_token": "$(json_escape "${NULLCLAW_WECOM_CALLBACK_TOKEN:-}")",
          "encoding_aes_key": "$(json_escape "${NULLCLAW_WECOM_ENCODING_AES_KEY:-}")",
          "corp_id": "$(json_escape "${NULLCLAW_WECOM_CORP_ID:-}")",
          "allow_from": $(json_string_array "${NULLCLAW_WECOM_ALLOW_FROM:-}")
        }
      }
    }
EOF
fi

if is_set NULLCLAW_LINE_ACCESS_TOKEN; then
cat >> "$TMP_PATH" <<EOF
    ,
    "line": {
      "accounts": {
        "default": {
          "access_token": "$(json_escape "${NULLCLAW_LINE_ACCESS_TOKEN}")",
          "channel_secret": "$(json_escape "${NULLCLAW_LINE_CHANNEL_SECRET:-}")",
          "port": 3000,
          "allow_from": $(json_string_array "${NULLCLAW_LINE_ALLOW_FROM:-}")
        }
      }
    }
EOF
fi

if is_set NULLCLAW_QQ_BOT_TOKEN; then
cat >> "$TMP_PATH" <<EOF
    ,
    "qq": {
      "accounts": {
        "default": {
          "app_id": "$(json_escape "${NULLCLAW_QQ_APP_ID:-}")",
          "app_secret": "$(json_escape "${NULLCLAW_QQ_APP_SECRET:-}")",
          "bot_token": "$(json_escape "${NULLCLAW_QQ_BOT_TOKEN}")",
          "sandbox": $(bool_value "${NULLCLAW_QQ_SANDBOX:-false}"),
          "receive_mode": "$(json_escape "${NULLCLAW_QQ_RECEIVE_MODE:-webhook}")",
          "group_policy": "$(json_escape "${NULLCLAW_QQ_GROUP_POLICY:-allow}")",
          "allowed_groups": $(json_string_array "${NULLCLAW_QQ_ALLOWED_GROUPS:-}"),
          "allow_from": $(json_string_array "${NULLCLAW_QQ_ALLOW_FROM:-}")
        }
      }
    }
EOF
fi

if is_set NULLCLAW_TEAMS_CLIENT_ID; then
cat >> "$TMP_PATH" <<EOF
    ,
    "teams": {
      "accounts": {
        "default": {
          "client_id": "$(json_escape "${NULLCLAW_TEAMS_CLIENT_ID}")",
          "client_secret": "$(json_escape "${NULLCLAW_TEAMS_CLIENT_SECRET:-}")",
          "tenant_id": "$(json_escape "${NULLCLAW_TEAMS_TENANT_ID:-}")",
          "webhook_secret": "$(json_escape "${NULLCLAW_TEAMS_WEBHOOK_SECRET:-}")",
          "notification_channel_id": "$(json_escape "${NULLCLAW_TEAMS_NOTIFICATION_CHANNEL_ID:-}")",
          "bot_id": "$(json_escape "${NULLCLAW_TEAMS_BOT_ID:-}")"
        }
      }
    }
EOF
fi

if is_set NULLCLAW_WEB_AUTH_TOKEN; then
cat >> "$TMP_PATH" <<EOF
    ,
    "web": {
      "accounts": {
        "default": {
          "transport": "$(json_escape "${NULLCLAW_WEB_TRANSPORT:-local}")",
          "port": ${NULLCLAW_WEB_PORT:-32123},
          "listen": "$(json_escape "${NULLCLAW_WEB_LISTEN:-0.0.0.0}")",
          "path": "$(json_escape "${NULLCLAW_WEB_PATH:-/ws}")",
          "auth_token": "$(json_escape "${NULLCLAW_WEB_AUTH_TOKEN}")",
          "message_auth_mode": "$(json_escape "${NULLCLAW_WEB_MESSAGE_AUTH_MODE:-token}")",
          "allowed_origins": $(json_string_array "${NULLCLAW_WEB_ALLOWED_ORIGINS:-*}")
EOF
if [ -n "${NULLCLAW_WEB_RELAY_URL:-}" ]; then
cat >> "$TMP_PATH" <<EOF
          ,
          "relay_url": "$(json_escape "${NULLCLAW_WEB_RELAY_URL}")",
          "relay_agent_id": "$(json_escape "${NULLCLAW_WEB_RELAY_AGENT_ID:-default}")"
EOF
fi
if [ -n "${NULLCLAW_WEB_RELAY_TOKEN:-}" ]; then
cat >> "$TMP_PATH" <<EOF
          ,
          "relay_token": "$(json_escape "${NULLCLAW_WEB_RELAY_TOKEN}")"
EOF
fi
cat >> "$TMP_PATH" <<EOF
        }
      }
    }
EOF
fi

cat >> "$TMP_PATH" <<EOF
  },
  "http_request": {
    "enabled": $(bool_value "${NULLCLAW_HTTP_REQUEST_ENABLED:-false}"),
    "search_base_url": $(json_nullable_string "${NULLCLAW_SEARCH_BASE_URL:-}"),
    "search_provider": "$(json_escape "${NULLCLAW_SEARCH_PROVIDER:-auto}")",
    "allowed_domains": $(json_string_array "${NULLCLAW_HTTP_ALLOWED_DOMAINS:-}")
  },
  "memory": {
    "profile": "$(json_escape "${NULLCLAW_MEMORY_PROFILE:-markdown_only}")",
    "backend": "$(json_escape "${NULLCLAW_MEMORY_BACKEND:-markdown}")",
    "auto_save": $(bool_value "${NULLCLAW_MEMORY_AUTO_SAVE:-true}")
  }
}
EOF

mv "$TMP_PATH" "$CONFIG_PATH"
if [ "${NULLCLAW_CONFIG_ONLY:-false}" = "true" ]; then
  exit 0
fi
cp /usr/local/bin/chat-bridge.sh /tmp/nullclaw-chat-bridge.sh
chmod +x /tmp/nullclaw-chat-bridge.sh
nohup /usr/bin/nc -lk -p 32124 -e /tmp/nullclaw-chat-bridge.sh >/tmp/nullclaw-chat-bridge.log 2>&1 &
exec nullclaw gateway --port 3000 --host ::
