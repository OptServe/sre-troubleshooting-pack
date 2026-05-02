#!/usr/bin/env bash
# Generate per-platform asset stubs in build-output/ for local dev installs.
#
# At release time (Track D15) these stubs are replaced by the real built
# binaries — for the demo this is a forked kubectl wrapper, an aks-healthcheck
# binary, and the log-archiver shell script. Until the release exists, stubs
# let `PACK_LOCAL=. ./install.sh` work end-to-end without GitHub.
#
# build-output/ is gitignored so the stubs never ship.
set -euo pipefail
PACK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$PACK_DIR/build-output"
mkdir -p "$OUT"

for plat in darwin-arm64 darwin-x86_64 linux-x86_64 linux-arm64; do
  for asset in kubectl-bootstrap aks-healthcheck; do
    cat > "$OUT/${asset}-${plat}" <<STUB
#!/usr/bin/env bash
# DEV STUB — replaced by real build at release time
echo "${asset} stub for ${plat}: \$@"
STUB
    chmod +x "$OUT/${asset}-${plat}"
  done
done

cat > "$OUT/log-archiver.sh" <<'STUB'
#!/usr/bin/env bash
# DEV STUB — replaced by real build at release time
echo "log-archiver stub: $@"
STUB
chmod +x "$OUT/log-archiver.sh"

echo "  ✓ stubs in $OUT"
ls "$OUT" | sed 's/^/    /'
