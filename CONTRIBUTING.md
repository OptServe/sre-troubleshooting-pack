# Contributing

Thanks for your interest in the AKS Lab Troubleshooting Pack. This pack collects scripts, runbooks, and Claude Code skills that SREs use day-to-day when operating Azure Kubernetes Service clusters from a developer Mac. We welcome additions that follow the patterns below.

## What to contribute

- **Runbooks** — short, focused Markdown files in `runbooks/` that walk through one specific recovery or diagnostic flow
- **Scripts** — small, well-scoped bash or Python tools in `bin/` that compose with `kubectl` and `az`
- **Skills** — Claude Code skills in `.claude/skills/<name>/SKILL.md` that automate common SRE flows

## Before opening a PR

1. **One change per PR.** Resist the urge to land a runbook and a skill in the same PR — reviewers can move faster on smaller units.
2. **Test on a real cluster.** Every script and skill must be exercised against a live AKS cluster (your own lab is fine). Note the cluster size, AKS version, and any preconditions in the PR description.
3. **Document the why.** A runbook that explains *why* the recovery works will be reused; one that only shows commands will be skipped on the third reading.

## Style

### Bash scripts (`bin/`)

- Start with `#!/usr/bin/env bash` and `set -euo pipefail`
- Quote all variable expansions
- Print one short usage line on bad input; exit non-zero
- Read from environment variables before reading from positional args; document expected env up front

### Runbooks (`runbooks/`)

- Open with a one-sentence "When to use this" header
- Each step is a short heading + a fenced code block + one or two sentences of explanation
- End with a "Verifying recovery" section so the reader knows when to stop

### Skills (`.claude/skills/`)

- One directory per skill, named `kebab-case`
- `SKILL.md` starts with YAML frontmatter (`name`, `description`)
- Description should answer "when should the model invoke this skill?" — not "what does it do?"

## Reporting bugs

Use the `bug` issue template. Include the AKS version, the exact command you ran, the observed behavior, and the expected behavior. Logs from `kubectl describe` and `kubectl get events` are almost always relevant.

## Reviewers

Two maintainer approvals required before merge. Maintainers are listed in the repo's About section. Tag `@OptServe/maintainers` if a review hasn't landed within 5 business days.
