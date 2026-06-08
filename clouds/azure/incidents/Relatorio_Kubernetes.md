# Relatório do Cluster Kubernetes

**Data:** 28/05/2026
**Cluster:** AKSCLAUDECODE
**Provedor:** Microsoft Azure (AKS)
**Região:** Korea Central

---

## 1. Inventário de Hardware

| Atributo | Valor |
|---|---|
| **Nome do Nó** | `aks-nodepool1-54470473-vmss000001` |
| **Tipo de VM** | Standard_D4ds_v4 |
| **vCPUs** | 4 cores |
| **Memória Total** | ~16 GB (15,58 GiB) |
| **CPU Alocável** | 3.860m (96,5%) |
| **Memória Alocável** | ~11,8 GiB |
| **Armazenamento Efêmero** | ~130 GiB |
| **Sistema Operacional** | Ubuntu 22.04.5 LTS |
| **Kernel** | 5.15.0-1111-azure |
| **Arquitetura** | amd64 |
| **Container Runtime** | containerd 1.7.31-1 |
| **Versão Kubernetes** | v1.34.7 |
| **IP Interno** | 10.224.0.4 |
| **Pods máximos suportados** | 250 |
| **Uptime do nó** | ~3 dias (desde 25/05/2026) |

> **Topologia:** Cluster single-node, zona 0, rede overlay com Azure CNI.

---

## 2. Pods em Execução

**Total: 19 pods ativos** distribuídos em 2 namespaces.

### Namespace: `kube-news`

| Pod | Status | Restarts | CPU | Memória | IP |
|---|---|---|---|---|---|
| `kube-news-blue-74bdc8bd96-v26sd` | Running | **3** | 5m | 42 Mi | 10.244.0.66 |
| `kube-news-blue-74bdc8bd96-wlw2z` | Running | **3** | 5m | 35 Mi | 10.244.0.254 |
| `postgres-66779479f8-88gdt` | Running | 0 | 4m | 40 Mi | 10.244.0.161 |

### Namespace: `kube-system` (componentes do sistema)

| Pod | Status | Containers | Restarts |
|---|---|---|---|
| `coredns-*` (2x) | Running | 1/1 | 0 |
| `metrics-server-*` (2x) | Running | 2/2 | 0 |
| `konnectivity-agent-*` (2x) | Running | 1/1 | 0 |
| `ama-logs-rs-*` | Running | 2/2 | 0 |
| `ama-logs-zssjw` | Running | 3/3 | 0 |
| `azure-cns-nfrz8` | Running | 1/1 | 0 |
| `csi-azuredisk-node-*` | Running | 3/3 | 0 |
| `csi-azurefile-node-*` | Running | 4/4 | 0 |
| `kube-proxy-*` | Running | 1/1 | 0 |
| `azure-ip-masq-agent-*` | Running | 1/1 | 0 |
| `cloud-node-manager-*` | Running | 1/1 | 0 |
| `konnectivity-agent-autoscaler-*` | Running | 1/1 | 0 |
| `coredns-autoscaler-*` | Running | 1/1 | 0 |

---

## 3. Aplicações em Execução

### `kube-news` — Aplicação Principal

| Atributo | Valor |
|---|---|
| **Deployment** | `kube-news-blue` |
| **Estratégia** | Blue-Green (somente Blue ativo) |
| **Réplicas** | 2/2 Ready |
| **Exposição** | `LoadBalancer` (externo) |
| **Criado em** | 28/05/2026 16:17 |

### `postgres` — Banco de Dados

| Atributo | Valor |
|---|---|
| **Deployment** | `postgres` |
| **Réplicas** | 1/1 Ready |
| **Exposição** | `ClusterIP` (interno) |
| **Persistência** | PVC `postgres-pvc` — **Bound** |
| **Criado em** | 28/05/2026 16:17 |

### Serviços Expostos

| Serviço | Namespace | Tipo | Finalidade |
|---|---|---|---|
| `kube-news` | kube-news | LoadBalancer | Acesso externo à aplicação |
| `postgres` | kube-news | ClusterIP | Comunicação interna com o banco |
| `kube-dns` | kube-system | ClusterIP | Resolução DNS interna |
| `metrics-server` | kube-system | ClusterIP | Métricas de recursos |
| `kubernetes` | default | ClusterIP | API Server |

### Namespaces do Cluster

| Namespace | Status | Criado em |
|---|---|---|
| `default` | Active | 22/05/2026 |
| `kube-news` | Active | 28/05/2026 |
| `kube-system` | Active | 22/05/2026 |
| `kube-node-lease` | Active | 22/05/2026 |
| `kube-public` | Active | 22/05/2026 |

---

## 4. Status de Saúde do Cluster e das Aplicações

### Saúde do Nó

| Condição | Status | Mensagem |
|---|---|---|
| Node Ready | ✅ True | kubelet is posting ready status |
| MemoryPressure | ✅ False | kubelet has sufficient memory available |
| DiskPressure | ✅ False | kubelet has no disk pressure |
| PIDPressure | ✅ False | kubelet has sufficient PID available |
| KernelDeadlock | ✅ False | kernel has no deadlock |
| FilesystemCorruption | ✅ False | Filesystem is healthy |
| ReadonlyFilesystem | ✅ False | Filesystem is not read-only |
| ContainerRuntimeProblem | ✅ False | container runtime service is up |
| FrequentKubeletRestart | ✅ False | kubelet is functioning properly |
| FrequentContainerdRestart | ✅ False | containerd is functioning properly |
| FrequentDockerRestart | ✅ False | docker is functioning properly |
| KubeletProblem | ✅ False | kubelet service is up |
| VMEventScheduled | ✅ False | VM has no scheduled event |

