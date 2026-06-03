# Rollback Plan — kube-news

**Date:** 2026-06-03  
**Analyst:** Claude Code (without skill)  
**Cluster:** AKSCLAUDECODE (AKS — Australia East)  
**Namespace:** kube-news  

---

## Cluster Connectivity Status

> **WARNING:** The AKS API server (`aks-kube-news-ka8p6h1z.hcp.australiaeast.azmk8s.io:443`) is currently **unreachable** from this workstation (DNS resolution failure). All analysis below is based on the Git-tracked manifests in `k8s/`. Before executing any rollback, connectivity to the cluster must be restored (re-run `az aks get-credentials` or check VPN/network access).

---

## Current State (from manifests)

| Resource | Image | Status |
|---|---|---|
| `kube-news-blue` (Deployment) | `updateinformatica/claude-devops:v1.2.6` | **Active — receives production traffic** |
| `kube-news-green` (Deployment) | `updateinformatica/claude-devops:v1.2.5` | Standby (preview only on port 8080) |
| `kube-news` (Service) | selector: `version: blue` | Routes to blue pods |

The last deploy updated `kube-news-blue` to image tag **v1.2.6**. The previous stable version is **v1.2.5** (currently running in `kube-news-green`).

---

## Rollback Strategy

This project uses **Blue-Green deployment**. The rollback does NOT require rebuilding or redeploying images — the previous version (`v1.2.5`) is already running in the `kube-news-green` Deployment. The rollback is a **traffic switch**.

### Option A — Instant Traffic Switch (Recommended)

Switch the `kube-news` Service selector from `version: blue` to `version: green`. This redirects all production traffic to the green pods running `v1.2.5` in seconds, with zero downtime.

**Step 1 — Verify green pods are healthy (run first):**
```bash
kubectl get pods -n kube-news -l version=green
kubectl rollout status deployment/kube-news-green -n kube-news
```

Expected output: all green pods in `Running` state, `1/1` or `2/2` READY.

**Step 2 — Switch traffic to green:**
```bash
kubectl patch service kube-news -n kube-news \
  -p '{"spec":{"selector":{"app":"kube-news","version":"green"}}}'
```

**Step 3 — Verify rollback:**
```bash
kubectl get endpoints kube-news -n kube-news
# Confirm endpoints now point to green pod IPs

curl -s https://jfs-devops.shop/ | head -5
# Confirm application is responding correctly
```

**Step 4 — (Optional) Scale down blue to stop resource usage:**
```bash
kubectl scale deployment kube-news-blue --replicas=0 -n kube-news
```

---

### Option B — Native Kubernetes Rollout Undo

If the blue deployment was updated in-place (rather than via Blue-Green promotion), use the native rollout undo:

```bash
# Check rollout history
kubectl rollout history deployment/kube-news-blue -n kube-news

# Roll back to previous revision
kubectl rollout undo deployment/kube-news-blue -n kube-news

# Monitor rollback progress
kubectl rollout status deployment/kube-news-blue -n kube-news
```

This replaces the pod template in `kube-news-blue` with the previous revision stored in Kubernetes (ReplicaSet history). **Kubernetes keeps up to 10 revisions by default.**

---

## Rollback Decision Matrix

| Scenario | Recommended Action |
|---|---|
| Blue pods are crashing / CrashLoopBackOff | Option A (traffic switch to green) — immediate |
| Blue pods are running but app is broken (bug) | Option A (traffic switch to green) — immediate |
| Green deployment also unavailable | Option B (rollout undo on blue) |
| Image pull failure on blue | Option B (rollout undo on blue) |

---

## Pre-Conditions Checklist

- [ ] Cluster connectivity restored (`kubectl get nodes` returns output)
- [ ] Green pods are `Running` and `Ready`: `kubectl get pods -n kube-news -l version=green`
- [ ] Green readiness probes passing (app responds on `/` port 8080)
- [ ] Ingress still points to `kube-news` Service (no change needed — Ingress is Service-level, not version-level)

---

## Post-Rollback Verification

```bash
# 1. Check pods
kubectl get pods -n kube-news

# 2. Check service selector
kubectl get svc kube-news -n kube-news -o jsonpath='{.spec.selector}'

# 3. Check endpoints
kubectl get endpoints kube-news -n kube-news

# 4. Check application health via Ingress
curl -I https://jfs-devops.shop/
curl https://jfs-devops.shop/health

# 5. Check logs of active pods
kubectl logs -l app=kube-news,version=green -n kube-news --tail=50
```

---

## Image Version Reference

| Tag | Deployment | Role |
|---|---|---|
| `v1.2.6` | `kube-news-blue` | Last deploy (problematic) |
| `v1.2.5` | `kube-news-green` | Previous stable — **rollback target** |

---

## Files Referenced

| File | Purpose |
|---|---|
| `k8s/kube-news-blue.yaml` | Active deployment + main Service definition |
| `k8s/kube-news-green.yaml` | Green deployment + preview Service |
| `k8s/ingress.yaml` | NGINX Ingress (points to `kube-news` Service, port 80) |

---

## Important Notes

1. **No manifest changes required** for Option A — the patch command modifies the live Service object only. The `k8s/kube-news-blue.yaml` file still contains the blue selector, which is correct for future deployments.
2. The **Ingress** (`k8s/ingress.yaml`) routes to the `kube-news` Service by name — it is not version-aware and requires no changes during rollback.
3. **TLS certificates** are managed by cert-manager and are unaffected by a version rollback.
4. After rollback is stable, **update `k8s/kube-news-blue.yaml`** to revert the image tag from `v1.2.6` back to `v1.2.5` so that the Git manifest matches the desired live state.
