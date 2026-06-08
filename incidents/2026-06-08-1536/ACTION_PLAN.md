# Plano de Ação — 2026-06-08 15:36

> **STATUS: PLANO EXECUTADO E CONCLUÍDO — 2026-06-08 15:56 BRT**
> Site restaurado. Todas as ações foram executadas e validadas.

---

## Resumo dos Passos

| # | Ação | Risco | Tipo | Status |
|---|---|---|---|---|
| 1 | Reiniciar nginx ingress controller | Baixo | REVERSÍVEL | ✅ EXECUTADO |
| 2 | Deletar pod zumbi `f6nxc` | Baixo | REVERSÍVEL | ✅ EXECUTADO |
| 3 | Corrigir health probe path para `/healthz` | Baixo | REVERSÍVEL | ✅ **EXECUTADO — RESOLVEU** |
| 4 | Forçar reconciliação via annotation (fallback) | Médio | REVERSÍVEL | ⏭ NÃO NECESSÁRIO |
| 5 | Validação final | — | VALIDAÇÃO | ✅ CONFIRMADO |

---

## Passo 1 — Reiniciar nginx ingress controller `[REVERSÍVEL]` ✅ EXECUTADO

**Objetivo:** Forçar o nginx ingress controller a re-registrar o Service LoadBalancer com o Azure Cloud Controller Manager.

**Comando executado:**
```bash
kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=120s
```

**Resultado:** Pod subiu com sucesso (`ingress-nginx-controller-549c768589-dbqpc`). O Azure LB reconciliou o backend pool, mas o site **ainda permaneceu inacessível** — a health probe continuou falhando porque o problema estava no path da probe, não no backend pool.

---

## Passo 2 — Deletar pod zumbi `[REVERSÍVEL]` ✅ EXECUTADO

**Objetivo:** Remover o pod `kube-news-green-b5f66df45-f6nxc` preso em `ContainerStatusUnknown` desde a rotação do nó.

**Comando executado:**
```bash
kubectl delete pod kube-news-green-b5f66df45-f6nxc -n kube-news --force --grace-period=0
```

**Resultado:** Pod removido com sucesso. Namespace `kube-news` voltou ao estado esperado com apenas 2 pods green Running.

---

## Passo 3 — Corrigir health probe path para `/healthz` `[REVERSÍVEL]` ✅ **EXECUTADO — RESOLVEU O INCIDENTE**

**Objetivo:** Corrigir o path da health probe HTTP do Azure LB de `/` (retorna 404 no nginx) para `/healthz` (retorna 200).

**Diagnóstico que levou a este passo:**
```bash
# Verificação do que a probe retorna:
kubectl exec nginx-pod -- curl -o /dev/null -w "%{http_code}" http://localhost/
→ 404   ← FALHA NA PROBE

kubectl exec nginx-pod -- curl -o /dev/null -w "%{http_code}" http://localhost/healthz
→ 200   ← PROBE PASSARIA

# Probe configurada no Azure LB:
az network lb probe show ... --name a1dd63d8e6fd74ed092a525f3f2af6c8-TCP-80
→ { "protocol": "Http", "port": 32423, "requestPath": "/" }
```

**Comando executado:**
```bash
kubectl annotate svc ingress-nginx-controller -n ingress-nginx \
  "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path=/healthz" \
  --overwrite
```

**Verificação pós-anotação:**
```bash
az network lb probe show ... → { "requestPath": "/healthz" }  ✓
```

**Resultado:**
- Azure LB atualizou a probe para `GET /healthz`
- Nginx passou a retornar HTTP 200
- Azure LB marcou backends como saudáveis
- **Site restaurado em ~30 segundos** — `HTTP_CODE:200 TIME:0.802070s`

**Por que aconteceu:** No AKS 1.34+, o campo `appProtocol: http` nos ports do Service tem precedência sobre a annotation `azure-load-balancer-health-probe-protocol: tcp`. Antes da rotação do nó (versão anterior do AKS), o comportamento era diferente. A annotation de path `/healthz` resolve independentemente do protocolo.

---

## Passo 4 — Forçar reconciliação via annotation (fallback) ⏭ NÃO EXECUTADO

**Motivo:** O Passo 3 resolveu o incidente. Este passo não foi necessário.

**Referência (caso necessário no futuro):**
```bash
kubectl annotate svc ingress-nginx-controller -n ingress-nginx \
  service.beta.kubernetes.io/azure-load-balancer-force-reconcile="$(date +%s)" \
  --overwrite
```

---

## Passo 5 — Validação Final ✅ CONFIRMADO

```bash
# HTTP
curl -o /dev/null -w "HTTP_CODE:%{http_code}" http://jfs-devops.shop
→ HTTP_CODE:200  ✓

# HTTPS
curl -o /dev/null -w "HTTP_CODE:%{http_code}" https://jfs-devops.shop
→ HTTP_CODE:200  ✓

# Pods kube-news
kubectl get pods -n kube-news
NAME                              READY   STATUS    RESTARTS
kube-news-blue-75c4f47878-mqcv9   1/1     Running   7
kube-news-blue-75c4f47878-zfpg9   1/1     Running   7
kube-news-green-b5f66df45-4hdkf   1/1     Running   6
kube-news-green-b5f66df45-htbt6   1/1     Running   3
postgres-679866d69f-gk7nm         1/1     Running   0

# nginx ingress controller
kubectl get pods -n ingress-nginx
NAME                                        READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-549c768589-dbqpc   1/1     Running   0          20m
```

**Checklist de sucesso:**
- [x] `ingress-nginx-controller` em `Running 1/1`
- [x] Pod zumbi `f6nxc` removido do namespace `kube-news`
- [x] `curl http://jfs-devops.shop` → `HTTP_CODE:200`
- [x] `curl https://jfs-devops.shop` → `HTTP_CODE:200`
- [x] Site acessível via browser

---

## Ações de Hardening Pós-Incidente

| Ação | Status | Descrição |
|---|---|---|
| CLAUDE.md atualizado | ✅ FEITO | `helm upgrade ingress-nginx` agora inclui `--set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz` |
| Alerta LB probe failure | ⬜ PENDENTE | Criar alerta Grafana/Prometheus para detectar Azure LB sem backends saudáveis |
| Helm values file | ⬜ PENDENTE | Criar `k8s/values-ingress-nginx.yaml` com todas as annotations permanentes para evitar divergência em upgrades futuros |
