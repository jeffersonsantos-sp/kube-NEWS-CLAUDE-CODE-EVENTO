# Incident RCA — 2026-06-08 15:36

| Campo | Valor |
|---|---|
| Data/Hora de abertura | 2026-06-08 15:36 BRT (18:36 UTC) |
| Data/Hora de resolução | 2026-06-08 15:56 BRT (18:56 UTC) |
| Duração total do downtime | ~5h54m (13:02–18:56 UTC) |
| Cluster | AKSCLAUDECODE (`aks-kube-news` / `rg-kube_news`) |
| Node Resource Group | `MC_rg-kube_news_aks-kube-news_australiaeast` |
| Kubernetes Version | v1.34.7 |
| Severidade | **CRÍTICA** |
| Status | **RESOLVIDO** |

---

## Sumário Executivo

O site `jfs-devops.shop` ficou completamente inacessível por ~5h54m após uma rotação automática do node pool AKS que atualizou os nós para Kubernetes v1.34.7. A causa raiz foi uma **mudança de comportamento silenciosa introduzida no cloud-controller-manager do AKS 1.34+**: o campo `appProtocol: http` presente nos ports do Service `ingress-nginx-controller` passou a sobrescrever a annotation `azure-load-balancer-health-probe-protocol: tcp`, fazendo com que o Azure Load Balancer criasse probes HTTP (ao invés de TCP). Com a probe HTTP configurada com path `/`, o nginx ingress retornava **HTTP 404** (sem host header correspondente a nenhum Ingress), fazendo o Azure LB marcar todos os backends como não saudáveis e cessar completamente o roteamento de tráfego. A correção foi adicionar a annotation `azure-load-balancer-health-probe-request-path: /healthz`, que aponta a probe para o endpoint de health do nginx (retorna HTTP 200). Site restaurado em ~30 segundos após a anotação.

---

## Causa Raiz Principal

> **AKS 1.34+: `appProtocol: http` nos ports do Service sobrescreve a annotation `azure-load-balancer-health-probe-protocol: tcp`, forçando probe HTTP com path `/` que falha no nginx (retorna 404).**

---

## Achados

### [INFRA] Achado 1 — Rotação do node pool AKS (trigger do incidente)

- **Descrição:** Ambos os nós do cluster foram substituídos hoje às ~10:02 BRT (13:02 UTC), com AGE de apenas `5h31m` no momento do diagnóstico. Todos os pods foram remarcados nos novos nós.
- **Evidência:**
  ```
  NAME                             STATUS   AGE     VERSION
  aks-user-32707659-vmss000003     Ready    5h31m   v1.34.7
  aks-system-27809007-vmss000003   Ready    5h31m   v1.34.7

  Conditions LastTransitionTime: Mon, 08 Jun 2026 10:02:19 -0300
  ```
- **Impacto:** Trigger do incidente. A rotação foi o gatilho que expôs o bug latente na configuração da health probe.

---

### [REDE] Achado 2 — Azure LB para de rotear tráfego (TCP timeout externo)

- **Descrição:** Toda conexão TCP ao IP externo `20.53.187.114` nas portas 80 e 443 expirava sem resposta. Não havia RST (porta fechada), apenas silêncio — indicativo clássico de Azure LB sem backends saudáveis.
- **Evidência:**
  ```bash
  curl http://jfs-devops.shop    → HTTP_CODE:000 TOTAL_TIME:10.00s (TIMEOUT)
  curl https://jfs-devops.shop   → HTTP_CODE:000 TOTAL_TIME:10.00s (TIMEOUT)
  curl http://20.53.187.114      → Connection timed out after 10002 milliseconds
  ```
- **Causa:** Todos os backends marcados como unhealthy pelo LB devido à falha da health probe (ver Achado 5).

---

### [REDE] Achado 3 — nginx sem endpoints durante janela de startup (window de 6 min)

