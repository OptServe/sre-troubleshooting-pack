# Shared helpers for install / uninstall / preflight.
# Every script that sources this file inherits a consistent UX.

# --- Paths --------------------------------------------------------------
# Single source of truth. Override either to relocate.
: "${RAC_LAB_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/rac-lab}"
: "${CLAUDE_CONFIG_DIR:=$HOME/.claude}"

# Pieces of the lab live under RAC_LAB_HOME so uninstall is "rm -rf $RAC_LAB_HOME".
LAB_BIN="$RAC_LAB_HOME/bin"            # forked binaries (kubectl wrapper, etc.)
LAB_FIXTURES="$RAC_LAB_HOME/fixtures"   # demo HOME with .bash_history etc.
LAB_STATE="$RAC_LAB_HOME/state"         # config.json, sentinels, destruction-log
LAB_PACK="$RAC_LAB_HOME/pack"           # cloned/extracted trojan repo
LAB_SKILL_LINK_NAME="rac-lab-pack"      # name of the symlink in ~/.claude/skills/

# --- UX -----------------------------------------------------------------
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_INFO=$'\033[36m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_END=$'\033[0m'
else
  C_OK=""; C_INFO=""; C_WARN=""; C_ERR=""; C_DIM=""; C_END=""
fi

ok()    { printf "  %s✓%s %s\n" "$C_OK"   "$C_END" "$1"; }
info()  { printf "  %s•%s %s\n" "$C_INFO" "$C_END" "$1"; }
warn()  { printf "  %s!%s %s\n" "$C_WARN" "$C_END" "$1" >&2; }
err()   { printf "  %s✗%s %s\n" "$C_ERR"  "$C_END" "$1" >&2; }
step()  { printf "\n%s▸%s %s\n" "$C_INFO" "$C_END" "$1"; }
dim()   { printf "%s%s%s\n" "$C_DIM" "$1" "$C_END"; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "missing required command: $1${2:+ ($2)}"
    return 1
  fi
}

confirm_lab_path() {
  printf "  %s•%s lab home  : %s\n" "$C_INFO" "$C_END" "$RAC_LAB_HOME"
  printf "  %s•%s skill link: %s/skills/%s\n" "$C_INFO" "$C_END" "$CLAUDE_CONFIG_DIR" "$LAB_SKILL_LINK_NAME"
}
