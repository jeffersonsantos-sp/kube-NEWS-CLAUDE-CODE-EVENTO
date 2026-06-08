# GCP — kube-news no GKE

Este documento descreve a infraestrutura GCP paralela à Azure AKS já existente.
Os arquivos Azure em `k8s/` e `argocd/` **não foram alterados**.

## Estrutura

```
gcp/
├── terraform/          # Provisionamento do cluster GKE
│   ├── providers.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── k8s/                # Manifestos K8s adaptados para GCP (path do ArgoCD GCP)
│   ├── kube-news-blue.yaml
│   ├── kube-news-green.yaml
│   ├── ingress.yaml
│   └── cert-issuer.yaml
├── argocd/
│   └── argocd-app.yaml # Application aponta para clouds/gcp/k8s
└── monitoring/
    ├── values-kube-prometheus-stack.yaml
    └── values-loki-stack.yaml
```

## Diferenças Azure AKS → GCP GKE

| Item | Azure AKS | GCP GKE |
|---|---|---|
| StorageClass | `managed-csi` | `standard-rwo` (pd-standard) ou `premium-rwo` (pd-ssd) |
| LB health probe | annotation `/healthz` obrigatória (bug AKS 1.34+) | Sem restrição — usa `/healthz` do ingress-nginx nativamente |
| Contexto kubectl | `AKSCLAUDECODE` | `gke_<project>_us-central1_kube-news-gke` |
| ArgoCD app name | `kube-news` | `kube-news-gcp` |
| ArgoCD watch path | `k8s/` | `clouds/gcp/k8s/` |
| Probes da app | path `/` | path `/ready` (liveness `/health`) |

## Pré-requisitos

```bash
# 1. gcloud CLI autenticado
gcloud auth login
gcloud auth application-default login

# 2. APIs habilitadas
gcloud services enable container.googleapis.com compute.googleapis.com

# 3. Helm disponível
export PATH="$HOME/bin:$PATH"
```

## 1. Provisionar cluster GKE (Terraform)

```bash
cd clouds/gcp/terraform

cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars — preencha project_id

terraform init
terraform plan
terraform apply
```

Após o apply, configure o kubectl:

```bash
# O comando exato é exibido no output do Terraform
terraform output -raw get_credentials_command | bash

# Verifique o contexto ativo
kubectl config current-context
kubectl get nodes
```

## 2. Instalar NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

Aguarde o IP externo do LoadBalancer:

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller --watch
```

Anote o `EXTERNAL-IP` e aponte o DNS `jfs-devops.shop` para ele.

## 3. Instalar cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

## 4. Instalar ArgoCD no GKE

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expor a UI (port-forward local)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Senha inicial
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

## 5. Registrar a Application GCP no ArgoCD

```bash
kubectl apply -f clouds/gcp/argocd/argocd-app.yaml
```

A partir deste ponto, ArgoCD sincroniza `clouds/gcp/k8s/` automaticamente no cluster GKE.

## 6. Aplicar cert-issuer e ingress

```bash
kubectl apply -f clouds/gcp/k8s/cert-issuer.yaml
kubectl apply -f clouds/gcp/k8s/ingress.yaml
```

## 7. Stack de Observabilidade (GKE)

```bash
export PATH="$HOME/bin:$PATH"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values clouds/gcp/monitoring/values-kube-prometheus-stack.yaml

helm upgrade --install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --values clouds/gcp/monitoring/values-loki-stack.yaml
```

## Blue-Green no GCP

O mecanismo é idêntico ao Azure — o seletor `version:` no Service `kube-news` em `clouds/gcp/k8s/kube-news-blue.yaml` controla o tráfego.

```bash
# Ver slot ativo
grep "version:" clouds/gcp/k8s/kube-news-blue.yaml | tail -1

# Trocar blue → green via GitOps
sed -i 's/version: blue/version: green/' clouds/gcp/k8s/kube-news-blue.yaml
git add clouds/gcp/k8s/kube-news-blue.yaml
git commit -m "blue-green: switch traffic to green (GCP)"
git push
# ArgoCD aplica em ~3 min
```

## CI/CD

O pipeline GitHub Actions existente (`docker build → push`) não muda.
Para promover no GCP, atualize `clouds/gcp/k8s/kube-news-green.yaml` com o novo tag e `clouds/gcp/k8s/kube-news-blue.yaml` com `version: green` — o ArgoCD GCP aplica automaticamente.

## Contexts kubectl

```bash
# Azure AKS (existente)
kubectl config use-context AKSCLAUDECODE

# GCP GKE (novo — nome gerado pelo gcloud)
kubectl config use-context gke_<PROJECT_ID>_us-central1_kube-news-gke
```
