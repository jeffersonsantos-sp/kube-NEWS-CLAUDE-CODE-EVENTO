# Observabilidade — kube-news

## Contexto

O cluster AKS (`AKSCLAUDECODE`) rodava com **Azure Container Insights** como único mecanismo de observabilidade. O Container Insights cobre métricas de infraestrutura e logs via Log Analytics, mas não raspa métricas de aplicação — e o kube-news já expunha um endpoint `/metrics` (via `express-prom-bundle` + `prom-client`) que nunca foi consumido.

O objetivo desta implementação foi substituir o Container Insights por um stack de observabilidade completo, self-hosted e centralizado no Grafana, cobrindo métricas de aplicação, métricas de banco de dados, métricas de infraestrutura e logs de containers.

---

## Decisões arquiteturais

### Problema identificado no brainstorm

| Camada | Gap antes da implementação |
|---|---|
| Métricas de app | `/metrics` exposto mas sem coleta |
| Métricas de banco | Nenhuma |
| Métricas de infra | Parcial via Container Insights |
| Logs | Container Insights (Azure Log Analytics) |
| Alertas | Nenhum |
| Dashboards | Nenhum |

### Opções avaliadas

| Opção | Descrição | Descartada por |
|---|---|---|
| kube-prometheus (manifests brutos) | Repo oficial, gerado via jsonnet | Toolchain complexo, incompatibilidade com K8s 1.34.7, inoperável para manutenção |
| **kube-prometheus-stack (Helm)** | Mesmo stack via chart gerenciável | **Escolhida** |
| Azure Managed Prometheus + Grafana | Solução gerenciada pela Azure | Custo de ingestão, lock-in; preferência por centralização self-hosted |

### Decisões finais

| Decisão | Escolha | Justificativa |
|---|---|---|
| Método de instalação | Helm (`prometheus-community/kube-prometheus-stack`) | Atualizável via `helm upgrade`, configurável via `values.yaml` |
| Logs | Loki + Promtail (`grafana/loki-stack`) | Integração nativa ao Grafana; cobre o gap deixado pela remoção do Container Insights |
| Componentes AKS desabilitados | `kubeScheduler`, `kubeControllerManager`, `kubeEtcd`, `kubeProxy` | São gerenciados pela Azure — scrape inacessível, gerariam alertas falsos permanentes |
| Persistência Prometheus | PVC 20Gi (`managed-csi`), retenção 30d | Métricas sobrevivem reinício de pod |
| Persistência Grafana | PVC 5Gi (`managed-csi`) | Dashboards e datasources persistidos |
| Persistência Loki | PVC 10Gi (`managed-csi`) | Logs persistidos entre restarts |
| Métricas de banco | postgres-exporter (Deployment separado) | Métricas de PostgreSQL sem alterar o pod existente |
| Alertas | AlertManager → Gmail SMTP | Canal imediato sem custo adicional |
| Acesso Grafana | Service `LoadBalancer` | IP público AKS com autenticação |
| Migração Container Insights | Desabilitar após validação | Garante zero janela cega de observabilidade durante a transição |

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│ Namespace: monitoring                                            │
│                                                                  │
│  ┌───────────────┐    scrape     ┌──────────────────────────┐  │
│  │  Prometheus   │◄──────────────│  ServiceMonitor          │  │
│  │  (PVC 20Gi)   │               │  - kube-news (app)        │  │
│  └──────┬────────┘               │  - postgres-exporter      │  │
│         │ query                  │  - node-exporter          │  │
│         ▼                        │  - kube-state-metrics     │  │
│  ┌───────────────┐               └──────────────────────────┘  │
│  │    Grafana    │◄── logs ──── Loki ◄── Promtail (DaemonSet)  │
│  │  (PVC 5Gi)    │                         │                    │
│  │  LoadBalancer │               ┌──────────▼──────────────┐   │
│  └───────────────┘               │ Todos os namespaces      │   │
│         │ alert                  │ (kube-news, kube-system) │   │
│         ▼                        └─────────────────────────┘   │
│  ┌───────────────┐                                              │
│  │ AlertManager  │──────────► Gmail (updateinformatica2019@)   │
│  └───────────────┘                                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Namespace: kube-news                                             │
│                                                                  │
│  kube-news (app) ──► /metrics:8080 ──► kube-news-metrics (svc) │
│  postgres ◄── postgres-exporter ──► :9187 (svc)                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Componentes instalados

| Componente | Namespace | Função |
|---|---|---|
| Prometheus | `monitoring` | Coleta e armazena métricas |
| Grafana | `monitoring` | Dashboards e visualização |
| AlertManager | `monitoring` | Roteamento e envio de alertas |
| Loki | `monitoring` | Armazenamento de logs |
| Promtail | `monitoring` | Agente de coleta de logs (DaemonSet) |
| Node Exporter | `monitoring` | Métricas do nó (CPU, memória, disco) |
| kube-state-metrics | `monitoring` | Métricas de objetos Kubernetes |
| Prometheus Operator | `monitoring` | Gerencia CRDs (ServiceMonitor, PrometheusRule) |
| postgres-exporter | `kube-news` | Métricas do PostgreSQL |

---

## Arquivos de configuração

