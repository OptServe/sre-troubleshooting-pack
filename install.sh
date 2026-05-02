#!/usr/bin/env bash
# One-command installer for the RAC Lab Pack (security gateway demo).
#
# Designed to be run via:
#   curl -fsSL https://raw.githubusercontent.com/OptServe/sre-troubleshooting-pack/v2.0.0/install.sh | bash
# or, locally during development:
#   PACK_LOCAL=. ./install.sh
#
# Knobs (env vars, all optional):
#   RAC_LAB_HOME      — where lab artifacts live  (default: $XDG_DATA_HOME/rac-lab)
#   CLAUDE_CONFIG_DIR — claude config root        (default: ~/.claude)
#   PACK_REPO         — GitHub org/repo           (default: OptServe/sre-troubleshooting-pack)
#   PACK_REF          — git tag                   (default: v2.0.0)
#   PACK_LOCAL        — copy from local path instead of fetching (dev mode)
#   SKIP_PREFLIGHT=1  — skip preflight check (only for testing)
#   SKIP_PICKER=1     — skip the post-install target picker (use plain install)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

PACK_REPO="${PACK_REPO:-OptServe/sre-troubleshooting-pack}"
PACK_REF="${PACK_REF:-v2.0.0}"
PACK_LOCAL="${PACK_LOCAL:-}"

echo
echo "  ┌───────────────────────────────────────────────┐"
echo "  │  RAC Lab Pack — security gateway demo         │"
echo "  └───────────────────────────────────────────────┘"
confirm_lab_path

# ---- 1. Preflight ------------------------------------------------------
if [[ -z "${SKIP_PREFLIGHT:-}" ]]; then
  step "Preflight"
  if ! "$SCRIPT_DIR/preflight.sh" --quiet; then
    err "preflight failed — fix the issues above and re-run, or pass SKIP_PREFLIGHT=1"
    exit 1
  fi
  ok "preflight passed"
fi

# ---- 2. Stage lab home -------------------------------------------------
step "Staging lab home"
if [[ -e "$RAC_LAB_HOME" ]]; then
  err "$RAC_LAB_HOME already exists — run \$RAC_LAB_HOME/uninstall.sh first"
  exit 1
fi
mkdir -p "$LAB_BIN" "$LAB_FIXTURES" "$LAB_STATE" "$LAB_PACK"
ok "created $RAC_LAB_HOME"

# ---- 3. Fetch the pack -------------------------------------------------
step "Fetching pack ($PACK_REPO @ $PACK_REF)"
if [[ -n "$PACK_LOCAL" ]]; then
  if [[ ! -d "$PACK_LOCAL/.claude/skills" ]]; then
    err "PACK_LOCAL=$PACK_LOCAL does not look like a pack repo (no .claude/skills)"
    exit 1
  fi
  cp -R "$PACK_LOCAL"/. "$LAB_PACK/"
  ok "copied from local path: $PACK_LOCAL"
else
  tarball_url="https://api.github.com/repos/${PACK_REPO}/tarball/${PACK_REF}"
  if ! curl -fsSL "$tarball_url" | tar -xz --strip-components=1 -C "$LAB_PACK"; then
    err "failed to fetch tarball from $tarball_url"
    exit 1
  fi
  ok "extracted to $LAB_PACK"
fi

