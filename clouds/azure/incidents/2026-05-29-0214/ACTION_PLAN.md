# Plano de Ação — 2026-05-29 02:14

> Este plano foi gerado automaticamente. Nenhuma ação foi executada.
> Revise cada passo, valide os comandos e aprove a execução explicitamente.

---

## Resumo dos Passos

| # | Ação | Risco | Tipo |
|---|---|---|---|
| 1 | Re-aplicar o deployment do postgres | Baixo | REVERSÍVEL |
| 2 | Aguardar postgres ficar Ready | Nenhum | VERIFICAÇÃO |
| 3 | Verificar recuperação automática dos pods da app | Nenhum | VERIFICAÇÃO |
| 4 | Validar acesso externo via LoadBalancer | Nenhum | VERIFICAÇÃO |
| 5 | (Opcional) Habilitar resources limits nos manifestos | Baixo | MELHORIA |

---

## Passo 1 — Re-aplicar o deployment do postgres `[REVERSÍVEL]`

**Objetivo:** Recriar o deployment `postgres` no namespace `kube-news`. O PVC `postgres-pvc` já está Bound com os dados preservados — o postgres irá inicializar com o volume existente.

**Risco:** Baixo — o PVC está preservado (dados não serão perdidos). A operação é idempotente (apply).

**Comando:**
```bash
kubectl apply -f k8s/kube-news-blue.yaml -n kube-news
```

> O arquivo `kube-news-blue.yaml` contém todos os recursos do namespace (Namespace, Secret, ConfigMap, PVC, Deployment postgres, Service postgres, Deployment kube-news-blue, Service kube-news). O apply é seguro pois recriará apenas o que está ausente e não modificará o que já existe.

**Resultado esperado:** Deployment `postgres` criado, pod `postgres-*` iniciando.

---

## Passo 2 — Aguardar postgres ficar Ready `[VERIFICAÇÃO]`

**Objetivo:** Confirmar que o postgres inicializou corretamente antes de verificar os pods da app.

**Risco:** Nenhum — apenas observação.

**Comando:**
```bash
kubectl rollout status deployment/postgres -n kube-news --timeout=120s
```

**Verificação adicional:**
```bash
kubectl get pods -n kube-news -l app=postgres
```

**Resultado esperado:**
```
deployment "postgres" successfully rolled out
NAME                        READY   STATUS    RESTARTS
postgres-xxxxxxxxx-xxxxx    1/1     Running   0
```

---

## Passo 3 — Verificar recuperação automática dos pods da app `[VERIFICAÇÃO]`

**Objetivo:** Após o postgres estar disponível, os pods `kube-news-blue` e `kube-news-green` devem se recuperar automaticamente assim que o backoff expirar e o próximo restart ocorrer com o banco disponível.

**Risco:** Nenhum — apenas observação.

**Comando (observar em tempo real):**
```bash
kubectl get pods -n kube-news -w
```

**Ou verificação pontual:**
```bash
kubectl get pods -n kube-news
```

**Resultado esperado:**
```
NAME                               READY   STATUS    RESTARTS
kube-news-blue-74bdc8bd96-54dxp    1/1     Running   7
kube-news-blue-74bdc8bd96-rwgfw    1/1     Running   7
kube-news-green-599d4d8b59-5jzcr   1/1     Running   6
kube-news-green-599d4d8b59-n4jqm   1/1     Running   6
postgres-xxxxxxxxx-xxxxx           1/1     Running   0
```

> Se os pods da app não se recuperarem em ~5 minutos após o postgres estar Running, execute um rollout restart:
> ```bash
> kubectl rollout restart deployment/kube-news-blue -n kube-news
> kubectl rollout restart deployment/kube-news-green -n kube-news
> ```

---

## Passo 4 — Validar acesso externo via LoadBalancer `[VERIFICAÇÃO]`

**Objetivo:** Confirmar que a aplicação está acessível via EXTERNAL-IP do LoadBalancer.

**Risco:** Nenhum.

**Comando:**
```bash
kubectl get svc kube-news -n kube-news
```

**Verificação HTTP:**
```bash
curl -s -o /dev/null -w "%{http_code}" http://20.200.201.126/
```

**Resultado esperado:** HTTP 200 e EXTERNAL-IP `20.200.201.126` com endpoints ativos.

---

## Passo 5 — (Opcional) Habilitar resources limits nos manifestos `[MELHORIA]`

**Objetivo:** Prevenir evicção por pressão de recursos (QoS BestEffort) e garantir estabilidade do cluster.

**Risco:** Baixo — pode causar OOMKilled se os limites forem muito restritivos. Ajuste conforme uso real.

**Ação:** Descomentar e ajustar as seções `resources` em `k8s/kube-news-blue.yaml` e `k8s/kube-news-green.yaml`:

```yaml
# Para kube-news (blue e green):
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "500m"

# Para postgres:
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "1000m"
```

**Após editar:**
```bash
kubectl apply -f k8s/kube-news-blue.yaml
kubectl apply -f k8s/kube-news-green.yaml
```

---

## Validação Final

Após execução de todos os passos, verificar:

- [ ] `kubectl get pods -n kube-news` — todos os 5 pods em `Running`
- [ ] `kubectl get deployment -n kube-news` — todos os deployments com `READY` = replicas desejadas (postgres 1/1, blue 2/2, green 2/2)
- [ ] `kubectl get svc kube-news -n kube-news` — LoadBalancer com `EXTERNAL-IP = 20.200.201.126`
- [ ] `curl http://20.200.201.126/` — resposta HTTP 200
- [ ] `kubectl get pvc -n kube-news` — `postgres-pvc` em `Bound`
- [ ] Nenhum evento `Warning` novo em `kubectl get events -n kube-news --sort-by=.lastTimestamp`
