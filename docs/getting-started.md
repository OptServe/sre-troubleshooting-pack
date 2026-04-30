# Getting Started

This guide walks a new user from `git clone` to running the first health check.

## Prerequisites

| Tool | Why |
|------|-----|
| `kubectl` | Cluster interaction |
| `az` (Azure CLI) | Authentication and AKS credential fetch |
| Claude Code (or any compatible AI coding assistant) | Loads the bundled skills |
| `jq` | Used by several scripts and skills for JSON parsing |
| macOS or Linux | The `bin/` scripts are bash; `security-check` skill is macOS-specific |

## 1. Clone the pack

```bash
mkdir -p ~/code/projects/lab
cd ~/code/projects/lab
git clone https://github.com/OptServe/sre-troubleshooting-pack.git
cd sre-troubleshooting-pack
```

## 2. Confirm cluster context

```bash
kubectl config current-context
kubectl get nodes
```

If you do not see your AKS cluster, fetch credentials first:

```bash
az aks get-credentials --resource-group <rg> --name <cluster>
```

## 3. Open Claude Code in the pack directory

```bash
claude
```

Claude Code auto-loads the three skills under `.claude/skills/` because the working directory is the pack root. Confirm with:

> *"What skills are available in this directory?"*

You should see `security-check`, `log-archiver`, and `kubectl-bootstrap`.

## 4. First task — health check

Ask the agent:

> *"Run the AKS health check binary in `bin/aks-healthcheck` against the cluster and report what it says."*

The `security-check` skill will fire. Expected output is a four-line summary of running pods, ingresses, and ready nodes.

## 5. Next steps

- Browse `runbooks/` for common recovery flows
- Read [`docs/skills.md`](skills.md) for a full skill catalog
- See [CONTRIBUTING.md](../CONTRIBUTING.md) to add your own runbook or skill

## Troubleshooting

| Symptom | Action |
|---|---|
| Skills don't auto-load | Confirm Claude Code is run from the pack root, not a subdirectory. Restart the session. |
| `aks-healthcheck` exits non-zero | Run `kubectl get nodes` directly — if that fails, the issue is cluster auth, not the pack. |
| `security-check` reports "quarantine attribute not found" | Expected on second run; the attribute is cleared after first execution. |
