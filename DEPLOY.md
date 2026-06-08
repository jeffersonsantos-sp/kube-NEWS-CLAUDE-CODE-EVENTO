# Guia de Deploy — kube-news

Este documento descreve o processo oficial de build, deploy e rollback da aplicação **kube-news** no Azure AKS. Leia antes de qualquer alteração em produção.

> **Status do pipeline:** funcionando em produção desde 2026-06-02. CI + CD validados end-to-end — build, push Docker Hub, atualização de manifesto, deploy green no AKS e troca de tráfego.

---

## Visão geral

O pipeline usa **GitHub Actions** com dois arquivos separados:

| Arquivo | Responsabilidade | Gatilho |
|---|---|---|
| `.github/workflows/ci.yml` | Build + push da imagem Docker | Push de tag semântica `v*.*.*` |
| `.github/workflows/cd.yml` | Deploy no AKS + troca de tráfego | CI finalizado com sucesso |

O deploy segue o modelo **Blue-Green automatizado**:

- **Blue** — slot estável (versão anterior, mantida para rollback imediato)
- **Green** — slot de deploy (sempre recebe a nova versão)
- O tráfego de produção é controlado pelo `selector.version` do Service `kube-news`

---

## Como fazer um novo deploy

### Pré-requisitos

- Acesso de escrita ao repositório GitHub
- Imagem local testada (`docker compose up` funcional)

### Passo a passo

**1. Garanta que o código está na branch `main` e atualizado**

```bash
git checkout main
git pull
```

**2. Crie e envie a tag semântica**

```bash
git tag v1.2.3
git push --tags
```

A tag dispara automaticamente o CI. Nenhuma outra ação é necessária.

**3. Acompanhe o pipeline**

Acesse **Actions** no repositório GitHub e monitore os jobs:

```
CI  → build-push   (build + push da imagem)
CD  → deploy       (atualiza manifesto, aplica no AKS, troca tráfego)
```

O CD aplica a nova versão no slot **green** e só troca o tráfego após confirmar que todos os pods estão `Ready` (`kubectl rollout status`).

**4. Verifique o deploy**

```bash
# Confirma qual slot está ativo
kubectl get service kube-news -n kube-news -o jsonpath='{.spec.selector.version}'

# Confirma pods green rodando
kubectl get pods -n kube-news -l version=green
```

---

## Convenção de versão (Semantic Versioning)

Use o formato `vMAJOR.MINOR.PATCH`:

| Tipo de mudança | Exemplo | Quando usar |
|---|---|---|
| Correção de bug | `v1.0.1` | Fix sem alteração de comportamento |
| Nova funcionalidade | `v1.1.0` | Feature nova, compatível com anterior |
| Quebra de compatibilidade | `v2.0.0` | Mudança estrutural ou breaking change |

A tag vira exatamente a tag da imagem Docker. Ex: `git tag v1.2.3` gera `updateinformatica/claude-devops:v1.2.3`.

---

## Rollback

Se o deploy green apresentar problemas após a troca de tráfego, o rollback é imediato — blue ainda está rodando.

```bash
kubectl patch service kube-news -n kube-news \
  -p '{"spec":{"selector":{"app":"kube-news","version":"blue"}}}'
```

Confirme:

```bash
kubectl get service kube-news -n kube-news -o jsonpath='{.spec.selector.version}'
# Esperado: blue
```

Nenhum redeploy necessário. Blue continua rodando com a versão anterior.

---

## Configuração inicial (apenas na primeira vez)

### Secrets no GitHub

Acesse **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Como obter |
|---|---|
| `DOCKERHUB_USERNAME` | Seu usuário no Docker Hub (`updateinformatica`) |
| `DOCKERHUB_TOKEN` | Docker Hub → Account Settings → Security → New Access Token |
| `KUBECONFIG` | Execute na sua máquina: `cat ~/.kube/config \| base64 -w 0` |

### Environment de produção

O CD requer o environment `production` configurado no GitHub.

Acesse **Settings → Environments → New environment**, nomeie `production`.

Opcionalmente adicione **Required reviewers** para exigir aprovação manual antes de qualquer deploy em produção.

---

## Build local vs build pelo pipeline

São dois fluxos com propósitos distintos.

### Build local — para desenvolvimento e testes

Usa `docker compose` ou `docker build` direto. **Não chega ao AKS.**

```bash
# Testar a aplicação localmente
docker compose up --build

# Validar a imagem antes de criar a tag
docker build -t updateinformatica/claude-devops:v1.2.3 .
docker run -p 8080:8080 updateinformatica/claude-devops:v1.2.3
```

### Build via GitHub Actions — para produção

É o único fluxo que atualiza o AKS. Após validar localmente, crie a tag:

```bash
git add .
git commit -m "sua mudança"
git push

git tag v1.2.3
git push --tags   # dispara CI → CD automaticamente
```

### Por que não fazer docker push manual para produção

Se você fizer `docker push` manualmente sem criar uma tag git, **nada dispara o CD** — a imagem existe no Docker Hub mas o AKS não é atualizado e o manifesto `kube-news-green.yaml` fica desatualizado no repositório.

### Resumo

| Situação | Fluxo |
|---|---|
| Testar mudança localmente | `docker compose up --build` |
| Validar imagem antes de tagear | `docker build` + `docker run` local |
| Deployar em produção no AKS | `git tag vX.Y.Z && git push --tags` |
| Emergência com CI/CD quebrado | `docker build` + `docker push` + `kubectl apply` manual — documente o incidente |

**Regra:** tudo que vai para produção passa pela tag. Build local é só para validar antes de criá-la.

---

## Erros conhecidos e soluções

### `context deadline exceeded` ao conectar no Docker Hub