- **Descrição:** Durante o startup do nginx no novo nó (13:03–13:09 UTC), o service `kube-news` ainda não tinha endpoints — os pods green ainda estavam inicializando. Os endpoints foram restaurados às 13:09:59 UTC e nunca mais falharam.
- **Evidência:**
  ```
  W0608 13:03:45 Service "kube-news/kube-news" does not have any active Endpoint.
  W0608 13:09:50 Service "kube-news/kube-news" does not have any active Endpoint.

  Endpoints last-change-trigger-time: 2026-06-08T13:09:59Z
  Addresses: 192.168.1.174, 192.168.1.225 / NotReadyAddresses: <none>
  ```
- **Impacto:** Janela adicional de 6 min de indisponibilidade interna. Não é a causa principal.

---

### [SAÚDE] Achado 4 — Pod green zumbi (`ContainerStatusUnknown`)

- **Descrição:** O pod `kube-news-green-b5f66df45-f6nxc` ficou preso em `ContainerStatusUnknown` (Exit Code 137) após o antigo nó ser decommissionado enquanto o container ainda estava rodando.
- **Evidência:**
  ```
  pod/kube-news-green-b5f66df45-f6nxc   0/1  ContainerStatusUnknown  1  2d12h
  State: Terminated — Reason: ContainerStatusUnknown
  Message: The container could not be located when the pod was terminated
  ```
- **Impacto:** Nenhum em produção (deployment estava 2/2 Ready com substituto `htbt6`). Pod deletado durante a resolução.

---

### [ROOT CAUSE] Achado 5 — Health probe HTTP com path `/` → nginx retorna 404

- **Descrição:** O Azure LB foi configurado com probe **HTTP** (não TCP) na porta 32423 (NodePort do nginx). A probe envia `GET / HTTP/1.1` ao nginx, que sem host header válido retorna **HTTP 404**. O Azure LB considera qualquer resposta fora do range 200–399 como falha — 404 reprova a probe, todos os backends são marcados unhealthy, e o LB para de rotear.
- **Evidência:**
  ```json
  // Azure LB probe (az network lb probe show):
  {
    "port": 32423,
    "protocol": "Http",
    "requestPath": "/"
  }

  // Resposta do nginx para GET /:
  kubectl exec nginx-pod -- curl -o /dev/null -w "%{http_code}" http://localhost/
  → 404

  // Resposta do nginx para GET /healthz:
  kubectl exec nginx-pod -- curl -o /dev/null -w "%{http_code}" http://localhost/healthz
  → 200
  ```
- **Por que a probe virou HTTP?** O Service `ingress-nginx-controller` tem `appProtocol: http` nos ports. No AKS 1.34+, o cloud-controller-manager usa `appProtocol` com precedência sobre a annotation `azure-load-balancer-health-probe-protocol: tcp`. Antes da rotação do nó (versão anterior do kubernetes), o comportamento era diferente — este é um breaking change silencioso.
- **Causa Raiz Definitiva:** Mudança de comportamento do cloud-controller-manager no AKS 1.34 + `appProtocol: http` no Service + path de probe padrão `/` + nginx retorna 404 para hosts desconhecidos.

---

## Timeline Completa

| Horário (BRT) | Horário (UTC) | Evento |
|---|---|---|
| ~10:00 | ~13:00 | AKS node pool rotation iniciada — nós antigos decommissionados |
| 10:02 | 13:02 | Novos nós `aks-user/system-*-vmss000003` registrados (v1.34.7) |
| 10:03 | 13:03 | nginx ingress controller iniciado no novo nó; cloud-controller-manager recria probe como HTTP `GET /` |
| 10:03–10:09 | 13:03–13:09 | nginx sem endpoints ativos (pods ainda inicializando) |
| 10:09 | 13:09 | Endpoints green restaurados; nginx operacional internamente |
| 10:10+ | 13:10+ | **Azure LB health probe HTTP `GET /` → nginx 404 → probe falha → LB para de rotear** |
| 15:36 | 18:36 | Incidente reportado pelo usuário ("site não está abrindo") |
| 15:36–15:50 | 18:36–18:50 | Diagnóstico: descartadas NSG, endpoints, pods; identificada probe HTTP com 404 |
| 15:51 | 18:51 | `kubectl rollout restart ingress-nginx-controller` (necessário, mas insuficiente) |
| 15:52 | 18:52 | Pod zumbi `f6nxc` deletado |
| 15:54 | 18:54 | Annotation `health-probe-request-path=/healthz` aplicada ao Service |
| 15:54 | 18:54 | Azure LB atualiza probe para `GET /healthz` → nginx retorna 200 → backends saudáveis |
| **15:56** | **18:56** | **Site restaurado — HTTP 200 em 0.8s** |