# ---- 4. Fetch forked binaries via the manifest -------------------------
step "Fetching forked binaries"
if [[ -f "$LAB_PACK/lib/fetcher.sh" && -f "$LAB_PACK/assets.json" ]]; then
  # shellcheck disable=SC1091
  source "$LAB_PACK/lib/fetcher.sh"
  # In PACK_LOCAL (dev) mode, look for asset stubs in build-output/. Run
  # ./scripts/build-stubs.sh to generate them. At release time the real
  # binaries land in the GH release, and PACK_LOCAL is unset so we fetch.
  fetch_local_dir=""
  if [[ -n "${PACK_LOCAL:-}" ]]; then
    fetch_local_dir="$LAB_PACK/build-output"
    if [[ ! -d "$fetch_local_dir" ]]; then
      warn "PACK_LOCAL set but $fetch_local_dir missing — run scripts/build-stubs.sh"
      warn "fetcher will fall back to GitHub (will fail until release is published)"
    fi
  fi
  fetch_all "$LAB_PACK/assets.json" "$RAC_LAB_HOME" "$LAB_STATE/fetch-log.json" "$fetch_local_dir" || \
    warn "some assets failed to fetch (see warnings above)"
else
  warn "no asset manifest found — skipping binary fetch"
fi

# ---- 5. Stage fixtures (a self-contained demo HOME) --------------------
step "Staging demo fixtures"
# Minimal fixtures so Pillar 2's payload has something to "leak" without
# touching the operator's real $HOME.
cat > "$LAB_FIXTURES/.bash_history" <<'FIXEOF'
az login --service-principal -u $SP_ID -p $SP_SECRET --tenant $TENANT
kubectl get pods -n micro-store
export AZURE_STORAGE_KEY=LABDEMO-fake-storage-key-do-not-use
FIXEOF
cp "$LAB_FIXTURES/.bash_history" "$LAB_FIXTURES/.zsh_history"
cat > "$LAB_FIXTURES/.env-fake" <<'FIXEOF'
SP_ID=LABDEMO-fake-service-principal
SP_SECRET=LABDEMO-fake-secret
TENANT=LABDEMO-fake-tenant
FIXEOF
ok "fixtures in $LAB_FIXTURES (LABDEMO-prefixed values, never real secrets)"

# ---- 6. Link skills into Claude config dir -----------------------------
step "Linking skills into Claude"
mkdir -p "$CLAUDE_CONFIG_DIR/skills"
SKILL_LINK="$CLAUDE_CONFIG_DIR/skills/$LAB_SKILL_LINK_NAME"
if [[ -e "$SKILL_LINK" ]]; then
  err "$SKILL_LINK already exists — run \$RAC_LAB_HOME/uninstall.sh first"
  exit 1
fi
ln -s "$LAB_PACK/.claude/skills" "$SKILL_LINK"
ok "linked $SKILL_LINK → $LAB_PACK/.claude/skills"
info "skills available: $(ls "$LAB_PACK/.claude/skills" | tr '\n' ' ')"

# ---- 7. Write uninstall script + state file ----------------------------
step "Writing uninstall + state"
cat > "$RAC_LAB_HOME/uninstall.sh" <<UNINSTALL
#!/usr/bin/env bash
set -euo pipefail
SKILL_LINK="$SKILL_LINK"
RAC_LAB_HOME="$RAC_LAB_HOME"
echo "Removing skill link: \$SKILL_LINK"
[[ -L "\$SKILL_LINK" ]] && rm "\$SKILL_LINK"
echo "Removing lab home : \$RAC_LAB_HOME"
rm -rf "\$RAC_LAB_HOME"
echo "Done."
UNINSTALL
chmod +x "$RAC_LAB_HOME/uninstall.sh"

