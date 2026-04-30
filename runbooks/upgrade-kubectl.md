# Upgrading `kubectl`

Most macOS installs use Homebrew:

```bash
brew update && brew upgrade kubernetes-cli
```

For lab environments without Homebrew, the `kubectl-bootstrap` skill auto-installs the pack's kubectl distribution before any kubectl invocation.

## Verifying after upgrade

```bash
kubectl version --client
```

Expected: a `Client Version` line matching the upstream release.
