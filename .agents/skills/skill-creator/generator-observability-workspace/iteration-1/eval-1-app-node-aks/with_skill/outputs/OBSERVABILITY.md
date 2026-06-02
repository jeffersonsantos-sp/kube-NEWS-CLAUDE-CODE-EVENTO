# OBSERVABILITY.md — kube-news

Documentação completa do stack de observabilidade implantado no projeto kube-news.

---

## Contexto

| Item | Valor |
|---|---|
| Projeto | kube-news |
| Plataforma | Azure AKS |
| Namespace da app | kube-news |
| Tecnologia | Node.js (Express) |
| Banco de dados | PostgreSQL 15 |
| Instrumentação | prom-client + express-prom-bundle (endpoint /metrics na porta 8080) |
| Email de alertas | jefferson@empresa.com |
| Storage Class | managed-csi |
| Data de geração | 2026-05-29 |

---

## Decisões arquiteturais

| Decisão | Justificativa |
|---|---|
| Desabilitar kubeScheduler, kubeControllerManager, kubeEtcd, kubeProxy | Componentes gerenciados pelo AKS — endpoints inacessíveis geram alertas falsos |
| Service ClusterIP separado para métricas | Evita conflito com o LoadBalancer existente; permite scrape limpo sem porta nomeada |
| ServiceMonitor com selector `app: kube-news` | Captura pods blue E green sem reconfiguração ao fazer rollout |
| postgres-exporter como Deployment separado | Melhor prática — não modifica o pod do PostgreSQL, usa credenciais do Secret existente |
| Loki + Promtail | Coleta de logs centralizada; Grafana desabilitado no loki-stack pois já instalado via kube-prometheus-stack |
| AlertManager com SMTP Gmail | Configuração padrão para email; requer Gmail App Password (não senha da conta) |
| Retenção Prometheus: 30d, PVC 20Gi | Retenção adequada para análise de incidentes; storage class managed-csi do AKS |

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────────┐
│                    namespace: monitoring                        │
│                                                                 │
│  ┌─────────────┐   scrape    ┌──────────────┐                  │
│  │  Prometheus  │◄───────────│ ServiceMonitor│                  │
│  │  (PVC 20Gi) │            │  kube-news    │                  │
│  └──────┬──────┘            └──────────────┘                  │
│         │ dados             ┌──────────────┐                  │
│         ▼                   │ ServiceMonitor│                  │
│  ┌─────────────┐◄───────────│ postgres-exp │                  │
│  │  Grafana    │            └──────────────┘                  │
│  │ (LB + PVC)  │                                              │
│  └──────┬──────┘   logs     ┌──────────────┐                  │
│         │◄──────────────────│     Loki      │                  │
│         │                   │  (PVC 10Gi)  │                  │
│  ┌──────▼──────┐            └──────┬───────┘                  │
│  │AlertManager │                   │ coleta                   │
│  │(email alerta│            ┌──────▼───────┐                  │
│  └─────────────┘            │   Promtail   │                  │
│                              │ (DaemonSet)  │                  │
└─────────────────────────────┴──────────────┴──────────────────┘
                                      │
┌─────────────────────────────────────▼──────────────────────────┐
│                    namespace: kube-news                         │
│                                                                 │
│  ┌──────────────┐  /metrics   ┌──────────────┐                 │
│  │ kube-news    │◄────────────│ kube-news-   │                 │
│  │ (blue/green) │  :8080      │ metrics svc  │                 │
│  └──────────────┘             └──────────────┘                 │
│                                                                 │
│  ┌──────────────┐  /metrics   ┌──────────────┐                 │
│  │   postgres   │◄────────────│  postgres-   │                 │
│  │   :5432      │  :9187      │  exporter    │                 │
│  └──────────────┘             └──────────────┘                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Componentes instalados

| Componente | Helm Chart | Namespace | PVC |
|---|---|---|---|
| Prometheus | kube-prometheus-stack | monitoring | 20Gi (managed-csi) |
| Grafana | kube-prometheus-stack | monitoring | 5Gi (managed-csi) |
| AlertManager | kube-prometheus-stack | monitoring | — |
| Loki | loki-stack | monitoring | 10Gi (managed-csi) |
| Promtail | loki-stack | monitoring | — (DaemonSet) |
| postgres-exporter | manifest direto | kube-news | — |

---

## Arquivos gerados

```
k8s/monitoring/
├── values-kube-prometheus-stack.yaml      # Stack principal (Prometheus + Grafana + AlertManager)
├── values-loki-stack.yaml                 # Logs (Loki + Promtail)
├── kube-news-metrics-service.yaml         # Service ClusterIP para /metrics (porta 8080)
├── kube-news-servicemonitor.yaml          # ServiceMonitor da app kube-news
├── postgres-exporter.yaml                 # Deployment + Service do postgres-exporter
├── postgres-exporter-servicemonitor.yaml  # ServiceMonitor do postgres-exporter
└── prometheus-rules.yaml                  # Regras de alerta (pods, HTTP, storage, postgres)
```

---

## Acesso

| Serviço | Comando para obter endereço | Credenciais |
|---|---|---|
| Grafana | `kubectl get svc kube-prometheus-stack-grafana -n monitoring` | admin / KubeNews@Monitoring2026 |
| Prometheus | `kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring` | Sem autenticação |
| AlertManager | `kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring` | Sem autenticação |

> **Importante:** Altere a senha do Grafana no primeiro acesso via UI ou via CLI:
> ```bash
> kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -- \
>   grafana-cli admin reset-admin-password NOVA_SENHA
> ```

---

## Alertas configurados

| Nome | Condição | Severidade | Destino |
|---|---|---|---|
| PodCrashLooping | Taxa de restarts > 0 por 5m | critical | jefferson@empresa.com |
| PodNotReady | Pod não Ready por 5m | critical | jefferson@empresa.com |
| HighHTTPLatency | P95 latência > 2s por 5m | warning | jefferson@empresa.com |
| HighHTTPErrorRate | Taxa 5xx > 5% por 5m | warning | jefferson@empresa.com |
| PVCUsageHigh | Uso > 80% por 5m | warning | jefferson@empresa.com |
| PostgresExporterDown | Exporter offline por 2m | critical | jefferson@empresa.com |
| PostgresHighConnections | Conexões > 80 por 5m | warning | jefferson@empresa.com |

---

## Configuração pós-instalação

### 1. Configurar Gmail App Password (OBRIGATÓRIO para email)

O AlertManager usa SMTP do Gmail. **Não use sua senha normal do Google** — use um App Password:

1. Acesse: https://myaccount.google.com/apppasswords
2. Crie um App Password para "Mail" / "Other"
3. Copie a senha gerada (16 caracteres)
4. Atualize o values do AlertManager:

```bash
# Edite o valor no values-kube-prometheus-stack.yaml:
# smtp_auth_password: 'REPLACE_WITH_GMAIL_APP_PASSWORD'
# Substitua pelo App Password gerado

helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/values-kube-prometheus-stack.yaml
```

### 2. Validar targets no Prometheus

```bash
# Port-forward para acessar o Prometheus UI
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring

# Acesse: http://localhost:9090/targets
# Verificar que os seguintes targets estão UP:
# - kube-news/kube-news (porta 8080 /metrics)
# - kube-news/postgres-exporter (porta 9187 /metrics)
```

### 3. Alterar senha do Grafana no primeiro acesso

Acesse o Grafana com as credenciais `admin / KubeNews@Monitoring2026` e altere imediatamente.

### 4. Desabilitar monitoramento nativo do AKS (após validação)

Após confirmar que o Prometheus coleta corretamente todos os targets, desabilite o Azure Monitor Managed Prometheus / Container Insights para evitar duplicação de custos e dados.

---

## Comandos de instalação

```bash
# 1. Adicionar repos Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 2. Criar namespace de monitoramento
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# 3. Instalar stack principal
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/values-kube-prometheus-stack.yaml \
  --timeout 10m --wait

# 4. Instalar Loki
helm install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --values k8s/monitoring/values-loki-stack.yaml \
  --timeout 10m --wait

# 5. Aplicar manifestos da app
kubectl apply -f k8s/monitoring/

# 6. Obter IP do Grafana
kubectl get svc kube-prometheus-stack-grafana -n monitoring
```

---

## Operações comuns

### Ver logs da aplicação no Grafana (Loki)

1. Abra o Grafana → Explore
2. Selecione datasource "Loki"
3. Query: `{namespace="kube-news"}`

### Verificar métricas da app

```promql
# Requisições por segundo
rate(http_requests_total{namespace="kube-news"}[5m])

# Latência P95
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{namespace="kube-news"}[5m]))

# Conexões PostgreSQL
pg_stat_activity_count{namespace="kube-news"}
```

### Silenciar um alerta temporariamente

```bash
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring
# Acesse: http://localhost:9093 → Silences → New Silence
```

### Atualizar valores após mudança

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/values-kube-prometheus-stack.yaml
```

---

## Pontos de atenção

| Item | Detalhe |
|---|---|
| Gmail App Password | OBRIGATÓRIO — sem isso alertas por email não funcionam |
| Componentes AKS desabilitados | kubeScheduler, kubeControllerManager, kubeEtcd, kubeProxy — gerenciados pela Azure |
| Blue-Green | O ServiceMonitor seleciona `app: kube-news` (sem filtro de versão), capturando pods blue e green simultaneamente |
| postgres-exporter DATA_SOURCE_NAME | Usa variável de ambiente composta — requer que POSTGRES_USER e POSTGRES_PASSWORD estejam definidos via valueFrom antes da expansão |
| Retenção Prometheus | Configurada para 30d; ajuste `retention` e `storage` se necessário |

---

## Métricas disponíveis

### App kube-news (prom-client + express-prom-bundle)

| Métrica | Tipo | Descrição |
|---|---|---|
| `http_requests_total` | Counter | Total de requisições HTTP por método, rota e status |
| `http_request_duration_seconds` | Histogram | Latência das requisições HTTP |
| `nodejs_heap_size_total_bytes` | Gauge | Tamanho total do heap Node.js |
| `nodejs_heap_size_used_bytes` | Gauge | Heap utilizado pelo Node.js |
| `nodejs_event_loop_lag_seconds` | Gauge | Lag do event loop (indica pressão na CPU) |
| `process_cpu_seconds_total` | Counter | Tempo de CPU consumido pelo processo |

### PostgreSQL (postgres-exporter)

| Métrica | Tipo | Descrição |
|---|---|---|
| `pg_stat_activity_count` | Gauge | Conexões ativas por estado |
| `pg_database_size_bytes` | Gauge | Tamanho do banco em bytes |
| `pg_stat_database_tup_fetched` | Counter | Linhas lidas por banco |
| `pg_stat_database_tup_inserted` | Counter | Linhas inseridas por banco |
| `pg_stat_database_deadlocks` | Counter | Deadlocks detectados |
| `pg_replication_lag` | Gauge | Lag de replicação (se configurado) |

### Infraestrutura (kube-state-metrics + node-exporter)

| Métrica | Tipo | Descrição |
|---|---|---|
| `kube_pod_status_ready` | Gauge | Status de prontidão dos pods |
| `kube_pod_container_status_restarts_total` | Counter | Restarts de containers |
| `node_cpu_seconds_total` | Counter | Uso de CPU por nó |
| `node_memory_MemAvailable_bytes` | Gauge | Memória disponível por nó |
| `kubelet_volume_stats_used_bytes` | Gauge | Uso de PVCs |
