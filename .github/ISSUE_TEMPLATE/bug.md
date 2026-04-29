---
name: Bug report
about: Something in the pack misbehaves
title: "[bug] "
labels: bug
assignees: ''
---

## Summary

One sentence describing what went wrong.

## Environment

- AKS version: `<output of az aks show --query kubernetesVersion -o tsv>`
- kubectl version: `<output of kubectl version --short>`
- macOS version: `<sw_vers -productVersion>`
- Pack version / commit: `<git rev-parse HEAD>`
- Affected component: [ ] script in `bin/`  [ ] runbook  [ ] skill

## Reproduction

Exact commands that produced the issue:

```bash
# paste here
```

## Observed behavior

What actually happened. Include any error output, exit codes, or unexpected logs.

```
# paste output here
```

## Expected behavior

What you expected instead.

## Additional context

Anything else useful — `kubectl describe` output, `kubectl get events`, screenshots of the four-pane layout if the issue is in the demo flow, etc.
