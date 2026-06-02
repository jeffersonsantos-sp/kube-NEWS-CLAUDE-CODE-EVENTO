---
name: generator-observability
description: Gera o stack completo de observabilidade Kubernetes (Prometheus + Grafana + Loki + AlertManager + exporters) via Helm, adaptado ao provedor de cloud e às tecnologias detectadas no projeto. Produz todos os arquivos em k8s/monitoring/, instala via Helm e gera OBSERVABILITY.md. Use sempre que o usuário mencionar monitoramento, métricas, Prometheus, Grafana, Loki, AlertManager, observabilidade, dashboards ou quiser adicionar visibilidade a uma aplicação Kubernetes — mesmo que não use a palavra "skill" ou "observabilidade".
---

## O que esta skill faz

Inspeciona o projeto e o cluster Kubernetes ativos, toma todas as decisões de configuração, gera os arquivos de monitoramento em `k8s/monitoring/`, instala o stack via Helm e documenta tudo em `OBSERVABILITY.md`. Nenhuma decisão óbvia é devolvida ao usuário — só perguntas genuinamente ambíguas.

---

## Processo de execução

### Fase 1 — Inspeção do projeto

Leia em paralelo:
- `docker-compose.yml` — identifica serviços, bancos de dados, tecnologia da app
- `src/package.json` (Node.js) ou `requirements.txt` / `pyproject.toml` (Python) ou `pom.xml` / `build.gradle` (Java) — detecta bibliotecas de métricas
- `k8s/*.yaml` — detecta namespaces, serviços, portas existentes
- `k8s/monitoring/` se existir — verifica o que já está gerado

### Fase 2 — Inspeção do cluster

Execute em paralelo (via MCP Kubernetes ou kubectl):
```bash
kubectl config current-context          # provedor de cloud
kubectl get nodes -o wide               # versão K8s, OS, quantidade de nós
kubectl get storageclass                # storage classes disponíveis
kubectl get namespaces                  # namespaces existentes
kubectl top nodes                       # recursos disponíveis (CPU/RAM)
kubectl get pods -A | grep -E "ama-logs|cloudwatch|stackdriver"  # monitoramento nativo ativo
```

### Fase 3 — Decisões de configuração

Aplique as regras abaixo e consolide as decisões **antes** de gerar qualquer arquivo.

### Fase 4 — Geração dos arquivos

Gere todos os arquivos em `k8s/monitoring/` (detalhe abaixo).

### Fase 5 — Instalação via Helm

Execute os comandos de instalação e aguarde os pods ficarem `Running`.

### Fase 6 — Resumo final

Exiba o resumo e gere `OBSERVABILITY.md`.

---

## Regras de detecção

### Provedor de cloud (context name ou node labels)

| Sinal detectado | Provedor | Storage class padrão |
|---|---|---|
| Context contém `AKS` ou node OS-Image contém `azure` | Azure AKS | `managed-csi` |
| Context contém `eks` ou node label `eks.amazonaws.com` | AWS EKS | `gp2` |
| Context contém `gke` ou node label `cloud.google.com/gke` | Google GKE | `standard` |
| Nenhum sinal claro | Genérico (kind, k3s, etc.) | `standard` ou `local-path` |

### Componentes gerenciados a desabilitar por provedor

Componentes gerenciados não têm endpoint de scrape acessível — deixá-los habilitados gera alertas falsos permanentes.

| Provedor | Desabilitar no values.yaml |
|---|---|
| AKS | `kubeScheduler`, `kubeControllerManager`, `kubeEtcd`, `kubeProxy` |
| EKS | `kubeScheduler`, `kubeControllerManager`, `kubeEtcd` |
| GKE | `kubeScheduler`, `kubeControllerManager`, `kubeEtcd` |
| Genérico | Nenhum — manter tudo habilitado |

### Instrumentação da app (endpoint /metrics)