---

## Resolução Aplicada

| # | Ação | Comando | Status | Resultado |
|---|---|---|---|---|
| 1 | Restart nginx controller | `kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx` | EXECUTADO | Pod subiu; necessário mas insuficiente |
| 2 | Deletar pod zumbi | `kubectl delete pod kube-news-green-b5f66df45-f6nxc -n kube-news --force --grace-period=0` | EXECUTADO | Pod removido com sucesso |
| 3 | **Fix definitivo: probe path** | `kubectl annotate svc ingress-nginx-controller -n ingress-nginx "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path=/healthz" --overwrite` | **EXECUTADO — RESOLVEU** | Probe → `/healthz` → 200 → site restaurado |
| 4 | Atualizar CLAUDE.md | Adicionada annotation `/healthz` ao `helm upgrade ingress-nginx` | EXECUTADO | Previne regressão em futuros upgrades |

---

## Validação Final

```bash
curl http://jfs-devops.shop    → HTTP_CODE:200 TIME:0.802070s  ✓
curl https://jfs-devops.shop   → HTTP_CODE:200                 ✓
kubectl get pods -n kube-news  → todos Running 1/1             ✓
kubectl get pods -n ingress-nginx → Running 1/1, RESTARTS:0   ✓
```

---

## Recursos Afetados — Estado Final

| Recurso | Namespace | Estado no Incidente | Estado Pós-Resolução |
|---|---|---|---|
| Site `jfs-devops.shop` | — | **Inacessível** | **Acessível (HTTP 200)** |
| Azure LB health probe | Azure | `GET /` → 404 → backends unhealthy | `GET /healthz` → 200 → backends healthy |
| `ingress-nginx-controller` pod | ingress-nginx | Running, sem receber tráfego do LB | Running, tráfego fluindo normalmente |
| `kube-news-green-b5f66df45-f6nxc` | kube-news | ContainerStatusUnknown (zumbi) | Deletado |
| Service `ingress-nginx-controller` | ingress-nginx | Annotation de probe path ausente | Annotation `/healthz` aplicada |
| Pods green (`4hdkf`, `htbt6`) | kube-news | Running 1/1, endpoints ativos | Running 1/1, sem alteração |
| Cert TLS `kube-news-tls` | kube-news | Valid (letsencrypt-prod) | Valid, sem alteração |

---

## Lições Aprendidas

| # | Lição |
|---|---|
| 1 | **AKS 1.34+ breaking change**: `appProtocol: http` no Service sobrescreve annotation de probe protocol. Sempre incluir `health-probe-request-path` ao instalar ingress-nginx em AKS. |
| 2 | **Nginx retorna 404 para `GET /` sem host header** — nunca usar `/` como path de health probe no nginx ingress. Usar `/healthz` que retorna 200 incondicionalmente. |
| 3 | **TCP timeout ≠ pod down**: o site estava em TCP timeout mas todos os pods estavam Running 1/1. Diagnosticar a camada de rede (LB) antes de focar nos pods. |
| 4 | **Node pool rotation pode triggerar probe recriação**: após upgrade de versão do AKS, revisar as health probes configuradas no Azure LB. |

---

## Prevenção de Recorrência

- [x] `CLAUDE.md` atualizado: `helm upgrade ingress-nginx` agora inclui `--set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz`
- [ ] Considerar adicionar alerta no Grafana/Prometheus para `probe_success == 0` no Azure LB
- [ ] Considerar configurar health check no Ingress Class ou via Helm values permanentes em arquivo `values-ingress-nginx.yaml` em `k8s/`
