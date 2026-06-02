#!/usr/bin/env bash
# install-commands.sh
# Sequência completa de comandos para instalar o stack de observabilidade
# no AKS para o projeto kube-news.
#
# NOTA: Este script é documentação executável. Revise cada passo antes
#       de executar em produção.
#
# Pré-requisitos:
#   - kubectl configurado e apontando para o cluster AKS correto
#   - helm >= 3.x instalado
#   - Namespace kube-news já existente com os recursos da aplicação

set -euo pipefail

# ─── Configuração ──────────────────────────────────────────────────────────────
NAMESPACE_MONITORING="monitoring"
RELEASE_PROMETHEUS="kube-prometheus-stack"
RELEASE_LOKI="loki-stack"
HELM_TIMEOUT="10m"

# ─── 1. Criar namespace de monitoramento ──────────────────────────────────────
kubectl create namespace "${NAMESPACE_MONITORING}" --dry-run=client -o yaml | kubectl apply -f -

# ─── 2. Adicionar repositórios Helm ───────────────────────────────────────────
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# ─── 3. Instalar kube-prometheus-stack (Prometheus + Grafana + AlertManager) ──
# NÃO EXECUTAR — apenas referência de comando
# helm upgrade --install "${RELEASE_PROMETHEUS}" prometheus-community/kube-prometheus-stack \
#   --namespace "${NAMESPACE_MONITORING}" \
#   --values k8s/monitoring/values-kube-prometheus-stack.yaml \
#   --timeout "${HELM_TIMEOUT}" \
#   --wait

# ─── 4. Instalar loki-stack (Loki + Promtail) ─────────────────────────────────
# NÃO EXECUTAR — apenas referência de comando
# helm upgrade --install "${RELEASE_LOKI}" grafana/loki-stack \
#   --namespace "${NAMESPACE_MONITORING}" \
#   --values k8s/monitoring/values-loki-stack.yaml \
#   --timeout "${HELM_TIMEOUT}" \
#   --wait

# ─── 5. Aplicar recursos no namespace kube-news ───────────────────────────────
# NÃO EXECUTAR — apenas referência de comando
# kubectl apply -f k8s/monitoring/postgres-exporter.yaml
# kubectl apply -f k8s/monitoring/postgres-exporter-servicemonitor.yaml
# kubectl apply -f k8s/monitoring/kube-news-metrics-service.yaml
# kubectl apply -f k8s/monitoring/kube-news-servicemonitor.yaml

# ─── 6. Aplicar regras de alerta ──────────────────────────────────────────────
# NÃO EXECUTAR — apenas referência de comando
# kubectl apply -f k8s/monitoring/prometheus-rules.yaml

# ─── 7. Verificar status ──────────────────────────────────────────────────────
echo "=== Verificação de status (somente leitura) ==="
echo "kubectl get pods -n ${NAMESPACE_MONITORING}"
echo "kubectl get servicemonitors -n kube-news"
echo "kubectl get prometheusrules -n ${NAMESPACE_MONITORING}"
echo "kubectl get svc -n ${NAMESPACE_MONITORING} | grep grafana"

# ─── 8. Obter IP do Grafana ───────────────────────────────────────────────────
echo ""
echo "Para obter o IP externo do Grafana após a instalação:"
echo "  kubectl get svc ${RELEASE_PROMETHEUS}-grafana -n ${NAMESPACE_MONITORING} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
echo ""
echo "Credenciais padrão do Grafana:"
echo "  Usuario: admin"
echo "  Senha: KubeNews@Monitoring2026"
echo ""
echo "IMPORTANTE: Altere a senha após o primeiro login!"