| Sinal | Conclusão | Ação |
|---|---|---|
| `prom-client`, `express-prom-bundle` em package.json | App Node.js já instrumentada | Criar Service de métricas + ServiceMonitor |
| `prometheus_client` em requirements.txt | App Python já instrumentada | Criar Service de métricas + ServiceMonitor |
| `micrometer` em pom.xml | App Java (Spring) já instrumentada | Criar Service de métricas + ServiceMonitor |
| Nenhuma biblioteca detectada | App não instrumentada | Gerar ServiceMonitor com aviso; documentar instrumentação necessária |

A porta do endpoint `/metrics` é a mesma porta HTTP da app (detectada em `ports:` do docker-compose ou `containerPort` dos manifests).

### Banco de dados e exporters

| Banco detectado | Exporter | Imagem | Porta |
|---|---|---|---|
| PostgreSQL | postgres-exporter | `prometheuscommunity/postgres-exporter:v0.15.0` | 9187 |
| MySQL / MariaDB | mysqld-exporter | `prom/mysqld-exporter:v0.15.0` | 9104 |
| Redis | redis-exporter | `oliver006/redis_exporter:v1.55.0` | 9121 |
| MongoDB | mongodb-exporter | `percona/mongodb_exporter:0.40` | 9216 |
| Nenhum | — | Não gerar exporter | — |

O exporter é sempre um **Deployment separado** no mesmo namespace da aplicação, usando credenciais do Secret existente via `valueFrom`.

---

## Estrutura dos arquivos gerados

```
k8s/monitoring/
├── values-kube-prometheus-stack.yaml      # Stack principal
├── values-loki-stack.yaml                 # Logs
├── <app>-metrics-service.yaml             # Service ClusterIP para /metrics
├── <app>-servicemonitor.yaml              # ServiceMonitor da app
├── <db>-exporter.yaml                     # Deployment + Service do exporter (se banco detectado)
├── <db>-exporter-servicemonitor.yaml      # ServiceMonitor do exporter
└── prometheus-rules.yaml                  # Regras de alerta
```

---

## Regras para values-kube-prometheus-stack.yaml

### Bloco obrigatório — desabilitar componentes gerenciados

```yaml
# exemplo para AKS
kubeScheduler:
  enabled: false
kubeControllerManager:
  enabled: false
kubeEtcd:
  enabled: false
kubeProxy:
  enabled: false

defaultRules:
  rules:
    kubeSchedulerAlerting: false
    kubeSchedulerRecording: false
    kubeControllerManager: false
    etcd: false
    kubeProxy: false
```

### Bloco obrigatório — Prometheus com descoberta global

```yaml
prometheus:
  prometheusSpec:
    retention: 30d
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector: {}
    serviceMonitorNamespaceSelector: {}
    podMonitorSelectorNilUsesHelmValues: false
    podMonitorSelector: {}
    podMonitorNamespaceSelector: {}
    ruleNamespaceSelector: {}
    ruleSelectorNilUsesHelmValues: false
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 500m
        memory: 2Gi
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: <storage-class-detectada>
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi
```

### Bloco obrigatório — Grafana

```yaml
grafana:
  adminPassword: "<NomeProjeto>@Monitoring<Ano>"   # ex: KubeNews@Monitoring2026
  service:
    type: LoadBalancer
  persistence:
    enabled: true
    storageClassName: <storage-class-detectada>
    size: 5Gi
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 300m
      memory: 512Mi
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki-stack.monitoring.svc.cluster.local:3100
      access: proxy
      isDefault: false
```

### Bloco obrigatório — AlertManager com email

Preencher com o email fornecido pelo usuário. Se não fornecido, usar placeholder `REPLACE_WITH_EMAIL` e documentar no OBSERVABILITY.md.

```yaml
alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 256Mi
  config:
    global:
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: '<email>'
      smtp_auth_username: '<email>'
      smtp_auth_password: 'REPLACE_WITH_GMAIL_APP_PASSWORD'
      smtp_require_tls: true
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: 'email-notifications'
    receivers:
      - name: 'null'
      - name: 'email-notifications'
        email_configs:
          - to: '<email>'
            send_resolved: true
    inhibit_rules:
      - source_matchers: ['severity="critical"']
        target_matchers: ['severity="warning"']
        equal: [alertname, namespace]
```

