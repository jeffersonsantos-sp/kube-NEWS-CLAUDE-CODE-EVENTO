# Plano de Ação ArgoCD — 2026-06-03 21:05

> Gerado automaticamente. Nenhuma ação foi executada.
> Revise cada passo antes de executar.

## Resumo

| # | Ação | Risco | Tipo |
|---|---|---|---|
| 1 | Recriar e fazer push da tag v2.0.0 no GitHub | Baixo | REVERSÍVEL |
| 2 | Verificar execução dos workflows CI e CD no GitHub Actions | Baixo | SEM EFEITO COLATERAL |
| 3 | Verificar conectividade com o cluster AKS | Baixo | SEM EFEITO COLATERAL |
| 4 | Após cluster disponível: verificar status do ArgoCD | Baixo | SEM EFEITO COLATERAL |
| 5 | Se ArgoCD OutOfSync: forçar sync | Baixo | REVERSÍVEL |

---

## Passo 1 — Recriar e fazer push da tag v2.0.0 `[REVERSÍVEL]`

**Objetivo:** Garantir que a tag v2.0.0 existe no GitHub para disparar o workflow CI.

**Risco:** Baixo — criar uma tag em um commit existente não altera código.

**Por que é necessário:** A tag v2.0.0 não aparece nos tags locais (`git tag` mostra apenas v1.0.2, v1.2.3, v1.2.4, v1.2.5, v1.2.6). Se a tag não chegou ao GitHub, o workflow CI (`on: push: tags: v*.*.*`) nunca foi disparado.

**Como verificar antes de executar:**
```bash
# Verificar se a tag existe localmente
git tag | grep v2.0.0

# Verificar se a tag existe no remote
git ls-remote --tags origin | grep v2.0.0
```

**Se a tag não existe localmente:**
```bash
# Criar a tag apontando para o commit desejado (geralmente HEAD ou o commit da versão)
git tag v2.0.0

# Fazer push da tag para o GitHub
git push origin v2.0.0
```

**Se a tag existe localmente mas não no remote:**
```bash
git push origin v2.0.0
```

**Resultado esperado:** A tag v2.0.0 aparece em `git ls-remote --tags origin | grep v2.0.0` e o workflow CI é acionado no GitHub Actions.

---

## Passo 2 — Verificar workflows CI e CD no GitHub Actions `[SEM EFEITO COLATERAL]`

**Objetivo:** Confirmar se o CI buildou e fez push da imagem, e se o CD atualizou os manifests.

**Risco:** Zero — apenas visualização.

**Como verificar:**
```bash
# Via GitHub CLI
gh run list --workflow=ci.yml --limit=5
gh run list --workflow=cd.yml --limit=5
```

Ou acessar diretamente: https://github.com/jeffersonsantos-sp/kube-NEWS-CLAUDE-CODE-EVENTO/actions

**O que verificar:**
- O workflow `CI` para a tag `v2.0.0` deve estar `completed: success`
- O workflow `CD` subsequente deve estar `completed: success`
- Após CD: deve existir um commit `ci: deploy green image v2.0.0` no branch `main`

**Resultado esperado:** Após CI+CD com sucesso:
```bash
git pull origin main
git log --oneline -3
# deve mostrar: ci: deploy green image v2.0.0
```

---

## Passo 3 — Verificar conectividade com o cluster AKS `[SEM EFEITO COLATERAL]`

**Objetivo:** Reestabelecer acesso kubectl ao cluster antes de verificar o estado do ArgoCD.

**Risco:** Zero — apenas diagnóstico.

**Sintoma observado:**
```
Unable to connect to the server: dial tcp: lookup aks-kube-news-ka8p6h1z.hcp.australiaeast.azmk8s.io
on 192.168.65.7:53: no such host
```

**Possível causa:** O cluster AKS está desalocado (stopped state) — comum em laboratórios para economizar créditos Azure.

