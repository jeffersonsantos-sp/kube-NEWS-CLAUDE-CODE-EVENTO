# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

kube-news is a Node.js news portal used as a Kubernetes/containers learning environment. Multi-cloud deployment with Blue-Green strategy.

**Multi-cloud layout:**

```
clouds/
├── azure/        ← Azure AKS (active production)
│   ├── terraform/    AKS provisioning (azurerm provider)
│   ├── k8s/          Active manifests — watched by ArgoCD
│   ├── k8s-legacy/   Old flat manifests (no Blue-Green) — not active
│   ├── argocd/       ArgoCD Application bootstrap
│   ├── incidents/    Incident RCAs and action plans
│   ├── ARGOCD.md
│   ├── OBSERVABILITY.md
│   └── PROPOSTA-AZURE-AKS.md
├── gcp/          ← GCP GKE (parallel, in progress)
│   ├── terraform/    GKE provisioning (google provider, us-central1, e2-medium)
│   ├── k8s/          GKE manifests — watched by ArgoCD GCP
│   ├── argocd/       ArgoCD Application for GKE
│   ├── monitoring/   Helm values (storageClass: standard-rwo)
│   └── GCP.md
└── aws/          ← AWS EKS (placeholder — not yet implemented)
    ├── terraform/
    ├── k8s/
    ├── argocd/
    └── README.md
```

## Commands

### Local development

```bash
cd src && npm install   # install dependencies
npm start               # run on :8080 (requires PostgreSQL)
```

### Docker

```bash
docker compose up                      # start app + postgres
docker build -t updateinformatica/claude-devops:TAG .   # build image
docker push updateinformatica/claude-devops:TAG         # push to registry
```

### Kubernetes — Azure AKS

```bash
# Bootstrap (one-time) — registers the ArgoCD Application; after this ArgoCD manages everything
kubectl apply -f clouds/azure/argocd/argocd-app.yaml

# Manual deploy (bypasses GitOps — emergency/local testing only)
kubectl apply -f clouds/azure/k8s/kube-news-blue.yaml

# Rollback via GitOps: edit selector version: green → blue, then:
git add clouds/azure/k8s/kube-news-blue.yaml && git commit -m "rollback: switch traffic to blue" && git push
```

### Kubernetes — GCP GKE

```bash
# Provision GKE cluster
cd clouds/gcp/terraform && cp terraform.tfvars.example terraform.tfvars  # fill project_id
terraform init && terraform apply
terraform output -raw get_credentials_command | bash   # configure kubectl

# Bootstrap ArgoCD Application on GKE
kubectl apply -f clouds/gcp/argocd/argocd-app.yaml

# Switch kubectl contexts
kubectl config use-context AKSCLAUDECODE                                   # Azure
kubectl config use-context gke_<PROJECT_ID>_us-central1_kube-news-gke     # GCP
```

### Helm (observability stack)

Helm binary lives at `~/bin/helm` — run `export PATH="$HOME/bin:$PATH"` before helm commands.

```bash
# Azure AKS
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --values clouds/azure/k8s/monitoring/values-kube-prometheus-stack.yaml

helm upgrade loki-stack grafana/loki-stack \
  --namespace monitoring --values clouds/azure/k8s/monitoring/values-loki-stack.yaml

# GCP GKE
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --values clouds/gcp/monitoring/values-kube-prometheus-stack.yaml

helm upgrade loki-stack grafana/loki-stack \
  --namespace monitoring --values clouds/gcp/monitoring/values-loki-stack.yaml
```

### Helm (ingress + TLS) — Azure AKS

```bash
helm upgrade ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-protocol"=tcp \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true
```

## Architecture

### Application (`src/`)

- **`server.js`** — entry point; wires all middleware and routes; calls `models.initDatabase()` on startup which auto-syncs the schema via Sequelize
- **`system-life.js`** — health/readiness probes (`GET /health`, `GET /ready`) + chaos engineering endpoints (`PUT /unhealth`, `PUT /unreadyfor/:seconds`); `healthMid` is applied globally as middleware before all routes
- **`middleware.js`** — increments a Prometheus counter `http_requests_total` with `method` and `path` labels on every request
- **`models/post.js`** — single Sequelize model `Post`; no migrations, schema is created via `sync()` at startup

Prometheus metrics are exposed at `GET /metrics` via `express-prom-bundle`, which automatically produces histograms for every route. The custom counter in `middleware.js` is additive on top of that.

### Kubernetes layout

#### Azure AKS (`clouds/azure/`)

| File | Purpose |
|---|---|
| `clouds/azure/k8s/kube-news-blue.yaml` | **Active manifests**: Namespace, Secret, ConfigMap, PVC, postgres Deployment+Service, blue app Deployment, **ClusterIP** Service |
| `clouds/azure/k8s/kube-news-green.yaml` | Green Deployment + preview ClusterIP Service (port 8080) |
| `clouds/azure/k8s/ingress.yaml` | NGINX Ingress for `jfs-devops.shop` — HTTP + HTTPS (TLS via `letsencrypt-prod`), `ssl-redirect: false` |
| `clouds/azure/k8s/cert-issuer.yaml` | ClusterIssuers `letsencrypt-staging` and `letsencrypt-prod` |
| `clouds/azure/k8s/monitoring/` | Helm values + ServiceMonitors + PrometheusRules for the observability stack |
| `clouds/azure/k8s-legacy/` | Legacy flat manifests (no Blue-Green) — not the active deployment |
| `clouds/azure/argocd/argocd-app.yaml` | ArgoCD Application manifest — applied once to bootstrap GitOps |
| `clouds/azure/terraform/` | AKS cluster provisioning (azurerm provider, modules: aks + networking) |

