# Plano de Ação ArgoCD — 2026-06-03 21:05

> Gerado automaticamente. Nenhuma ação foi executada.
> Revise cada passo antes de executar.

---

## Resumo

| # | Ação | Risco | Tipo |
|---|---|---|---|
| 1 | Push dos commits locais para o GitHub | Baixo | REVERSÍVEL |
| 2 | Verificar se ArgoCD sincronizou após o push | Nenhum | OBSERVAÇÃO |
| 3 | Investigar CrashLoopBackOff do applicationset-controller | Baixo | REVERSÍVEL |

---

## Passo 1 — Push dos commits locais para o GitHub `[REVERSÍVEL]`

**Objetivo:** Enviar os 3 commits locais ao repositório remoto para que o ArgoCD possa detectá-los e aplicar as mudanças ao cluster (principalmente a atualização da imagem blue de `1.0` para `v1.2.6`).

**Risco:** Baixo — o ArgoCD com `selfHeal: true` e `prune: true` vai reconciliar o estado do cluster com o git. A mudança de imagem do blue não afeta o tráfego atual (slot ativo é green).

**Como executar:**
```bash
# Verificar o que será enviado antes do push
git log --oneline origin/main..HEAD

# Enviar os commits locais
git push origin main
```

**Resultado esperado:** Após o push, o ArgoCD detectará a nova revisão em até ~3 minutos (polling automático) e aplicará os manifests. O Deployment `kube-news-blue` será atualizado de `1.0` para `v1.2.6`.

---

## Passo 2 — Verificar sync após o push `[OBSERVAÇÃO]`

**Objetivo:** Confirmar que o ArgoCD sincronizou os novos commits e que o Deployment blue foi atualizado.

**Risco:** Nenhum — apenas observação.

**Como executar:**
```bash
# Verificar status da Application
kubectl get application kube-news -n argocd

# Verificar a revisão sincronizada (deve bater com o novo HEAD)
kubectl get application kube-news -n argocd -o jsonpath='{.status.sync.revision}'

# Verificar imagens dos deployments
kubectl get deployments -n kube-news -o wide

# Se quiser forçar sync imediatamente (sem esperar polling):
kubectl patch application kube-news -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

**Resultado esperado:**
```
NAME        SYNC STATUS   HEALTH STATUS
kube-news   Synced        Healthy
```
E os deployments devem mostrar:
```
kube-news-blue    2/2   updateinformatica/claude-devops:v1.2.6
kube-news-green   2/2   updateinformatica/claude-devops:v1.2.6
```

---

## Passo 3 — Investigar argocd-applicationset-controller `[REVERSÍVEL]`

**Objetivo:** Diagnosticar e corrigir o CrashLoopBackOff do `argocd-applicationset-controller`. Embora não tenha impacto imediato (não há ApplicationSets no projeto), o pod em loop pode consumir recursos desnecessários e gerar ruído nos logs.

**Risco:** Baixo — diagnóstico não modifica nada; reinicialização é reversível.

**Como executar:**
```bash
# 1. Verificar os logs para entender o motivo do crash
kubectl logs argocd-applicationset-controller-6d9bc95cc7-rgkdp -n argocd --tail=50

# 2. Verificar eventos do pod
kubectl describe pod argocd-applicationset-controller-6d9bc95cc7-rgkdp -n argocd

# 3. Se for problema de RBAC ou configuração resolvível, reiniciar o pod:
kubectl rollout restart deployment argocd-applicationset-controller -n argocd
```

**Resultado esperado:** Pod em estado `Running` sem reinicializações. Se o problema persistir, verificar compatibilidade de versão do ArgoCD com o cluster.

---

## Validação após execução

- [ ] `kubectl get application kube-news -n argocd` → SYNC: Synced, HEALTH: Healthy
- [ ] `kubectl get pods -n kube-news` → todos os pods Running
- [ ] `kubectl get deployments -n kube-news -o wide` → kube-news-blue com imagem `v1.2.6`
- [ ] `kubectl get svc kube-news -n kube-news -o jsonpath='{.spec.selector}'` → selector `version: green` (tráfego continua no green)
- [ ] Aplicação acessível em https://jfs-devops.shop
- [ ] `kubectl get pods -n argocd` → argocd-applicationset-controller em Running

---

## Contexto de decisão: Push imediato ou aguardar?

O commit mais recente local é **"Atualização da imagem blue v1.2.6"** — isso atualiza a imagem do Deployment blue de `1.0` para `v1.2.6`, alinhando ambos os slots com a mesma versão da aplicação.

Considerando que:
- O tráfego está no slot **green** (v1.2.6) — não há risco de interrupção
- O Deployment blue com imagem `1.0` está Running mas não recebe tráfego
- O push apenas atualizará o blue para `v1.2.6`, melhorando a consistência

**Recomendação:** Executar o push é seguro e recomendado para manter os dois slots na mesma versão e garantir que o git local e remoto estejam sincronizados.