### Consumo de Recursos em Tempo Real

| Recurso | Uso Atual | Capacidade | % Utilização |
|---|---|---|---|
| **CPU** | 181m | 4.000m | **4%** |
| **Memória** | 2.358 Mi | ~11.800 Mi | **19%** |

### Alertas de Overcommit (Limits configurados vs. capacidade alocável)

| Recurso | Requests | % | Limits | % |
|---|---|---|---|---|
| **CPU** | 1.242m | 32% | 13.092m | **339%** ⚠️ |
| **Memória** | 1.804 Mi | 15% | ~16.936 Mi | **143%** ⚠️ |

> Os limites de CPU somam **339%** da capacidade alocável — situação de overcommit crítico.
> Os limites de memória somam **143%** da capacidade alocável.

### Saúde das Aplicações

| Aplicação | Deployment | Pods | Restarts | Eventos Ativos |
|---|---|---|---|---|
| kube-news | ✅ 2/2 Ready | Running | ⚠️ 3 cada | Nenhum |
| postgres | ✅ 1/1 Ready | Running | ✅ 0 | Nenhum |

> Os 3 restarts nos pods `kube-news-blue` ocorreram há ~5h no momento da coleta.
> Nenhum evento de warning ativo no namespace `kube-news`.

---

## 5. Sugestões de Melhorias

### Prioridade Alta

#### 1. Definir `resources.requests` e `resources.limits` nos pods `kube-news`

Atualmente os pods da aplicação não têm requests nem limits configurados. Isso impede o scheduler de fazer decisões corretas de alocação e pode causar OOMKill ou CPU starvation.

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

#### 2. Investigar os 3 restarts dos pods `kube-news-blue`

Os pods reiniciaram 3 vezes. Verificar os logs do container anterior para identificar a causa raiz:

```bash
kubectl logs <pod-name> --previous -n kube-news
kubectl describe pod <pod-name> -n kube-news
```

Possíveis causas: crash da aplicação, OOMKill, falha de liveness probe ou problema na inicialização.

#### 3. Migrar PostgreSQL para `StatefulSet`

O banco de dados está rodando como `Deployment`, o que não garante identidade de rede estável nem ordem de inicialização controlada. Use `StatefulSet` para workloads stateful como bancos de dados relacionais.

---

### Prioridade Média

#### 4. Adicionar mais de 1 nó (Alta Disponibilidade)

O cluster possui apenas **1 nó**. Se ele falhar, toda a carga de trabalho cai imediatamente. Recomenda-se no mínimo 2 nós para ambientes de produção, idealmente distribuídos em zonas de disponibilidade distintas.

#### 5. Configurar `HorizontalPodAutoscaler` (HPA)

A aplicação `kube-news` tem réplicas fixas em 2. Com HPA configurado, o cluster escala automaticamente conforme demanda:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: kube-news-hpa
  namespace: kube-news
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: kube-news-blue
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

#### 6. Reduzir overcommit de CPU no `kube-system`

Os limits de CPU somam 339% da capacidade alocável. Os principais responsáveis são `coredns` (3 CPU de limit cada) e `ama-logs`. Revisar e ajustar esses limits para valores mais realistas com base no consumo observado.

#### 7. Ativar o lado `Green` do Blue-Green com Ingress Controller

A estratégia Blue-Green está configurada no projeto, mas apenas o `Blue` está ativo. Para aproveitar o modelo corretamente, configure um **Ingress Controller** (ex: NGINX Ingress) para orquestrar o chaveamento de tráfego entre Blue e Green de forma controlada e sem downtime.

---

### Prioridade Baixa

#### 8. Configurar `NetworkPolicies`

Não há políticas de rede definidas no namespace `kube-news`. Isso permite comunicação irrestrita entre todos os pods. Adicione NetworkPolicies para isolar o banco de dados:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app-to-postgres
  namespace: kube-news
spec:
  podSelector:
    matchLabels:
      app: postgres
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: kube-news
```

#### 9. Configurar `PodDisruptionBudget` (PDB)

Para garantir disponibilidade mínima durante manutenções ou drain de nós, configure um PDB:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: kube-news-pdb
  namespace: kube-news
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: kube-news
```

#### 10. Revisar estratégia de backup do PostgreSQL

O PVC `postgres-pvc` está Bound, mas não há evidência de política de backup configurada. Recomenda-se adotar uma das estratégias abaixo:

- **Azure Disk Snapshots** — snapshots automáticos agendados pelo Azure
- **Velero** — solução open-source para backup de volumes e recursos Kubernetes
- **pg_dump agendado** — CronJob interno que exporta o banco periodicamente para um storage externo

---

## Resumo Executivo

| Indicador | Status |
|---|---|
| Nó disponível | ✅ Ready |
| Utilização de CPU | ✅ 4% (saudável) |
| Utilização de Memória | ✅ 19% (saudável) |
| Overcommit de CPU (limits) | ⚠️ 339% (crítico) |
| Overcommit de Memória (limits) | ⚠️ 143% (atenção) |
| Pods da aplicação | ✅ Running |
| Restarts nos pods kube-news | ⚠️ 3 restarts (investigar) |
| Banco de dados | ✅ Running, PVC Bound |
| Alta Disponibilidade | ❌ Single-node |
| Resource Requests/Limits (app) | ❌ Não configurados |
| Backup do banco de dados | ❌ Não evidenciado |

O cluster está **operacional e saudável** em termos de hardware. Os principais riscos são a ausência de `requests/limits` na aplicação, os 3 restarts não investigados, o banco de dados configurado como `Deployment` ao invés de `StatefulSet`, e a falta de alta disponibilidade com apenas 1 nó no cluster.