---

## Regras para values-loki-stack.yaml

```yaml
loki:
  persistence:
    enabled: true
    storageClassName: <storage-class-detectada>
    size: 10Gi
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 300m
      memory: 512Mi

promtail:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi

grafana:
  enabled: false   # já instalado via kube-prometheus-stack
```

---

## Regras para ServiceMonitor

O ServiceMonitor **não** deve usar o Service LoadBalancer existente (que pode não ter porta nomeada). Sempre criar um `<app>-metrics-service.yaml` separado:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <app>-metrics
  namespace: <namespace-app>
  labels:
    app: <app>-metrics
spec:
  type: ClusterIP
  selector:
    app: <app>     # seleciona os pods — tanto blue quanto green
  ports:
    - name: metrics
      port: <porta-da-app>
      targetPort: <porta-da-app>
```

ServiceMonitor correspondente:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: <app>
  namespace: <namespace-app>
spec:
  namespaceSelector:
    matchNames: [<namespace-app>]
  selector:
    matchLabels:
      app: <app>-metrics
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
```

---

## Regras para PrometheusRule

Sempre gerar as regras de alerta abaixo. Adaptar `namespace` ao namespace da app detectado.

**Pods:**
- `PodCrashLooping` — `rate(kube_pod_container_status_restarts_total{namespace="<ns>"}[5m]) > 0` por 5m → critical
- `PodNotReady` — `kube_pod_status_ready{namespace="<ns>", condition="true"} == 0` por 5m → critical

**HTTP (somente se app instrumentada):**
- `HighHTTPLatency` — P95 de `http_request_duration_seconds_bucket` > 2s por 5m → warning
- `HighHTTPErrorRate` — taxa de 5xx > 5% por 5m → warning

**Storage:**
- `PVCUsageHigh` — `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.8` por 5m → warning

---

## Comandos de instalação (sempre executar na sequência)

```bash
# 1. Verificar/instalar Helm
helm version || curl -fsSL https://get.helm.sh/helm-v3.21.0-linux-amd64.tar.gz | tar -xz -C /tmp && cp /tmp/linux-amd64/helm ~/bin/helm

# 2. Adicionar repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# 3. Namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# 4. Stack principal
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values k8s/monitoring/values-kube-prometheus-stack.yaml \
  --timeout 10m --wait

# 5. Loki
helm install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --values k8s/monitoring/values-loki-stack.yaml \
  --timeout 10m --wait

# 6. Manifests da app
kubectl apply -f k8s/monitoring/
```

Após a instalação, obter o IP do Grafana:
```bash
kubectl get svc kube-prometheus-stack-grafana -n monitoring
```

---

## Resumo final (sempre exibir após instalação)

```
## Observabilidade instalada

| Componente        | Status  | Detalhe                        |
|-------------------|---------|--------------------------------|
| Prometheus        | Running | Retenção 30d, PVC 20Gi         |
| Grafana           | Running | IP: <ip> — admin / <senha>     |
| AlertManager      | Running | Email: <email> (App Password pendente) |
| Loki              | Running | PVC 10Gi                       |
| Promtail          | Running | DaemonSet ativo                |
| <db>-exporter     | Running | Métricas de banco ativas       |
| ServiceMonitor    | Ativo   | Namespace: <namespace-app>     |

### Próximos passos obrigatórios
1. Alterar senha do Grafana no primeiro acesso
2. Configurar Gmail App Password (myaccount.google.com/apppasswords)
3. Validar targets em Prometheus → /targets
4. Após validação: desabilitar monitoramento nativo do provedor (se presente)
```

Após o resumo, sempre gerar `OBSERVABILITY.md` com a documentação completa seguindo a estrutura:
Contexto → Decisões arquiteturais → Arquitetura (diagrama ASCII) → Componentes → Arquivos → Acesso → Alertas → Configuração pós-instalação → Operações comuns → Pontos de atenção → Métricas disponíveis.
