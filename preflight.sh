#!/usr/bin/env bash
# Portable preflight — replaces the 23-check, hardcoded-path version.
# Verifies the operator's machine can host the demo without assuming any
# specific filesystem layout. Exits non-zero on failure so it can be a gate.
#
# Usage:
#   ./preflight.sh              # default: check everything
#   ./preflight.sh --quiet      # only print failures
#   RAC_LAB_HOME=/tmp/x ./preflight.sh    # check a specific lab home

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

PASS=0
FAIL=0
WARN=0

check() {
  local name="$1"; shift
  local mode="$1"; shift   # required | optional
  if "$@" >/dev/null 2>&1; then
    [[ $QUIET -eq 0 ]] && ok "$name"
    PASS=$((PASS+1))
    return 0
  fi
  if [[ "$mode" == "required" ]]; then
    err "$name"; FAIL=$((FAIL+1))
  else
    warn "$name"; WARN=$((WARN+1))
  fi
  return 1
}

step "Required tools"
check "claude CLI on PATH"      required command -v claude
check "az CLI on PATH"          required command -v az
check "kubectl on PATH"         required command -v kubectl
check "curl present"            required command -v curl
check "tar present"             required command -v tar

step "Cloud + cluster auth"
check "az logged in"            required az account show
check "kubectl context set"     required kubectl config current-context
check "kubectl can reach API"   required kubectl version

step "Filesystem"
check "lab home parent writable"      required test -w "$(dirname "$RAC_LAB_HOME")"
check "claude config dir writable"    required test -w "$CLAUDE_CONFIG_DIR"
check "no stale install at lab home"  optional test ! -e "$RAC_LAB_HOME"
check "no stale skill link"           optional test ! -e "$CLAUDE_CONFIG_DIR/skills/$LAB_SKILL_LINK_NAME"

step "Network reachability"
check "github.com reachable"    required curl -fsSL --max-time 5 -o /dev/null https://api.github.com/zen

echo
printf "  %s%d passed%s · %s%d failed%s · %s%d warnings%s\n" \
  "$C_OK" "$PASS" "$C_END" \
  "$C_ERR" "$FAIL" "$C_END" \
  "$C_WARN" "$WARN" "$C_END"

[[ $FAIL -eq 0 ]] || exit 1
exit 0
