# Upgrading AKS Cluster Version

**When to use this:** A new AKS minor version is generally available and the cluster is more than two minors behind, or a CVE notice requires a patch upgrade.

## 1. Check current version

```bash
az aks show --resource-group <rg> --name <cluster> --query 'kubernetesVersion' -o tsv
az aks get-upgrades --resource-group <rg> --name <cluster> --output table
```

The `Upgrades` column lists available targets.

## 2. Plan the upgrade hop

AKS supports skipping at most one minor version per upgrade. To go from 1.28 to 1.30, you must upgrade to 1.29 first, wait for the cluster to settle, then upgrade to 1.30.

## 3. Upgrade the control plane only

```bash
az aks upgrade \
  --resource-group <rg> \
  --name <cluster> \
  --kubernetes-version <target-version> \
  --control-plane-only \
  --yes
```

Control-plane-only upgrades are faster and let you verify control plane stability before touching node pools.

## 4. Verify control plane

```bash
kubectl version --short
kubectl get nodes
```

The `Server Version` should report the new version. Nodes still show the old version — that's expected at this stage.

## 5. Upgrade node pools one at a time

```bash
az aks nodepool list --resource-group <rg> --cluster-name <cluster> -o table

az aks nodepool upgrade \
  --resource-group <rg> \
  --cluster-name <cluster> \
  --name <nodepool-name> \
  --kubernetes-version <target-version> \
  --max-surge 33%
```

`--max-surge 33%` is the AKS default and balances upgrade speed against extra capacity cost.

## 6. Watch the rolling upgrade

```bash
kubectl get nodes -w
kubectl get pods -A -w
```

Pods on cordoned nodes will be drained and rescheduled. Workloads with `PodDisruptionBudget` will gate the drain — long-blocked drains usually mean a PDB is too strict.

## Verifying upgrade

```bash
az aks show --resource-group <rg> --name <cluster> --query 'kubernetesVersion' -o tsv
kubectl get nodes -o wide
```

All nodes should report the new version. The cluster's overall `kubernetesVersion` matches the target.
