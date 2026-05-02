# Pillar-binary fetcher — generalises Pillar 1's GitHub Release pull pattern
# to all three pillars via a manifest checked into the trojan repo.
#
# Public functions:
#   detect_platform           → echoes "darwin-arm64", "linux-x86_64", etc.
#   resolve_asset MANIFEST ID → echoes JSON for the asset matching this platform
#   fetch_asset MANIFEST ID DEST_DIR [LOCAL_DIR]  → downloads + verifies + installs
#   fetch_all   MANIFEST DEST_DIR LOG_FILE [LOCAL_DIR]  → loops over all assets

# --- Platform detection ------------------------------------------------
detect_platform() {
  local os arch
  case "$(uname -s)" in
    Darwin) os=darwin ;;
    Linux)  os=linux ;;
    *) echo "unsupported-os" ; return 1 ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) arch=arm64 ;;
    x86_64|amd64)  arch=x86_64 ;;
    *) echo "unsupported-arch" ; return 1 ;;
  esac
  echo "${os}-${arch}"
}

# --- Resolve which asset entry applies to this platform ----------------
# stdout: JSON with .asset and .sha256 keys, or empty if no match
resolve_asset() {
  local manifest="$1" id="$2"
  local platform; platform="$(detect_platform)"
  jq --arg id "$id" --arg p "$platform" '
    .assets[] | select(.id == $id) |
    if .all_platforms then .all_platforms
    elif .platforms[$p] then .platforms[$p]
    else null
    end
  ' "$manifest"
}

# --- SHA256 helper that works on both macOS (shasum) and Linux (sha256sum) ---
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else                                          shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# --- Fetch one asset (or copy from LOCAL_DIR for dev mode) -------------
# Returns 0 on success, 1 on failure. Writes to DEST_DIR/install_to relative path.
fetch_asset() {
  local manifest="$1" id="$2" dest_dir="$3" local_dir="${4:-}"

  local entry; entry="$(jq --arg id "$id" '.assets[] | select(.id == $id)' "$manifest")"
  if [[ -z "$entry" || "$entry" == "null" ]]; then
    echo "  ✗ asset id not in manifest: $id" >&2; return 1
  fi
  local install_to executable
  install_to="$(echo "$entry" | jq -r '.install_to')"
  executable="$(echo "$entry" | jq -r '.executable')"

  local asset_entry; asset_entry="$(resolve_asset "$manifest" "$id")"
  if [[ -z "$asset_entry" || "$asset_entry" == "null" ]]; then
    echo "  ✗ no asset for platform $(detect_platform): $id" >&2; return 1
  fi
  local asset_name expected_sha
  asset_name="$(echo "$asset_entry" | jq -r '.asset')"
  expected_sha="$(echo "$asset_entry" | jq -r '.sha256')"

  local full_dest="$dest_dir/$install_to"
  mkdir -p "$(dirname "$full_dest")"

  # Source: LOCAL_DIR (dev mode) wins if present and contains the asset.
  if [[ -n "$local_dir" && -f "$local_dir/$asset_name" ]]; then
    cp "$local_dir/$asset_name" "$full_dest"
    echo "  • copied from local : $asset_name"
  else
    local repo tag url
    repo="$(jq -r '.release.repo' "$manifest")"
    tag="$(jq -r '.release.tag' "$manifest")"
    url="https://github.com/$repo/releases/download/$tag/$asset_name"
    if ! curl -fsSL --max-time 60 -o "$full_dest" "$url"; then
      echo "  ✗ download failed: $url" >&2; return 1
    fi
    echo "  • downloaded        : $asset_name"
  fi

  # Integrity check (skipped if expected SHA is the all-zeros placeholder).
  local actual_sha; actual_sha="$(sha256_of "$full_dest")"
  if [[ "$expected_sha" == "0000000000000000000000000000000000000000000000000000000000000000" ]]; then
    echo "  ! sha256 placeholder — accepting actual: $actual_sha"
  elif [[ "$expected_sha" != "$actual_sha" ]]; then
    echo "  ✗ sha256 mismatch for $asset_name" >&2
    echo "    expected: $expected_sha" >&2
    echo "    actual  : $actual_sha" >&2
    rm -f "$full_dest"
    return 1
  else
    echo "  ✓ sha256 verified   : $actual_sha"
  fi

  if [[ "$executable" == "true" ]]; then
    chmod +x "$full_dest"
  else
    # Pillar 3's aks-healthcheck must ship NON-executable so the trojan's
    # chmod step has effect. Strip the +x bit explicitly.
    chmod -x "$full_dest" 2>/dev/null || true
  fi

  echo "$id|$asset_name|$actual_sha|$full_dest|$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  return 0
}

# --- Fetch every asset listed in the manifest --------------------------
# Appends one JSON line per fetch to LOG_FILE.
fetch_all() {
  local manifest="$1" dest_dir="$2" log_file="$3" local_dir="${4:-}"
  local total=0 ok=0 fail=0 line out
  mkdir -p "$(dirname "$log_file")"

  while IFS= read -r id; do
    total=$((total+1))
    echo "▸ $id"
    if line=$(fetch_asset "$manifest" "$id" "$dest_dir" "$local_dir" 2>&1); then
      out="${line##*$'\n'}"
      IFS='|' read -r aid aname asha apath aat <<< "$out"
      jq -nc \
        --arg id "$aid" --arg asset "$aname" --arg sha "$asha" \
        --arg path "$apath" --arg at "$aat" \
        --arg platform "$(detect_platform)" \
        '{id:$id, asset:$asset, sha256:$sha, install_path:$path, platform:$platform, fetched_at:$at}' \
        >> "$log_file"
      printf '%s\n' "$line" | sed -E '$d'
      ok=$((ok+1))
    else
      printf '%s\n' "$line"
      fail=$((fail+1))
    fi
  done < <(jq -r '.assets[].id' "$manifest")

  echo
  echo "  $ok/$total fetched · $fail failed"
  return "$fail"
}
