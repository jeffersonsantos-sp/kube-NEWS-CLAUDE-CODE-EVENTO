# ArgoCD Status Report
Generated: 2026-06-03

## ArgoCD Version
- **Version:** v3.4.3
- **Image:** `quay.io/argoproj/argocd:v3.4.3`
- **Build date:** 2026-05-28T11:38:55Z

## ArgoCD UI Access
- **URL:** http://20.213.174.138 (LoadBalancer, ports 80/443)
- **Service:** argocd-server (LoadBalancer)

---

## ArgoCD Component Health

| Pod | Status | Restarts |
|-----|--------|----------|
| argocd-application-controller-0 | Running | 0 |
| argocd-applicationset-controller | **CrashLoopBackOff** | 22 |
| argocd-dex-server | Running | 0 |
| argocd-notifications-controller | Running | 0 |
| argocd-redis | Running | 0 |
| argocd-repo-server | Running | 0 |
| argocd-server | Running | 0 |

### CrashLoopBackOff: argocd-applicationset-controller

**Root cause:** The CRD `applicationsets.argoproj.io` is NOT installed in the cluster. The controller tries to watch this resource and fails with:

```
failed to get restmapping: no matches for kind "ApplicationSet" in version "argoproj.io/v1alpha1"
```

After 2 minutes of retrying it times out and crashes, then Kubernetes restarts it (loop repeats).

**Impact:** ApplicationSet controller is non-functional. However, this does NOT affect the standard `Application` resource or current deployments — the `kube-news` Application continues to sync normally via `argocd-application-controller`.

**Installed ArgoCD CRDs (present):**
- `applications.argoproj.io`
- `appprojects.argoproj.io`

**Missing CRD:**
- `applicationsets.argoproj.io` — NOT installed

---

## ArgoCD Application: kube-news

| Field | Value |
|-------|-------|
| Sync Status | **Synced** |
| Health Status | **Healthy** |
| Last Sync Revision | `ae0267c5771973ec7e6a49729421b772d34093d1` |
| Sync Policy | Automated (prune=true, self-heal=true) |
| Source Repo | https://github.com/jeffersonsantos-sp/kube-NEWS-CLAUDE-CODE-EVENTO.git |
| Source Path | `k8s/` |
| Target Revision | `main` |
| Target Namespace | `kube-news` |
| Last Sync Time | 2026-06-03T20:55:16Z |
| Last Sync By | admin (manual trigger) |
| External URL | https://jfs-devops.shop/ |

### Sync History (last 3 syncs)

| ID | Revision | Triggered By | Time |
|----|----------|--------------|------|
| 0 | `5c2d61a6...` | Automated | 2026-06-03T19:21:56Z |
| 1 | `ce375744...` | Automated | 2026-06-03T19:45:07Z |
| 2 | `ae0267c5...` | admin (manual) | 2026-06-03T20:55:15Z |

---

## Running Application State (namespace: kube-news)

### Pods

| Pod | Status | Restarts | Age |
|-----|--------|----------|-----|
| kube-news-blue-75c4f47878-95nnd | Running 1/1 | 3 (23h ago) | 23h |
| kube-news-blue-75c4f47878-ck8hg | Running 1/1 | 3 (23h ago) | 23h |
| kube-news-green-b5f66df45-g4bl5 | Running 1/1 | 0 | ~9m |
| kube-news-green-b5f66df45-hxq4t | Running 1/1 | 0 | ~9m |
| postgres-679866d69f-bxxnn | Running 1/1 | 0 | 23h |

### Deployments

| Deployment | Image | Ready | Selector |
|------------|-------|-------|----------|
| kube-news-blue | `updateinformatica/claude-devops:1.0` | 2/2 | version=blue |
| kube-news-green | `updateinformatica/claude-devops:v1.2.6` | 2/2 | version=green |
| postgres | `postgres:15-alpine` | 1/1 | app=postgres |

### Active Traffic Version

The `kube-news` Service selector is currently pointing to **version=green**, meaning:

- **Live traffic goes to:** `kube-news-green` (image: `updateinformatica/claude-devops:v1.2.6`)
- **Standby:** `kube-news-blue` (image: `updateinformatica/claude-devops:1.0`)

### Services

| Service | Type | Selector |
|---------|------|----------|
| kube-news | ClusterIP | app=kube-news, **version=green** |
| kube-news-preview | ClusterIP | app=kube-news, version=green |
| postgres | ClusterIP | app=postgres |

---

## Summary

### Deploy is working?
**YES.** The ArgoCD `kube-news` Application is Synced and Healthy. The application controller reconciled successfully at 2026-06-03T21:07:18Z. All resources in `kube-news` namespace are synced from git.

### Version currently running?
**`updateinformatica/claude-devops:v1.2.6`** (Green deployment) is receiving all production traffic.
The blue deployment (`1.0`) is standing by.

### Known Problem
The `argocd-applicationset-controller` is in CrashLoopBackOff (22 restarts) due to the missing `applicationsets.argoproj.io` CRD. This is a partial installation issue — ArgoCD v3.4.3 was installed without the ApplicationSet CRD. This does not affect current operations since no ApplicationSet resources are in use, but should be fixed by reinstalling ArgoCD with the complete CRD set.