#### GCP GKE (`clouds/gcp/`)

| File | Purpose |
|---|---|
| `clouds/gcp/k8s/kube-news-blue.yaml` | Same Blue-Green manifests, storageClass: `standard-rwo` |
| `clouds/gcp/k8s/kube-news-green.yaml` | Green Deployment for GKE |
| `clouds/gcp/argocd/argocd-app.yaml` | ArgoCD Application `kube-news-gcp` — watches `clouds/gcp/k8s/` |
| `clouds/gcp/terraform/` | GKE cluster provisioning (google provider, us-central1, e2-medium) |
| `clouds/gcp/monitoring/` | Helm values (storageClass: `standard-rwo`) |

The Blue-Green switch is entirely controlled by the `version:` label selector on the `kube-news` Service in `kube-news-blue.yaml`. No other changes are required to promote green to production.

Traffic entry point is the NGINX Ingress Controller LoadBalancer (IP `20.53.187.114`). DNS `jfs-devops.shop` points to this IP. The `kube-news` Service is ClusterIP — no direct external IP.

### Secrets and config

In Kubernetes, credentials live in `kube-news-secret` (Secret) and non-sensitive config in `kube-news-config` (ConfigMap), both defined in `kube-news-blue.yaml`. The postgres-exporter in `clouds/azure/k8s/monitoring/postgres-exporter.yaml` reuses these same objects via `valueFrom`.

### ArgoCD (GitOps)

| Item | Azure AKS | GCP GKE |
|---|---|---|
| UI | `http://20.213.174.138` | install after `terraform apply` |
| Application name | `kube-news` | `kube-news-gcp` |
| Watched path | `clouds/azure/k8s/` | `clouds/gcp/k8s/` |
| Bootstrap manifest | `clouds/azure/argocd/argocd-app.yaml` | `clouds/gcp/argocd/argocd-app.yaml` |
| Auto-sync | enabled — prune + selfHeal | enabled — prune + selfHeal |
| Full documentation | `clouds/azure/ARGOCD.md` | `clouds/gcp/GCP.md` |

#### CI/CD flow (Azure — active pipeline)

```
git tag v1.2.3 && git push --tags
  → CI: npm ci → docker build → docker push updateinformatica/claude-devops:v1.2.3
  → CD: updates clouds/azure/k8s/kube-news-green.yaml (image)
        + clouds/azure/k8s/kube-news-blue.yaml (selector → green) → git push
  → ArgoCD: detects commit (~3 min) → applies manifests to cluster
```

GitHub Actions secrets required: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`. `KUBECONFIG` is no longer needed.

### Observability

- **Prometheus + Grafana + AlertManager**: installed via `kube-prometheus-stack` Helm chart in `monitoring` namespace
- **Loki + Promtail**: installed via `loki-stack` Helm chart; Grafana datasource URL is `http://loki-stack.monitoring.svc.cluster.local:3100`
- **Grafana**: LoadBalancer at `http://20.249.165.203` — credentials in `clouds/azure/k8s/monitoring/values-kube-prometheus-stack.yaml`
- **App metrics scraping**: `clouds/azure/k8s/monitoring/kube-news-metrics-service.yaml` creates a dedicated ClusterIP Service (port 8080, selector `app: kube-news`) that the ServiceMonitor targets — this covers both blue and green pods simultaneously
- Full documentation: `clouds/azure/OBSERVABILITY.md`

### MCP servers (`.mcp.json`)

| Server | What it does |
|---|---|
| `kubernetes` | kubectl access via Docker container — use for all cluster operations |
| `prometheus` | Prometheus query API at `localhost:9090` (requires port-forward active) |
| `context7` | Fetches up-to-date library documentation |

## Skills (`.claude/skills/`)

Use these skills for recurring tasks rather than implementing from scratch:

| Skill | When to use |
|---|---|
| `gerador-kubernetes` | Generate Blue-Green K8s manifests from `docker-compose.yml` |
| `gerador-docker` | Audit `Dockerfile` and `docker-compose.yml` against project rules |
| `generator-observability` | Generate and install the full Prometheus+Grafana+Loki stack |
| `k8s-incident` | Diagnose cluster incidents — produces `INCIDENT_RCA.md` and `ACTION_PLAN.md` in `clouds/azure/incidents/` |
| `setup-https` | Configure HTTPS on AKS: NGINX Ingress + cert-manager + Let's Encrypt — includes Azure LB probe fix, staging→prod cert sequence, and Blue-Green compatibility |
| `argocd-gitops` | Diagnose ArgoCD Application state and GitOps pipeline issues — generates `ARGOCD_STATUS.md` + `ARGOCD_ACTION_PLAN.md` in `clouds/azure/argocd/incidents/` |
| `blue-green` | Execute Blue-Green deployment operations via GitOps: traffic switch (blue↔green), rollback, manual green deploy with a specific image tag, and blue baseline update — all via git commit + push, ArgoCD applies automatically |

## Image naming

The Docker image is `updateinformatica/claude-devops`. The tag in `docker-compose.yml` may differ from the tag pinned in the K8s manifests — always update `clouds/azure/k8s/kube-news-green.yaml` (or `clouds/gcp/k8s/kube-news-green.yaml` for GCP) with the new tag before a Blue-Green promotion.

## Chaos endpoints

`PUT /unhealth` flips a process-level flag that makes all subsequent requests return 500. **Only a pod restart resets it.** `PUT /unreadyfor/:seconds` temporarily makes `/ready` return 500 for the given duration. Both are intentional for testing Kubernetes probe behavior.
