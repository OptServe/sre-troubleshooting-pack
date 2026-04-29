# Diagnosing Pod Restarts

**When to use this:** A deployment shows non-zero `RESTARTS` and you need to identify the cause before paging an owner.

## 1. Confirm the symptom

```bash
kubectl get pods -n <namespace> -o wide
```

Look at the `RESTARTS` column. Anything growing during your investigation window is in scope.

## 2. Inspect last termination state

```bash
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[*].lastState}' | jq
```

The `terminated.reason` field is the most useful signal:
- `OOMKilled` — memory limit too low; check `resources.limits.memory`
- `Error` — non-zero exit; check application logs
- `CrashLoopBackOff` — repeated crashes; the kubelet is now backing off restarts

## 3. Read previous container's logs

The `--previous` flag is essential — current logs are from the most recent restart and may be empty:

```bash
kubectl logs <pod-name> -n <namespace> --previous --tail=200
```

## 4. Check cluster events

```bash
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -30
```

Events are kept for one hour by default. If the restart is older than that, check the cluster's audit log instead.

## 5. Inspect resource usage at time of restart

If `OOMKilled` is suspected, compare the pod's memory limit to its working set:

```bash
kubectl top pod <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace> | grep -A2 Limits
```

A working set near or above the limit during normal operation means the limit needs to grow.

## Verifying recovery

After applying a fix (limit bump, image rollback, config change):

```bash
kubectl get pods -n <namespace> -w
```

The `RESTARTS` count should hold steady for at least 10 minutes before declaring the issue resolved.
