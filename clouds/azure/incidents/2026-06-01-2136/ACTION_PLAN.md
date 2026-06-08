# Plano de Ação — 2026-06-01 21:36

> **Status:** EXECUTADO — A correção foi aplicada automaticamente conforme instrução do usuário.

## Resumo dos Passos

| # | Ação | Risco | Tipo |
|---|---|---|---|
| 1 | Aplicar `k8s/kube-news-blue.yaml` no cluster | Baixo | REVERSÍVEL |

---

## Passo 1 — Deploy completo da aplicação `[REVERSÍVEL]`

**Objetivo:** Criar namespace, secrets, configmap, PVC, postgres e aplicação blue no cluster.

**Risco:** Baixo — cria recursos novos em namespace inexistente, sem impacto em outros namespaces.

**Comando:**
```bash
kubectl apply -f k8s/kube-news-blue.yaml
```

**Resultado esperado:**
```
namespace/kube-news created
secret/kube-news-secret created
configmap/kube-news-config created
persistentvolumeclaim/postgres-pvc created
deployment.apps/postgres created
service/postgres created
deployment.apps/kube-news-blue created
service/kube-news created
```

**Rollback:**
```bash
kubectl delete namespace kube-news
```

---

## Validação Final

Após aplicação, verificar:

```bash
# Pods em Running
kubectl get pods -n kube-news

# LoadBalancer com EXTERNAL-IP atribuído
kubectl get svc -n kube-news

# Aplicação acessível
curl http://<EXTERNAL-IP>
```

Checklist:
- [ ] `postgres` pod em `Running`
- [ ] `kube-news-blue` pods (2x) em `Running`
- [ ] Service `kube-news` com `EXTERNAL-IP` atribuído
- [ ] Aplicação respondendo via HTTP