**Como verificar e corrigir:**
```bash
# Verificar estado do cluster no Azure
az aks show --resource-group <seu-resource-group> --name <nome-do-cluster> --query "powerState.code" -o tsv

# Se o cluster estiver Stopped, iniciar:
az aks start --resource-group <seu-resource-group> --name <nome-do-cluster>

# Após iniciar, atualizar KUBECONFIG:
az aks get-credentials --resource-group <seu-resource-group> --name <nome-do-cluster> --overwrite-existing

# Verificar acesso:
kubectl cluster-info
kubectl get nodes
```

**Resultado esperado:** `kubectl cluster-info` retorna o endpoint do API server sem erros.

---

## Passo 4 — Verificar status do ArgoCD após reconexão `[SEM EFEITO COLATERAL]`

**Objetivo:** Confirmar se o ArgoCD está saudável e se processou o commit do CD.

**Risco:** Zero — apenas leitura.

**Como executar:**
```bash
# Verificar pods do ArgoCD
kubectl get pods -n argocd

# Verificar status da Application
kubectl get application kube-news -n argocd -o wide

# Ver detalhes do sync (revision sincronizada, erros)
kubectl describe application kube-news -n argocd | tail -40
```

**Resultado esperado:**
- Todos os pods em `Running`
- `SYNC STATUS: Synced`
- `HEALTH STATUS: Healthy`
- `STATUS.SYNC.REVISION` = SHA do commit `ci: deploy green image v2.0.0`

**Se ArgoCD mostrar OutOfSync:** prosseguir para Passo 5.

---

## Passo 5 — Forçar sync do ArgoCD `[REVERSÍVEL]`

**Objetivo:** Forçar o ArgoCD a sincronizar imediatamente sem aguardar o polling de ~3 minutos.

**Risco:** Baixo — apenas aplica os manifests que já estão no git (idempotente).

**Pré-requisito:** O commit `ci: deploy green image v2.0.0` deve existir no branch `main` do GitHub antes de forçar o sync.

**Como executar:**
```bash
# Via kubectl patch (força sync para HEAD do branch main)
kubectl patch application kube-news -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Verificar andamento
kubectl get application kube-news -n argocd -w
```

Ou via UI ArgoCD:
1. Acessar http://20.213.174.138
2. Selecionar Application `kube-news`
3. Clicar em **Sync** → **Synchronize**

**Resultado esperado:** ArgoCD aplica os manifests com `image: updateinformatica/claude-devops:v2.0.0` no Deployment `kube-news-green` e o Service `kube-news` com `selector: version: green`. Pods do slot green sobem com a nova imagem.

---

## Validação após execução

- [ ] `git ls-remote --tags origin | grep v2.0.0` → tag v2.0.0 presente no GitHub
- [ ] GitHub Actions: workflow CI para v2.0.0 = `success`
- [ ] GitHub Actions: workflow CD para v2.0.0 = `success`
- [ ] `git log --oneline -3` → commit `ci: deploy green image v2.0.0` presente
- [ ] `kubectl get application kube-news -n argocd` → SYNC: Synced, HEALTH: Healthy
- [ ] `kubectl get pods -n kube-news` → todos os pods Running, incluindo pods `kube-news-green` com imagem v2.0.0
- [ ] `kubectl get svc kube-news -n kube-news -o jsonpath='{.spec.selector}'` → `{"app":"kube-news","version":"green"}`
- [ ] Aplicação acessível em https://jfs-devops.shop com a nova versão

---

## Observação sobre Blue-Green e v2.0.0

Quando o CD executar com sucesso para v2.0.0:

1. `k8s/kube-news-green.yaml` será atualizado para `image: updateinformatica/claude-devops:v2.0.0`
2. `k8s/kube-news-blue.yaml` terá o selector do Service alterado para `version: green`
3. O ArgoCD aplicará ambos os manifests no cluster
4. O tráfego passará automaticamente para o slot green (v2.0.0)
5. O slot blue (v1.2.6) permanece como fallback para rollback

Para rollback caso v2.0.0 apresente problemas:
```bash
# Editar k8s/kube-news-blue.yaml: selector version: green → version: blue
git add k8s/kube-news-blue.yaml
git commit -m "rollback: switch traffic to blue v1.2.6"
git push
# ArgoCD sincroniza em ~3 min
```
