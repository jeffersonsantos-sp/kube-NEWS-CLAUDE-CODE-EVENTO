# Incident RCA — 2026-06-01 21:36

| Campo | Valor |
|---|---|
| Data/Hora | 2026-06-01 21:36 UTC |
| Cluster | `aks-kube-news` |
| Contexto kubectl | `aks-kube-news` (Azure AKS — australiaeast) |
| Servidor API | `https://aks-kube-news-z6q0yhi6.hcp.australiaeast.azmk8s.io:443` |
| Severidade | **CRÍTICA** |
| Status | Corrigido |

---

## Sumário Executivo

A aplicação `kube-news` estava completamente inacessível. O cluster AKS foi recriado via Terraform (`aks-kube-news` em `rg-kube_news`, região `australiaeast`), mas nenhum manifesto de aplicação foi reaplicado ao novo cluster. O namespace `kube-news` não existia, resultando em zero pods, zero services e zero recursos de aplicação no cluster. O cluster de infraestrutura estava saudável — o incidente foi causado exclusivamente pela ausência do deploy pós-provisionamento.

---

## Achados

### [INFRA] Achado 1 — Namespace `kube-news` ausente no cluster

- **Descrição:** O namespace `kube-news` declarado em `k8s/kube-news-blue.yaml` não existia no cluster. Apenas os namespaces padrão do Kubernetes estavam presentes.
- **Evidência:**
  ```
  $ kubectl get namespaces
  NAME              STATUS   AGE
  default           Active   166m
  kube-node-lease   Active   166m
  kube-public       Active   166m
  kube-system       Active   166m
  ```
- **Causa Raiz:** Cluster recriado via Terraform sem reaplicação dos manifestos da aplicação.

---

### [INFRA] Achado 2 — Zero recursos de aplicação no cluster

- **Descrição:** Nenhum Deployment, Service, Secret, ConfigMap, PVC ou Pod da aplicação existia no cluster.
- **Evidência:**
  ```
  $ kubectl get all -n kube-news -o wide
  No resources found in kube-news namespace.

  $ kubectl get pvc -n kube-news
  No resources found in kube-news namespace.
  ```
- **Causa Raiz:** Os manifestos `k8s/kube-news-blue.yaml` nunca foram aplicados ao novo cluster.

---

### [INFRA] Achado 3 — Cluster AKS saudável

- **Descrição:** A infraestrutura do cluster estava completamente operacional. Ambos os nodes estavam `Ready` e todos os pods do `kube-system` em `Running`.
- **Evidência:**
  ```
  $ kubectl get nodes -o wide
  NAME                             STATUS   ROLES    AGE    VERSION
  aks-system-39531238-vmss000000   Ready    <none>   165m   v1.34.7
  aks-user-32769649-vmss000000     Ready    <none>   160m   v1.34.7
  ```
- **Causa Raiz:** Não aplicável — cluster OK. O problema era exclusivamente de ausência de deploy.

---

## Timeline Estimada

| Horário | Evento |
|---|---|
| ~2026-06-01 18:30 | `terraform apply` concluído — cluster `aks-kube-news` provisionado |
| ~2026-06-01 18:30–21:36 | Manifestos da aplicação não aplicados ao novo cluster |
| 2026-06-01 21:36 | Incidente detectado e diagnosticado |
| 2026-06-01 21:36 | Correção aplicada via `kubectl apply -f k8s/kube-news-blue.yaml` |

---

## Recursos Afetados

| Recurso | Namespace | Estado Atual | Estado Esperado |
|---|---|---|---|
| Namespace `kube-news` | — | Ausente | Presente |
| Deployment `postgres` | `kube-news` | Ausente | 1 réplica Running |
| Deployment `kube-news-blue` | `kube-news` | Ausente | 2 réplicas Running |
| Service `kube-news` (LoadBalancer) | `kube-news` | Ausente | Presente com EXTERNAL-IP |
| Service `postgres` (ClusterIP) | `kube-news` | Ausente | Presente |
| PVC `postgres-pvc` | `kube-news` | Ausente | Bound (5Gi) |
| Secret `kube-news-secret` | `kube-news` | Ausente | Presente |
| ConfigMap `kube-news-config` | `kube-news` | Ausente | Presente |

---

## Lição Aprendida

Ao recriar ou migrar o cluster Kubernetes, o processo de provisionamento via Terraform **não** aplica os manifestos da aplicação automaticamente. Um pipeline CI/CD ou runbook de pós-provisionamento deve incluir o `kubectl apply` dos manifestos como etapa obrigatória após qualquer `terraform apply` que recrie o cluster.
