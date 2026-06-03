# ArgoCD — GitOps CI/CD

Este documento descreve como o ArgoCD está integrado ao projeto kube-news para entrega contínua via GitOps no Azure AKS.

---

## Visão geral

O pipeline segue o modelo **GitOps**: o repositório GitHub é a fonte da verdade. Nenhum `kubectl apply` é executado manualmente pelo pipeline — o ArgoCD detecta mudanças no branch `main` e sincroniza o cluster automaticamente.

```
git tag v1.2.3
      │
      ▼
GitHub Actions CI          → build + push da imagem Docker
      │
      ▼
GitHub Actions CD          → atualiza os manifests em k8s/ e commita
      │
      ▼
ArgoCD detecta o commit    → kubectl apply automático no AKS
```

---

## Acesso ao ArgoCD

| Item | Valor |
|---|---|
| UI | `http://20.213.174.138` |
| Namespace | `argocd` |
| Application | `kube-news` |

As credenciais iniciais do ArgoCD ficam no Secret `argocd-initial-admin-secret` no namespace `argocd`. Para recuperar:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

---

## Application do ArgoCD

Arquivo: `argocd/argocd-app.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-news
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/jeffersonsantos-sp/kube-NEWS-CLAUDE-CODE-EVENTO.git
    targetRevision: main
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-news
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### O que cada campo faz

| Campo | Valor | Efeito |
|---|---|---|
| `targetRevision` | `main` | Monitora o branch main |
| `path` | `k8s` | Observa apenas os arquivos diretamente em `k8s/` (não recursivo) |
| `automated.prune` | `true` | Remove do cluster recursos deletados do git |
| `automated.selfHeal` | `true` | Reverte mudanças manuais feitas via kubectl |
| `CreateNamespace` | `true` | Cria o namespace `kube-news` se não existir |
| `finalizers` | `resources-finalizer` | Ao deletar a Application, remove também os recursos do cluster |

> O diretório `k8s/monitoring/` **não** é gerenciado pelo ArgoCD pois o ArgoCD não faz recursão em subdiretórios por padrão. A stack de observabilidade é gerenciada via Helm separadamente.

---

## Recursos gerenciados

O ArgoCD gerencia todos os arquivos YAML diretamente em `k8s/`:

| Arquivo | Recursos |
|---|---|
| `kube-news-blue.yaml` | Namespace, Secret, ConfigMap, PVC, postgres Deployment+Service, kube-news-blue Deployment, Service kube-news |
| `kube-news-green.yaml` | kube-news-green Deployment, Service kube-news-preview |
| `ingress.yaml` | Ingress kube-news (NGINX, domínio `jfs-devops.shop`) |
| `cert-issuer.yaml` | ClusterIssuers `letsencrypt-staging` e `letsencrypt-prod` |

---

## Fluxo CI/CD detalhado

### 1. CI — Build e Push (`.github/workflows/ci.yml`)

**Gatilho:** push de tag no formato `v*.*.*` (ex: `v1.2.3`)

**Passos:**
1. Checkout do código
2. `npm ci` — instala e valida dependências
3. Login no Docker Hub (secrets `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN`)
4. Build e push da imagem `updateinformatica/claude-devops:<tag>`
5. Salva a tag em artefato para o workflow CD consumir

### 2. CD — Atualização dos Manifests (`.github/workflows/cd.yml`)

**Gatilho:** conclusão bem-sucedida do workflow CI

**Passos:**
1. Checkout do repositório
2. Download do artefato com a image tag gerada pelo CI
3. Atualiza a imagem em `k8s/kube-news-green.yaml`:
   ```bash
   sed -i "s|image: updateinformatica/claude-devops:.*|image: updateinformatica/claude-devops:${IMAGE_TAG}|" k8s/kube-news-green.yaml
   ```
4. Garante que o selector do Service aponta para `green` em `k8s/kube-news-blue.yaml`:
   ```bash
   sed -i 's/^    version: blue$/    version: green/' k8s/kube-news-blue.yaml
   ```
5. Commita e faz push das alterações

**A partir daqui o ArgoCD assume:** detecta o novo commit (~3 min de polling) e aplica os manifests no cluster.

---

## Secrets necessários no GitHub

Acesse: `Settings → Secrets and variables → Actions`

| Secret | Descrição | Como obter |
|---|---|---|
| `DOCKERHUB_USERNAME` | Usuário do Docker Hub | Sua conta em hub.docker.com |
| `DOCKERHUB_TOKEN` | Token de acesso do Docker Hub | Docker Hub → Account Settings → Security → New Access Token |

> O secret `KUBECONFIG` **não é mais necessário** — o deploy é feito pelo ArgoCD, não pelo pipeline.

---

## Estratégia Blue-Green com GitOps

O Blue-Green é controlado inteiramente pelo selector `version:` no Service `kube-news` dentro de `k8s/kube-news-blue.yaml`.

```
                   ┌─────────────────────┐
  Internet ──────► │  Ingress NGINX      │
                   └──────────┬──────────┘
                              │
                   ┌──────────▼──────────┐
                   │  Service kube-news  │
                   │  selector:          │
                   │    version: green ◄─┼── CD atualiza aqui
                   └──────────┬──────────┘
                              │
              ┌───────────────┴──────────────┐
              │                              │
   ┌──────────▼──────────┐      ┌────────────▼────────┐
   │  kube-news-blue     │      │  kube-news-green     │
   │  image: :1.0        │      │  image: :v1.2.3      │ ◄── nova versão
   │  (rollback)         │      │  (ativo)             │
   └─────────────────────┘      └─────────────────────┘
```

### Deploy normal

```bash
git tag v1.2.3
git push origin v1.2.3
# CI/CD executa automaticamente
# ArgoCD sincroniza em ~3 min
```

### Rollback para blue

```bash
# Editar k8s/kube-news-blue.yaml: selector version: green → version: blue
git add k8s/kube-news-blue.yaml
git commit -m "rollback: switch traffic to blue"
git push
# ArgoCD aplica em ~3 min
```

---

## Bootstrap — Aplicar a Application do ArgoCD

O arquivo `argocd/argocd-app.yaml` é aplicado **uma única vez** para registrar a aplicação no ArgoCD. Após isso, o próprio ArgoCD gerencia tudo.

```bash
kubectl apply -f argocd/argocd-app.yaml
```

Para verificar o status:

```bash
kubectl get application kube-news -n argocd
```

---

## Verificação e troubleshooting

### Verificar status da Application

```bash
kubectl get application kube-news -n argocd -o wide
```

Campos relevantes: `SYNC STATUS` (Synced/OutOfSync) e `HEALTH STATUS` (Healthy/Degraded).

### Forçar sync manual

```bash
kubectl patch application kube-news -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

Ou pela UI: selecionar a Application → **Sync** → **Synchronize**.

### Ver eventos de sync

```bash
kubectl describe application kube-news -n argocd | tail -30
```

### Pods do ArgoCD

```bash
kubectl get pods -n argocd
```

| Pod | Função |
|---|---|
| `argocd-server` | API + UI web |
| `argocd-application-controller` | Reconcilia estado desejado (git) vs atual (cluster) |
| `argocd-repo-server` | Clona e lê o repositório git |
| `argocd-dex-server` | Autenticação SSO |
| `argocd-redis` | Cache interno |

> O `argocd-applicationset-controller` pode estar em CrashLoopBackOff sem impacto — ele é usado apenas para cenários multi-cluster com ApplicationSets, que não está em uso neste projeto.
