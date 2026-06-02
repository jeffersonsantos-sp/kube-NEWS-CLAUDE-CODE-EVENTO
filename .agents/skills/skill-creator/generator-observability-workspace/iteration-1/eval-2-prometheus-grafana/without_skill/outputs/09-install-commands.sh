#!/usr/bin/env bash
# =============================================================================
# install-monitoring.sh
#
# Script de instalação do stack de observabilidade do kube-news.
# Execute os blocos na ordem indicada.
# NÃO execute este script em produção sem revisar cada etapa.
# =============================================================================

set -euo pipefail

MONITORING_NS="monitoring"
KUBE_NEWS_NS="kube-news"

# ---------------------------------------------------------------------------
# 1. Adicionar repositórios Helm
# ---------------------------------------------------------------------------
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# ---------------------------------------------------------------------------
# 2. Criar namespace monitoring
# ---------------------------------------------------------------------------
kubectl apply -f 00-namespace.yaml

# ---------------------------------------------------------------------------
# 3. Instalar kube-prometheus-stack (Prometheus + Grafana + AlertManager +
#    Node Exporter + kube-state-metrics)
# ---------------------------------------------------------------------------
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "${MONITORING_NS}" \
  --create-namespace \
  --values 01-values-kube-prometheus-stack.yaml \
  --wait --timeout 10m

# ---------------------------------------------------------------------------
# 4. Instalar loki-stack (Loki + Promtail)
# ---------------------------------------------------------------------------
helm upgrade --install loki-stack grafana/loki-stack \
  --namespace "${MONITORING_NS}" \
  --create-namespace \
  --values 02-values-loki-stack.yaml \
  --wait --timeout 5m

# ---------------------------------------------------------------------------
# 5. Aplicar recursos no namespace kube-news
# ---------------------------------------------------------------------------
kubectl apply -f 03-kube-news-metrics-service.yaml
kubectl apply -f 04-kube-news-servicemonitor.yaml
kubectl apply -f 05-postgres-exporter.yaml
kubectl apply -f 06-postgres-exporter-servicemonitor.yaml

# ---------------------------------------------------------------------------
# 6. Aplicar alertas e dashboard
# ---------------------------------------------------------------------------
kubectl apply -f 07-prometheus-rules.yaml
kubectl apply -f 08-grafana-dashboard-configmap.yaml

# ---------------------------------------------------------------------------
# 7. Verificar status
# ---------------------------------------------------------------------------
echo ""
echo "=== Pods no namespace monitoring ==="
kubectl get pods -n "${MONITORING_NS}"

echo ""
echo "=== Pods no namespace kube-news (exporter) ==="
kubectl get pods -n "${KUBE_NEWS_NS}" | grep exporter

echo ""
echo "=== ServiceMonitors registrados ==="
kubectl get servicemonitor -A

echo ""
echo "=== PrometheusRules registradas ==="
kubectl get prometheusrule -A

echo ""
echo "=== IP público do Grafana ==="
kubectl get svc -n "${MONITORING_NS}" kube-prometheus-stack-grafana \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo ""
echo "Grafana user: admin"
echo "Grafana pass: KubeNews@Monitoring2026  (altere no primeiro acesso)"