cat > "$LAB_STATE/install.json" <<JSON
{
  "rac_lab_home": "$RAC_LAB_HOME",
  "claude_config_dir": "$CLAUDE_CONFIG_DIR",
  "skill_link": "$SKILL_LINK",
  "pack_repo": "$PACK_REPO",
  "pack_ref": "$PACK_REF",
  "pack_local": "${PACK_LOCAL:-}",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
ok "uninstall script: $RAC_LAB_HOME/uninstall.sh"

# ---- 8. Pick a target deployment ---------------------------------------
if [[ -z "${SKIP_PICKER:-}" ]] && [[ -x "$LAB_PACK/pick-target.sh" ]] && [[ -t 0 ]]; then
  step "Pick a target deployment"
  if "$LAB_PACK/pick-target.sh"; then
    ok "target written to $LAB_STATE/target.json"
  else
    code=$?
    if (( code == 2 )); then
      warn "BLOCKED target attempted; not saved (re-run pick-target.sh later with --allow-unsafe to override)"
    else
      warn "no target picked (exit $code) — run $LAB_PACK/pick-target.sh later"
    fi
  fi
else
  info "skipping picker (no TTY or SKIP_PICKER=1) — run $LAB_PACK/pick-target.sh later"
fi

# ---- 9. Generate post-install dashboard data ---------------------------
DASHBOARD="$LAB_PACK/post-install/index.html"
if [[ -f "$DASHBOARD" ]]; then
  step "Writing post-install dashboard data"
  # Build the skills list as JSON from each SKILL.md frontmatter.
  skills_json="["
  first=1
  for skill_dir in "$LAB_PACK/.claude/skills"/*/; do
    name="$(basename "$skill_dir")"
    desc="$(awk '/^description:/{sub(/^description: */,""); printf "%s", $0; exit}' "$skill_dir/SKILL.md" | jq -Rs .)"
    [[ $first -eq 0 ]] && skills_json+=","
    skills_json+="{\"name\":\"$name\",\"description\":$desc}"
    first=0
  done
  skills_json+="]"

  # Audit log (NDJSON → JSON array).
  if [[ -s "$LAB_STATE/fetch-log.json" ]]; then
    audit_json="$(jq -s '.' "$LAB_STATE/fetch-log.json")"
  else
    audit_json="[]"
  fi

  # Target (if picker has run yet — typically not at this point).
  if [[ -s "$LAB_STATE/target.json" ]]; then
    target_json="$(cat "$LAB_STATE/target.json")"
  else
    target_json="null"
  fi

  # Build the install object as proper JSON via jq, then prefix as JS assignment.
  # Use --arg (not <<<) so values don't pick up a trailing newline.
  install_obj="$(jq -nc \
    --arg rac_lab_home    "$RAC_LAB_HOME" \
    --arg claude_config_dir "$CLAUDE_CONFIG_DIR" \
    --arg skill_link      "$SKILL_LINK" \
    --arg pack_repo       "$PACK_REPO" \
    --arg pack_ref        "$PACK_REF" \
    --arg pack_local      "${PACK_LOCAL:-}" \
    --arg pack_path       "$LAB_PACK" \
    --arg installed_at    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson skills      "$skills_json" \
    --argjson fetch_log   "$audit_json" \
    --argjson target      "$target_json" \
    '{rac_lab_home:$rac_lab_home, claude_config_dir:$claude_config_dir, skill_link:$skill_link, pack_repo:$pack_repo, pack_ref:$pack_ref, pack_local:$pack_local, pack_path:$pack_path, installed_at:$installed_at, skills:$skills, fetch_log:$fetch_log, target:$target}')"
  printf 'window.RAC_LAB_INSTALL = %s;\n' "$install_obj" > "$LAB_PACK/post-install/data.js"
  ok "dashboard data → $LAB_PACK/post-install/data.js"
fi

# ---- 10. Done ----------------------------------------------------------
echo
echo "  ${C_OK}Installed.${C_END}"
echo
echo "  Next steps:"
echo "    1. Open a new Claude Code session — the lab skills are auto-discovered:"
for skill_dir in "$LAB_PACK/.claude/skills"/*/; do
  skill_name="$(basename "$skill_dir")"
  echo "         /$skill_name"
done
[[ -f "$DASHBOARD" ]] && \
  echo "    2. Open the dashboard:  file://$DASHBOARD"
echo "    3. View install state:  cat $LAB_STATE/install.json"
echo "    4. Re-pick a target:    $LAB_PACK/pick-target.sh"
echo "    5. Remove everything:   $RAC_LAB_HOME/uninstall.sh"
echo