```
k8s/monitoring/
├── values-kube-prometheus-stack.yaml   # Config principal do stack
├── values-loki-stack.yaml              # Config Loki + Promtail
├── kube-news-metrics-service.yaml      # Service ClusterIP para /metrics da app
├── kube-news-servicemonitor.yaml       # ServiceMonitor da app kube-news
├── postgres-exporter.yaml              # Deployment + Service do exporter
├── postgres-exporter-servicemonitor.yaml
└── prometheus-rules.yaml               # Regras de alerta
```

---

## Acesso

### Grafana

| Campo | Valor |
|---|---|
| URL | `http://20.249.165.203` |
| Usuário | `admin` |
| Senha padrão | `KubeNews@Monitoring2026` |

> **Altere a senha no primeiro acesso.** O serviço está exposto publicamente via LoadBalancer.

**Datasources configurados automaticamente:**
- `Prometheus` — métricas (padrão)
- `Loki` — logs

### Prometheus (interno)

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# Acesse: http://localhost:9090
```

### AlertManager (interno)

```bash
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring
# Acesse: http://localhost:9093
```

---

## Alertas configurados

| Alerta | Condição | Severidade |
|---|---|---|
| `PodCrashLooping` | Pod no namespace `kube-news` reiniciando | critical |
| `PodNotReady` | Pod não pronto por 5 minutos | critical |
| `HighHTTPLatency` | P95 de latência > 2s por rota | warning |
| `HighHTTPErrorRate` | Mais de 5% das requisições retornando 5xx | warning |
| `PVCUsageHigh` | PVC acima de 80% de capacidade | warning |

Todos os alertas críticos disparam email para `updateinformatica2019@gmail.com`.

---

## Configuração pós-instalação

### 1. Gmail App Password (obrigatório para alertas)

O AlertManager está instalado mas silencioso até essa etapa.

1. Acesse `myaccount.google.com/apppasswords`
2. Habilite 2FA se necessário
3. Gere uma senha para "Other device" — copie o código de 16 caracteres
4. Execute:

```bash
export PATH="$HOME/bin:$PATH"

helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/values-kube-prometheus-stack.yaml \
  --set alertmanager.config.global.smtp_auth_password="SEU_APP_PASSWORD_AQUI"
```

### 2. Desativar Container Insights

Execute **somente após validar** que métricas e logs aparecem no Grafana:

```bash
az aks update \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --disable-azure-monitor-metrics \
  --no-wait
```

Para desabilitar também a coleta de logs pelo ama-logs:

```bash
az aks disable-addons \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --addons monitoring
```

---

## Operações comuns

### Atualizar o stack

```bash
export PATH="$HOME/bin:$PATH"
helm repo update

helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/values-kube-prometheus-stack.yaml

helm upgrade loki-stack grafana/loki-stack \
  --namespace monitoring \
  --values k8s/monitoring/values-loki-stack.yaml
```

### Verificar targets do Prometheus

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# Acesse: http://localhost:9090/targets
# Verifique: kube-news e postgres-exporter devem estar UP
```

### Ver logs de um pod pelo Grafana

1. Abra o Grafana → menu **Explore**
2. Selecione datasource **Loki**
3. Use o label filter: `namespace=kube-news`

### Adicionar nova regra de alerta

Edite `k8s/monitoring/prometheus-rules.yaml` e aplique:

```bash
kubectl apply -f k8s/monitoring/prometheus-rules.yaml
```

### Escalar o postgres-exporter

```bash
kubectl scale deployment postgres-exporter --replicas=1 -n kube-news
```

### Verificar status geral

```bash
kubectl get pods -n monitoring
kubectl get pods -n kube-news | grep exporter
kubectl get servicemonitor -A
kubectl get prometheusrule -A
```

---

## Pontos de atenção

| Item | Detalhe |
|---|---|
| `grafana/loki-stack` deprecated | Funciona mas deve ser migrado para `grafana/loki` (modo single binary) em uma próxima janela de manutenção |
| Cluster single-node | O monitoramento cai junto com o nó em caso de falha de infraestrutura — considere adicionar um segundo node pool dedicado ao stack de observabilidade |
| Senha Grafana | Alterar imediatamente após o primeiro acesso |
| Gmail App Password | Sem ela, nenhum alerta é enviado |
| Container Insights | Continua consumindo recursos até ser desabilitado explicitamente via `az aks update` |

---

## Métricas disponíveis após a instalação

### Aplicação (kube-news)

| Métrica | Descrição |
|---|---|
| `http_request_duration_seconds` | Latência por rota, método e status code |
| `http_requests_total` | Total de requisições |
| `nodejs_heap_size_used_bytes` | Uso de memória heap do Node.js |
| `nodejs_eventloop_lag_seconds` | Lag do event loop |
| `process_cpu_seconds_total` | CPU consumida pelo processo |

### Banco de dados (postgres-exporter)

| Métrica | Descrição |
|---|---|
| `pg_up` | PostgreSQL está acessível |
| `pg_stat_activity_count` | Conexões ativas |
| `pg_stat_database_tup_fetched` | Linhas lidas por banco |
| `pg_stat_database_deadlocks` | Deadlocks detectados |
| `pg_database_size_bytes` | Tamanho do banco |

### Infraestrutura (node-exporter + kube-state-metrics)

Métricas padrão de CPU, memória, disco, rede do nó e estado dos objetos Kubernetes (pods, deployments, PVCs).
