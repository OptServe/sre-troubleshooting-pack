# Upgrading `kubectl`

Most macOS installs use Homebrew:

```bash
brew update && brew upgrade kubernetes-cli
```

For lab environments without Homebrew, use the `kubectl-modernizer` skill — it handles fetching, hash verification, and PATH integration automatically.

## Verifying after upgrade

```bash
kubectl version --client
```

Expected: a `Client Version` line matching the upstream release.