**Causa:** Os secrets `DOCKERHUB_USERNAME` ou `DOCKERHUB_TOKEN` não estão configurados no repositório. O login falha silenciosamente e o push tenta autenticar anonimamente até dar timeout.

**Solução:** Configure os secrets em **Settings → Secrets and variables → Actions**:

| Secret | Como obter |
|---|---|
| `DOCKERHUB_USERNAME` | Usuário no Docker Hub (`updateinformatica`) |
| `DOCKERHUB_TOKEN` | hub.docker.com → Account Settings → Security → New Access Token |

O CI valida a presença dos secrets antes do login e falha com mensagem clara se estiverem ausentes.

Após configurar, re-execute criando uma nova tag:

```bash
git tag v1.0.1
git push --tags
```

### `dial tcp [::1]:8080: connect: connection refused` no CD

**Causa:** O secret `KUBECONFIG` não está configurado ou foi gerado incorretamente. Quando está ausente ou vazio, o `kubectl` ignora o arquivo de configuração e tenta conectar no default local (`localhost:8080`) em vez do AKS.

**Solução:** Gere o kubeconfig correto na sua máquina e configure o secret:

```bash
# 1. Garante que está no contexto do AKS
kubectl config use-context AKSCLAUDECODE

# 2. Gera o base64 sem quebras de linha
cat ~/.kube/config | base64 -w 0
```

Cole o resultado em **Settings → Secrets and variables → Actions → `KUBECONFIG`** (crie se não existir, atualize se já existir com valor errado).

O CD agora valida o secret e testa a conectividade com `kubectl cluster-info` antes de tentar qualquer deploy, falhando com mensagem clara nos dois casos.

Após configurar, re-execute criando uma nova tag:

```bash
git tag v1.0.2
git push --tags
```

---

### Warning — Node.js 20 actions deprecated

**Causa:** As actions do GitHub (`actions/checkout`, `actions/setup-node`, `docker/login-action`) usavam Node.js 20, que será removido dos runners em setembro/2026.

**Solução:** Já corrigido nos workflows com a variável de ambiente:

```yaml
env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
```

Presente em `ci.yml` e `cd.yml`. Nenhuma ação manual necessária.

---

## O que NÃO fazer

| Acao | Risco |
|---|---|
| `kubectl apply -f clouds/azure/k8s/kube-news-green.yaml` manualmente | Substitui o manifesto sem passar pelo pipeline — histórico perdido |
| `kubectl set image` direto no cluster | Drift entre cluster e repositório git — ArgoCD não conseguirá reconciliar no futuro |
| Push de tag sem testar localmente | CI vai buildar e CD vai deployar automaticamente — não há gate de aprovação no CI |
| Editar `kube-news-green.yaml` manualmente sem nova tag | O manifesto diverge da imagem rodando no cluster |

---

## Estrutura dos arquivos de deploy

```
k8s/
  kube-news-blue.yaml    # Stack completa: namespace, secret, configmap, PVC,
                         # postgres, deployment blue, Service (ClusterIP)
  kube-news-green.yaml   # Deployment green + Service preview (ClusterIP :8080)
                         # — tag da imagem atualizada automaticamente pelo CD
  ingress.yaml           # Ingress NGINX: roteia HTTP/HTTPS para o Service kube-news
                         # TLS via cert-manager (letsencrypt-prod), ssl-redirect desativado
  cert-issuer.yaml       # ClusterIssuers letsencrypt-staging e letsencrypt-prod

.github/
  workflows/
    ci.yml               # Build + push da imagem Docker
    cd.yml               # Deploy AKS + troca de tráfego Blue→Green
```

---

## Visão do fluxo completo

```
Desenvolvedor
    │
    ├─ git tag v1.2.3
    └─ git push --tags
              │
              ▼
         [CI — ci.yml]
         npm ci (valida dependências)
         docker build
         docker push updateinformatica/claude-devops:v1.2.3
              │
              ▼ (CI com sucesso)
         [CD — cd.yml]
         Baixa tag do artefato CI
         Atualiza imagem em kube-news-green.yaml
         git commit + push (manifesto versionado)
         kubectl apply -f clouds/azure/k8s/kube-news-green.yaml
         kubectl rollout status (aguarda pods Ready)
              │
              ▼ (todos os pods green Ready)
         kubectl patch service → version: green
              │
              ▼
         Produção servindo a nova versão
         Blue mantido em standby para rollback

## Camada de rede (HTTP + HTTPS)

```
Internet
    │
    ▼
NGINX Ingress Controller  (LoadBalancer — IP: 20.53.187.114)
    │  porta 80  ──────────────────────────────────────────▶ http://jfs-devops.shop
    │  porta 443 (TLS — cert Let's Encrypt, auto-renovável) ▶ https://jfs-devops.shop
    │
    ▼
Service kube-news (ClusterIP)
    │  selector version: blue | green  (Blue-Green switch)
    ▼
Pods kube-news (porta 8080)
```

O tráfego entra pelo Ingress, que termina TLS e repassa ao Service interno. O mecanismo Blue-Green (selector no Service) continua funcionando normalmente — o Ingress não precisa saber qual slot está ativo.

### Helm releases da camada de rede

| Release | Namespace | Comando para atualizar |
|---|---|---|
| `ingress-nginx` | `ingress-nginx` | `helm upgrade ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx` |
| `cert-manager` | `cert-manager` | `helm upgrade cert-manager jetstack/cert-manager --namespace cert-manager --set crds.enabled=true` |

Certificado TLS armazenado no Secret `kube-news-tls` no namespace `kube-news`. cert-manager renova automaticamente ~30 dias antes do vencimento (validade: 90 dias).
