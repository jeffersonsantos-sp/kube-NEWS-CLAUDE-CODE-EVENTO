# Incident RCA — 2026-05-29 02:14

| Campo | Valor |
|---|---|
| Data/Hora | 2026-05-29 02:14 UTC |
| Cluster | AKSCLAUDECODE |
| Contexto kubectl | AKSCLAUDECODE (AKS — rg-claude-code) |
| Namespace | kube-news |
| Severidade | **CRÍTICA** |
| Status | Em investigação |

---

## Sumário Executivo

O deployment `postgres` foi removido do namespace `kube-news`, derrubando o único banco de dados do qual todos os pods da aplicação dependem. Como resultado, todos os 4 pods da aplicação (`kube-news-blue` x2 e `kube-news-green` x2) entraram em **CrashLoopBackOff** com `ECONNREFUSED` ao tentar conectar ao postgres na porta 5432. A aplicação está **completamente inacessível** via LoadBalancer (0/4 pods em Ready). Os dados do banco estão **preservados** no PVC `postgres-pvc` (Bound, 5Gi).

---

## Achados

### [INFRA] Achado 1 — Deployment `postgres` ausente no cluster

- **Descrição:** O deployment `postgres` está definido em `k8s/kube-news-blue.yaml` mas não existe no cluster. O pod do postgres foi encerrado (~2 minutos atrás) e o deployment foi deletado — nenhum replicaset ou pod do postgres está presente no namespace `kube-news`.
- **Evidência:**
  ```
  $ kubectl get deployment postgres -n kube-news
  Error: Resource deployment/postgres not found

  $ kubectl get pods -n kube-news
  NAME                               READY   STATUS             RESTARTS
  kube-news-blue-74bdc8bd96-54dxp    0/1     CrashLoopBackOff   7
  kube-news-blue-74bdc8bd96-rwgfw    0/1     CrashLoopBackOff   7
  kube-news-green-599d4d8b59-5jzcr   0/1     CrashLoopBackOff   6
  kube-news-green-599d4d8b59-n4jqm   0/1     CrashLoopBackOff   6
  # Pod postgres: ausente

  Evento capturado:
  72s  Normal  Killing  pod/postgres-66779479f8-88brh  Stopping container postgres
  ```
- **Causa Raiz:** O deployment `postgres` foi deletado manualmente ou por algum processo automatizado. O Kubernetes encerrou o pod (`Killing`) e não há controlador para recriá-lo.

---

### [SAÚDE] Achado 2 — CrashLoopBackOff em todos os pods da aplicação (ECONNREFUSED)

- **Descrição:** Todos os 4 pods da aplicação (kube-news-blue e kube-news-green) estão em CrashLoopBackOff. A aplicação inicia, tenta conectar ao postgres via Service ClusterIP `10.0.170.38:5432` e falha imediatamente com `ECONNREFUSED` pois não há pod rodando atrás do Service `postgres`.
- **Evidência:**
  ```
  Log do pod kube-news-blue-74bdc8bd96-54dxp (última execução):

  Aplicação rodando na porta 8080
  ConnectionRefusedError [SequelizeConnectionRefusedError]: connect ECONNREFUSED 10.0.170.38:5432
      at Client._connectionCallback (.../connection-manager.js:130:24)
  ...
  errno: -111, code: 'ECONNREFUSED', address: '10.0.170.38', port: 5432

  Eventos dos pods:
  Warning  Unhealthy  Readiness probe failed: Get "http://10.244.0.239:8080/": EOF
  Warning  BackOff    Back-off restarting failed container kube-news (count: 17)
  Warning  BackOff    Back-off restarting failed container kube-news (count: 16)
  Warning  BackOff    Back-off restarting failed container kube-news (count: 13)
  Warning  BackOff    Back-off restarting failed container kube-news (count: 12)
  ```
- **Causa Raiz:** Dependência direta da aplicação no banco de dados durante inicialização. Sem o postgres disponível, a aplicação não sobe e entra em loop de restart.

---

### [INFRA] Achado 3 — Service `postgres` existe mas sem endpoints

- **Descrição:** O Service `postgres` (ClusterIP `10.0.170.38`) ainda existe no namespace, mas não possui pods correspondentes. Qualquer tentativa de conexão na porta 5432 resulta em `ECONNREFUSED`.
- **Evidência:**
  ```
  service/postgres   ClusterIP   10.0.170.38   <none>   5432/TCP   4h4m   app=postgres
  # Nenhum pod com label app=postgres está Running
  ```
- **Causa Raiz:** Consequência direta da deleção do deployment postgres.

---

### [INFO] Achado 4 — PVC `postgres-pvc` preservado (dados seguros)

- **Descrição:** O PersistentVolumeClaim `postgres-pvc` ainda está `Bound` com 5Gi, o que significa que os dados do banco de dados **não foram perdidos** e serão reutilizados quando o deployment for recriado.
- **Evidência:**
  ```
  NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES
  postgres-pvc   Bound    pvc-6093dd1e-9790-4ef8-91e7-0f734d243167   5Gi        RWO
  ```

---

### [RISCO] Achado 5 — Resources limits/requests comentados em todos os Deployments

- **Descrição:** As seções `resources` (CPU e memória) estão comentadas em todos os três deployments (`postgres`, `kube-news-blue`, `kube-news-green`). Isso coloca todos os pods na QoS class `BestEffort`, tornando-os os primeiros a serem evictados em situações de pressão de recursos no nó.
- **Causa Raiz:** Configuração de manifesto incompleta — seção `resources` desabilitada por comentário.

---

## Timeline Estimada

| Horário (UTC) | Evento |
|---|---|
| 2026-05-28 ~22:07 | Deployments `kube-news-blue`, `kube-news-green` e `postgres` criados no namespace `kube-news` |
| 2026-05-28 ~22:08 | Todos os pods inicializam e ficam Running |
| 2026-05-29 ~02:12 | Deployment `postgres` deletado (manualmente ou por automação) |
| 2026-05-29 ~02:12 | Kubelet encerra o pod `postgres-66779479f8-88brh` (`Stopping container postgres`) |
| 2026-05-29 ~02:13 | Pods `kube-news-blue` e `kube-news-green` começam a falhar com ECONNREFUSED |
| 2026-05-29 ~02:14 | Todos os 4 pods em CrashLoopBackOff — aplicação inacessível |
| 2026-05-29 ~02:14 | Incidente detectado e diagnóstico iniciado |

---

## Recursos Afetados

| Recurso | Namespace | Estado Atual | Estado Esperado |
|---|---|---|---|
| deployment/postgres | kube-news | **AUSENTE** | Running (1/1) |
| pod/postgres-* | kube-news | **AUSENTE** | Running |
| pod/kube-news-blue-* (x2) | kube-news | CrashLoopBackOff (7 restarts) | Running (2/2) |
| pod/kube-news-green-* (x2) | kube-news | CrashLoopBackOff (6 restarts) | Running (2/2) |
| service/kube-news (LB) | kube-news | Sem endpoints ativos | EXTERNAL-IP 20.200.201.126 acessível |
| pvc/postgres-pvc | kube-news | Bound (dados preservados) | Bound |
