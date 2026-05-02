# Safety scoring for own-cluster-mode target selection.
#
# Inputs come from `kubectl get deploy -A -o json` plus a sidecar PVC list.
# Output is a per-deployment score 0..100 + a verdict (SAFE / RISKY / BLOCKED)
# and a human-readable reason string.
#
# The scoring rules below are intentionally explicit and mockable so that
# `test/test-safety-scoring.sh` can run them without a live cluster.

# Namespaces we never touch — these are infra the cluster depends on.
SAFETY_BLOCKED_NAMESPACES=(
  kube-system kube-public kube-node-lease
  ingress-nginx ingress
  cert-manager
  gatekeeper-system
  azure-arc azure-extensions-usage-system
  cilium-system
  monitoring observability prometheus
)

is_blocked_ns() {
  local ns="$1"
  for blocked in "${SAFETY_BLOCKED_NAMESPACES[@]}"; do
    [[ "$ns" == "$blocked" ]] && return 0
  done
  return 1
}

# Score a single deployment described by a small JSON blob:
#   {"namespace":"x","name":"y","replicas":N,"hasPVC":true|false,"readyMinutes":N,"safeOptIn":true|false}
#
# Outputs to stdout: "<score> <verdict> <reason>"
score_deployment() {
  local json="$1"
  local ns name replicas has_pvc ready_min safe_opt
  ns=$(printf '%s' "$json"        | jq -r '.namespace')
  name=$(printf '%s' "$json"      | jq -r '.name')
  replicas=$(printf '%s' "$json"  | jq -r '.replicas // 0')
  has_pvc=$(printf '%s' "$json"   | jq -r '.hasPVC // false')
  ready_min=$(printf '%s' "$json" | jq -r '.readyMinutes // 0')
  safe_opt=$(printf '%s' "$json"  | jq -r '.safeOptIn // false')

  if is_blocked_ns "$ns"; then
    echo "0 BLOCKED ns=$ns is in the always-blocked list (cluster infra)"
    return
  fi

  if [[ "$safe_opt" == "true" ]]; then
    echo "100 SAFE annotated rac-lab/safe-target=true (operator opt-in)"
    return
  fi

  local score=50 reasons=()
  if (( replicas >= 2 )); then score=$((score + 25)); reasons+=("replicas=$replicas");
  else                          score=$((score - 15)); reasons+=("single-replica"); fi

  if [[ "$has_pvc" == "true" ]]; then score=$((score - 30)); reasons+=("has-PVC");
  else                                 score=$((score + 15)); reasons+=("stateless"); fi

  if (( ready_min >= 5 )); then score=$((score + 10)); reasons+=("ready-${ready_min}m");
  else                          score=$((score - 10)); reasons+=("recently-changed"); fi

  # Clamp.
  (( score < 0 )) && score=0
  (( score > 100 )) && score=100

  local verdict
  if   (( score >= 70 )); then verdict=SAFE
  elif (( score >= 40 )); then verdict=RISKY
  else                         verdict=BLOCKED
  fi

  local IFS=,; echo "$score $verdict ${reasons[*]}"
}

# Score every deployment in a kubectl JSON dump.
# stdin: kubectl get deploy -A -o json
# stdout: NDJSON, one row per deployment with score + verdict + reason
score_all_deployments() {
  local pvc_json="${1:-}"  # optional: kubectl get pvc -A -o json output

  local pvc_keys=""
  if [[ -n "$pvc_json" && -f "$pvc_json" ]]; then
    # Build a "ns/deploy-or-stateful-name" lookup of PVC ownership
    pvc_keys=$(jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' "$pvc_json" 2>/dev/null | sort -u)
  fi

  jq -r '.items[] | {
    namespace: .metadata.namespace,
    name: .metadata.name,
    replicas: (.spec.replicas // 0),
    readyMinutes: 999,
    safeOptIn: ((.metadata.annotations // {}) | (.["rac-lab/safe-target"] == "true"))
  } | @json' | while read -r row; do
    ns=$(printf '%s' "$row" | jq -r '.namespace')
    # Heuristic: any PVC in this namespace flips has-PVC. Imperfect but cheap and conservative.
    has_pvc=false
    if [[ -n "$pvc_keys" ]] && grep -q "^$ns/" <<< "$pvc_keys"; then
      has_pvc=true
    fi
    enriched=$(printf '%s' "$row" | jq --arg has "$has_pvc" '. + {hasPVC: ($has == "true")}')
    score_line=$(score_deployment "$enriched")
    score=${score_line%% *}; rest=${score_line#* }; verdict=${rest%% *}; reason=${rest#* }
    jq -n \
      --arg ns "$(printf '%s' "$enriched" | jq -r '.namespace')" \
      --arg name "$(printf '%s' "$enriched" | jq -r '.name')" \
      --argjson replicas "$(printf '%s' "$enriched" | jq -r '.replicas')" \
      --argjson hasPVC "$(printf '%s' "$enriched" | jq -r '.hasPVC')" \
      --argjson score "$score" \
      --arg verdict "$verdict" \
      --arg reason "$reason" \
      '{namespace:$ns, name:$name, replicas:$replicas, hasPVC:$hasPVC, score:$score, verdict:$verdict, reason:$reason}'
  done
}
