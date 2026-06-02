# Guia de Deploy — kube-news

Este documento descreve o processo oficial de build, deploy e rollback da aplicação **kube-news** no Azure AKS. Leia antes de qualquer alteração em produção.

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

## O que NÃO fazer

| Acao | Risco |
|---|---|
| `kubectl apply -f k8s/kube-news-green.yaml` manualmente | Substitui o manifesto sem passar pelo pipeline — histórico perdido |
| `kubectl set image` direto no cluster | Drift entre cluster e repositório git — ArgoCD não conseguirá reconciliar no futuro |
| Push de tag sem testar localmente | CI vai buildar e CD vai deployar automaticamente — não há gate de aprovação no CI |
| Editar `kube-news-green.yaml` manualmente sem nova tag | O manifesto diverge da imagem rodando no cluster |

---

## Estrutura dos arquivos de deploy

```
k8s/
  kube-news-blue.yaml    # Stack completa: namespace, secret, configmap, PVC,
                         # postgres, deployment blue, Service (LoadBalancer)
  kube-news-green.yaml   # Deployment green + Service preview (ClusterIP :8080)
                         # — tag da imagem atualizada automaticamente pelo CD

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
         kubectl apply -f k8s/kube-news-green.yaml
         kubectl rollout status (aguarda pods Ready)
              │
              ▼ (todos os pods green Ready)
         kubectl patch service → version: green
              │
              ▼
         Produção servindo a nova versão
         Blue mantido em standby para rollback
```
