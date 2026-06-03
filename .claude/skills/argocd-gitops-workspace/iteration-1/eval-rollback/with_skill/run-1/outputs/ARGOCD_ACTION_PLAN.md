# Plano de Ação ArgoCD — 2026-06-03 21:05

> Gerado automaticamente. Nenhuma ação foi executada.
> Revise cada passo antes de executar.

## Resumo

| # | Ação | Risco | Tipo |
|---|---|---|---|
| 1 | Restaurar conectividade com o cluster AKS | Baixo | REVERSÍVEL |
| 2 | Verificar estado atual do ArgoCD e pods kube-news | Baixo | READ-ONLY |
| 3 | Rollback: redirecionar tráfego para slot green (v1.2.5) via git | Médio | REVERSÍVEL |
| 4 | Aguardar sincronização do ArgoCD | Baixo | REVERSÍVEL |
| 5 | Validar aplicação em produção | Baixo | READ-ONLY |

---

## Passo 1 — Restaurar conectividade com o cluster AKS `[PRÉ-REQUISITO]`

**Objetivo:** Permitir que os comandos kubectl se conectem ao AKS antes de qualquer ação.
**Risco:** Baixo — operação de configuração local, sem impacto no cluster.
**Como executar:**

```bash
# Opção A — Se o cluster ainda existe no Azure, renovar o KUBECONFIG:
az login
az aks get-credentials \
  --resource-group <resource-group> \
  --name <aks-cluster-name> \
  --overwrite-existing

# Verificar conectividade:
kubectl cluster-info
kubectl get nodes
```

**Resultado esperado:** `kubectl cluster-info` retorna a URL do API server e `kubectl get nodes` lista os nós do cluster.

---

## Passo 2 — Verificar estado atual do ArgoCD e pods `[READ-ONLY]`

**Objetivo:** Confirmar que o ArgoCD está operacional e identificar o estado real atual antes do rollback.
**Risco:** Baixo — apenas leitura.
**Como executar:**

```bash
# Estado da Application kube-news:
kubectl get application kube-news -n argocd -o wide

# Pods do ArgoCD:
kubectl get pods -n argocd

# Pods em kube-news (verificar qual slot está com problemas):
kubectl get pods -n kube-news -o wide

# Imagens em execução (confirmar versão ativa no cluster):
kubectl get deployments -n kube-news -o wide

# Selector ativo do Service:
kubectl get svc kube-news -n kube-news -o jsonpath='{.spec.selector}'
```

**Resultado esperado:**
- ArgoCD: todos os pods em `Running`
- Application: `SYNC: Synced`, mas possivelmente `HEALTH: Degraded` se v1.2.6 está com problemas
- kube-news-blue pods: possivelmente em `CrashLoopBackOff` ou `Error` (indicando problema com v1.2.6)

---

## Passo 3 — Rollback: redirecionar tráfego para slot green (v1.2.5) `[REVERSÍVEL]`

**Objetivo:** Desviar o tráfego de produção do slot blue (v1.2.6 — com problema) para o slot green (v1.2.5 — versão estável anterior), usando o mecanismo GitOps via commit.
**Risco:** Médio — altera o tráfego de produção, mas é totalmente reversível.

**Como executar:**

```bash
# Editar k8s/kube-news-blue.yaml:
# Localizar as linhas do selector do Service kube-news (ao final do arquivo):
#   selector:
#     app: kube-news
#     version: blue   ← ALTERAR PARA: version: green

# Após editar, commitar e fazer push:
git add k8s/kube-news-blue.yaml
git commit -m "rollback: switch traffic to green (v1.2.5)"
git push origin main
```

**O que o ArgoCD fará automaticamente:**
1. Detectará o novo commit em ~3 minutos (polling do branch main)
2. Aplicará o `kubectl apply` no Service `kube-news` atualizando o selector para `version: green`
3. O tráfego será imediatamente desviado para os pods do deployment `kube-news-green` (imagem `v1.2.5`)

**Resultado esperado:** Após o sync do ArgoCD, `kubectl get svc kube-news -n kube-news -o jsonpath='{.spec.selector}'` retorna `{"app":"kube-news","version":"green"}`.

> **Nota:** O deployment `kube-news-green` com imagem `v1.2.5` já está definido em `k8s/kube-news-green.yaml`. O ArgoCD já deve tê-lo aplicado. Os pods green devem estar em `Running`.

---

## Passo 4 — (Opcional) Forçar sync imediato no ArgoCD `[REVERSÍVEL]`

**Objetivo:** Evitar aguardar o polling padrão de ~3 minutos do ArgoCD.
**Risco:** Baixo — apenas aciona uma operação que o ArgoCD faria de qualquer forma.
**Como executar:**

```bash
# Via kubectl (patch de operação de sync):
kubectl patch application kube-news -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Via UI:
# Abrir http://20.213.174.138 → Application kube-news → Sync → Synchronize
```

**Resultado esperado:** `kubectl get application kube-news -n argocd` mostra `SYNC STATUS: Synced` com o SHA do commit de rollback.

---

## Passo 5 — Validação após rollback `[READ-ONLY]`

**Objetivo:** Confirmar que o rollback foi aplicado com sucesso e a aplicação está funcional.
**Risco:** Baixo — apenas leitura e teste de acesso HTTP.
**Como executar:**

```bash
# 1. Verificar Application ArgoCD:
kubectl get application kube-news -n argocd
# Esperado: SYNC: Synced, HEALTH: Healthy

# 2. Verificar pods kube-news:
kubectl get pods -n kube-news -o wide
# Esperado: pods kube-news-green-* em Running (2/2)

# 3. Verificar selector do Service:
kubectl get svc kube-news -n kube-news -o jsonpath='{.spec.selector}'
# Esperado: {"app":"kube-news","version":"green"}

# 4. Verificar imagem em execução nos pods green:
kubectl describe deployment kube-news-green -n kube-news | grep Image
# Esperado: updateinformatica/claude-devops:v1.2.5

# 5. Verificar acesso à aplicação:
curl -s -o /dev/null -w "%{http_code}" https://jfs-devops.shop/health
# Esperado: 200
```

---

## Validação após execução

- [ ] `kubectl get application kube-news -n argocd` → SYNC: Synced, HEALTH: Healthy
- [ ] `kubectl get pods -n kube-news` → pods `kube-news-green-*` em Running
- [ ] `kubectl get svc kube-news -n kube-news -o jsonpath='{.spec.selector}'` → `version: green`
- [ ] `kubectl describe deployment kube-news-green -n kube-news | grep Image` → `v1.2.5`
- [ ] Aplicação acessível em https://jfs-devops.shop

---

## Notas Pós-Rollback

### Investigação da falha em v1.2.6

Após estabilizar a produção com v1.2.5, investigar a causa do problema em v1.2.6:

```bash
# Logs dos pods blue com problema:
kubectl logs -l app=kube-news,version=blue -n kube-news --tail=100

# Eventos do deployment blue:
kubectl describe deployment kube-news-blue -n kube-news | tail -30

# Eventos gerais do namespace:
kubectl get events -n kube-news --sort-by=.lastTimestamp | tail -20
```

### Procedimento para novo deploy após correção

1. Corrigir o problema na aplicação
2. Criar nova tag (ex: `v1.2.7`): `git tag v1.2.7 && git push origin v1.2.7`
3. CI/CD atualiza `k8s/kube-news-green.yaml` com a nova imagem
4. Validar no slot green antes de promover
5. Atualizar selector do Service de `green` → `blue` via commit (ou vice-versa, conforme estratégia)
