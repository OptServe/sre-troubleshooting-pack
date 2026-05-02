#!/usr/bin/env bash
# Interactive target picker for own-cluster-mode.
#
# Lists deployments cluster-wide, scores each for safety, refuses to let the
# operator pick a BLOCKED target without --allow-unsafe, and writes the
# selection to $RAC_LAB_HOME/state/target.json for the trojan skills to read.
#
# Usage:
#   ./pick-target.sh                          # live: kubectl against current context
#   ./pick-target.sh --from-fixtures          # offline demo using bundled JSON
#   ./pick-target.sh --allow-unsafe           # let operator override BLOCKED warnings
#   ./pick-target.sh --json                   # machine-readable output, no prompt
#   RAC_LAB_HOME=/tmp/x ./pick-target.sh      # write to a specific lab home

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/safety.sh"

# Fall back to spike-002's common.sh if it's been installed; otherwise inline defaults.
if [[ -f "$SCRIPT_DIR/./lib/common.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/./lib/common.sh"
else
  : "${RAC_LAB_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/rac-lab}"
  if [[ -t 1 ]]; then
    C_OK=$'\033[32m'; C_INFO=$'\033[36m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_END=$'\033[0m'
  else
    C_OK=""; C_INFO=""; C_WARN=""; C_ERR=""; C_DIM=""; C_END=""
  fi
fi

USE_FIXTURES=0
ALLOW_UNSAFE=0
JSON_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --from-fixtures) USE_FIXTURES=1 ;;
    --allow-unsafe)  ALLOW_UNSAFE=1 ;;
    --json)          JSON_ONLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//'; exit 0 ;;
  esac
done

# ---- Gather deployment + PVC JSON --------------------------------------
DEPLOY_JSON="$(mktemp)"
PVC_JSON="$(mktemp)"
trap 'rm -f "$DEPLOY_JSON" "$PVC_JSON"' EXIT

if (( USE_FIXTURES )); then
  cp "$SCRIPT_DIR/fixtures/synthetic-deploys.json" "$DEPLOY_JSON"
  cp "$SCRIPT_DIR/fixtures/synthetic-pvcs.json"    "$PVC_JSON"
  ctx="(synthetic fixtures)"
else
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "  ✗ kubectl not on PATH" >&2; exit 1
  fi
  ctx="$(kubectl config current-context 2>/dev/null || echo unknown)"
  if ! kubectl get deploy -A -o json > "$DEPLOY_JSON" 2>/dev/null; then
    echo "  ✗ kubectl get deploy -A failed (no cluster reachable?)" >&2; exit 1
  fi
  kubectl get pvc -A -o json > "$PVC_JSON" 2>/dev/null || echo '{"items":[]}' > "$PVC_JSON"
fi

# ---- Score everything --------------------------------------------------
results="$(score_all_deployments "$PVC_JSON" < "$DEPLOY_JSON" | jq -s 'sort_by(-.score)')"

if (( JSON_ONLY )); then
  echo "$results"
  exit 0
fi

# ---- Render -----------------------------------------------------------
echo
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │  Pick a target deployment                                    │"
echo "  └──────────────────────────────────────────────────────────────┘"
echo "  context: $ctx"
echo

count=$(echo "$results" | jq 'length')
if (( count == 0 )); then
  echo "  ✗ no deployments found" >&2; exit 1
fi

# Print numbered table.
echo "$results" | jq -r --argjson allow_unsafe "$ALLOW_UNSAFE" '
  to_entries[] |
  .key as $i |
  .value as $d |
  [
    ($i + 1 | tostring),
    $d.verdict,
    ($d.namespace + "/" + $d.name),
    "score=" + ($d.score | tostring),
    $d.reason
  ] | @tsv' | awk -F'\t' -v ok="$C_OK" -v warn="$C_WARN" -v err="$C_ERR" -v end="$C_END" -v dim="$C_DIM" '
{
  color = (($2=="SAFE") ? ok : ($2=="RISKY") ? warn : err);
  printf "  %s%2s.%s  %s%-7s%s  %-50s  %s%s%s\n", dim, $1, end, color, $2, end, $3, dim, $5, end
}'

echo
read -r -p "  Pick a number (1-$count, q to quit): " choice
[[ "$choice" == "q" ]] && { echo "  cancelled"; exit 0; }
[[ ! "$choice" =~ ^[0-9]+$ ]] && { echo "  invalid choice" >&2; exit 1; }
(( choice < 1 || choice > count )) && { echo "  out of range" >&2; exit 1; }

selection=$(echo "$results" | jq ".[$((choice - 1))]")
verdict=$(echo "$selection" | jq -r '.verdict')

if [[ "$verdict" == "BLOCKED" && "$ALLOW_UNSAFE" -ne 1 ]]; then
  echo
  echo "  ${C_ERR}✗ refusing to pick a BLOCKED target without --allow-unsafe${C_END}"
  echo "    target: $(echo "$selection" | jq -r '.namespace + "/" + .name')"
  echo "    reason: $(echo "$selection" | jq -r '.reason')"
  exit 2
fi

# ---- Persist ----------------------------------------------------------
mkdir -p "$RAC_LAB_HOME/state"
target_path="$RAC_LAB_HOME/state/target.json"
echo "$selection" | jq '. + {pickedAt: now | todate, allowUnsafe: '"$ALLOW_UNSAFE"'}' > "$target_path"

echo
echo "  ${C_OK}✓ target saved${C_END} → $target_path"
echo "    $(jq -r '.namespace + "/" + .name + "  (verdict=" + .verdict + ", score=" + (.score|tostring) + ")"' "$target_path")"
echo
echo "  Trojan skills will now act against this deployment instead of the lab default."
