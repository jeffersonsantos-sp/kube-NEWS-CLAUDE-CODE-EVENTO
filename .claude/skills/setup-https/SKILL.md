---
name: setup-https
description: >
  Configura HTTPS em aplicações Kubernetes no Azure AKS usando NGINX Ingress Controller +
  cert-manager + Let's Encrypt. Aplica toda a sequência: instalação dos componentes via Helm,
  criação dos ClusterIssuers (staging e produção), Ingress resource com TLS, correção do
  health probe do Azure LB (problema conhecido de HTTP→TCP), validação do certificado staging
  antes de ir para produção, e migração do Service de LoadBalancer para ClusterIP.
  Use sempre que o usuário mencionar HTTPS, TLS, SSL, certificado, cadeado, Let's Encrypt,
  Ingress, domínio com HTTPS, ou quiser expor a aplicação com segurança — mesmo que não use
  a palavra "skill" ou "HTTPS" explicitamente. Também use quando o domínio estiver em HTTP
  e o usuário quiser "adicionar segurança" ou "configurar o domínio corretamente".
---

# Setup HTTPS — NGINX Ingress + cert-manager + Let's Encrypt (Azure AKS)

## Visão geral do que será feito

```
Antes:  DNS → IP antigo (LoadBalancer direto) → pods  [HTTP :80]
Depois: DNS → IP do Ingress → NGINX Ingress (TLS) → Service ClusterIP → pods  [HTTP + HTTPS]
```

## Pré-requisitos

- `kubectl` configurado com contexto AKS (`AKSCLAUDECODE`)
- `helm` disponível — no projeto fica em `~/bin/helm`; execute `export PATH="$HOME/bin:$PATH"`
- `az` CLI autenticado (necessário para corrigir o health probe do Azure LB)
- Domínio com acesso ao painel DNS (ex: Hostinger)
- Repos Helm necessários:

```bash
export PATH="$HOME/bin:$PATH"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

---

## Sequência de execução (ordem importa)

### Passo 1 — Reduzir TTL do DNS ANTES de tudo

No painel do provedor DNS (ex: Hostinger), localize o registro A do domínio e reduza o TTL para **300 segundos**. Aguarde o TTL atual expirar antes de continuar. Isso minimiza o downtime na troca de IP.

### Passo 2 — Instalar NGINX Ingress Controller

```bash
export PATH="$HOME/bin:$PATH"
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-protocol"=tcp \
  --kube-context AKSCLAUDECODE \
  --wait --timeout=5m
```

> **Por que a annotation `azure-load-balancer-health-probe-protocol=tcp`?**
> O Azure LB cria por padrão um health probe HTTP que envia `GET /` sem Host header para a porta do NGINX. O NGINX retorna 404, o Azure LB considera o backend unhealthy e descarta todo o tráfego externo. Forçar TCP evita esse problema. Se a annotation não propagar automaticamente, corrija via az CLI (ver seção "Problemas conhecidos").

Após a instalação, capture o IP do Ingress:

```bash
kubectl get service ingress-nginx-controller -n ingress-nginx \
  --context AKSCLAUDECODE \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Passo 3 — Instalar cert-manager

```bash
export PATH="$HOME/bin:$PATH"
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --kube-context AKSCLAUDECODE \
  --wait --timeout=5m
```

### Passo 4 — Criar ClusterIssuers (staging + produção)

Crie o arquivo `k8s/cert-issuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: SEU_EMAIL@dominio.com
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: SEU_EMAIL@dominio.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```

Aplique:

```bash
kubectl apply -f k8s/cert-issuer.yaml --context AKSCLAUDECODE
kubectl get clusterissuers --context AKSCLAUDECODE
# Esperado: READY=True para ambos
```

### Passo 5 — Criar Ingress resource (iniciando com staging)

Crie `k8s/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kube-news
  namespace: kube-news
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-staging
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - SEU_DOMINIO.com
      secretName: kube-news-tls
  rules:
    - host: SEU_DOMINIO.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kube-news
                port:
                  number: 80
```

> `ssl-redirect: "false"` mantém HTTP e HTTPS ativos simultaneamente. Mude para `"true"` se quiser forçar HTTPS.

Aplique:

```bash
kubectl apply -f k8s/ingress.yaml --context AKSCLAUDECODE
```

### Passo 6 — Atualizar DNS para o IP do Ingress

No painel DNS, troque o registro A do domínio do IP antigo para o IP do Ingress (obtido no Passo 2). Aguarde ~5 minutos (TTL configurado no Passo 1).

Confirme a propagação:

```bash
dig +short SEU_DOMINIO.com A
# Esperado: o IP do Ingress
```

### Passo 7 — Validar certificado staging

```bash
kubectl get certificate,certificaterequest,challenge -n kube-news --context AKSCLAUDECODE
```

Aguarde o challenge ir para `valid` e o Certificate para `READY=True`. Se o challenge ficar `invalid`, veja "Problemas conhecidos" abaixo.

### Passo 8 — Trocar para certificado de produção

Edite `k8s/ingress.yaml` e mude:

```yaml
cert-manager.io/cluster-issuer: letsencrypt-prod
```

Aplique e force a reemissão:

```bash
kubectl apply -f k8s/ingress.yaml --context AKSCLAUDECODE
kubectl delete secret kube-news-tls -n kube-news --context AKSCLAUDECODE
kubectl delete certificaterequest --all -n kube-news --context AKSCLAUDECODE
```

Aguarde `READY=True` com issuer `letsencrypt-prod`.

### Passo 9 — Migrar Service para ClusterIP

Em `k8s/kube-news-blue.yaml`, altere o Service:

```yaml
spec:
  type: ClusterIP   # era LoadBalancer
```

Aplique:

```bash
kubectl apply -f k8s/kube-news-blue.yaml --context AKSCLAUDECODE
```

### Passo 10 — Validar tudo

```bash
curl -sv https://SEU_DOMINIO.com/ 2>&1 | grep -E "issuer|subject|HTTP|SSL"
# Esperado: issuer Let's Encrypt, HTTP/2 200
```

---

## Problemas conhecidos

### Azure LB probe HTTP causa timeout externo (problema mais comum)

**Sintoma:** DNS correto, pods saudáveis, mas `curl` externo trava ou o challenge fica `invalid` com erro `Timeout during connect (likely firewall problem)`.

**Causa:** Azure LB usa probe HTTP na porta do NGINX. NGINX retorna 404, Azure considera unhealthy e não encaminha tráfego.

**Diagnóstico:**
```bash
az network lb probe list \
  --lb-name kubernetes \
  --resource-group MC_SEU_RESOURCE_GROUP \
  -o json | python3 -c "
import json,sys
for p in json.load(sys.stdin):
    print(p['name'], p['protocol'], p.get('requestPath','N/A'))
"
```

**Correção via az CLI** (quando a annotation não propagar automaticamente):
```bash
az network lb probe update \
  --lb-name kubernetes \
  --resource-group MC_SEU_RESOURCE_GROUP \
  --name NOME_DO_PROBE_80 \
  --protocol Tcp \
  --path ""

az network lb probe update \
  --lb-name kubernetes \
  --resource-group MC_SEU_RESOURCE_GROUP \
  --name NOME_DO_PROBE_443 \
  --protocol Tcp \
  --path ""
```

> O `--path ""` é obrigatório ao trocar para TCP — o Azure rejeita se o path não for nulo.

### Challenge fica `invalid` após DNS propagar

Force um retry deletando os objetos falhos:

```bash
kubectl delete certificaterequest,challenge --all -n kube-news --context AKSCLAUDECODE
# cert-manager recria automaticamente em segundos
```

### cert-manager em backoff (não recria challenge)

Force a reemissão via annotation temporária:

```bash
kubectl annotate certificate kube-news-tls -n kube-news \
  cert-manager.io/issue-temporary-certificate="true" --overwrite --context AKSCLAUDECODE
kubectl annotate certificate kube-news-tls -n kube-news \
  cert-manager.io/issue-temporary-certificate- --context AKSCLAUDECODE
```

### Helm install com estado `pending-install` corrompido

Se um install anterior falhou e deixou release presa:

```bash
export PATH="$HOME/bin:$PATH"
helm list --all -n ingress-nginx --kube-context AKSCLAUDECODE
helm uninstall ingress-nginx -n ingress-nginx --kube-context AKSCLAUDECODE
# Reinstalar normalmente
```

---

## Compatibilidade com Blue-Green

O mecanismo Blue-Green **não é afetado** por esta configuração. O Ingress aponta para o Service `kube-news`, e o `selector.version` dentro desse Service continua controlando qual slot (blue/green) recebe tráfego. O CD pipeline que faz `kubectl patch service kube-news` continua funcionando sem alterações.

```
Ingress → Service kube-news (selector: version=blue|green) → pods
```

---

## Arquivos gerados por esta skill

| Arquivo | Descrição |
|---|---|
| `k8s/cert-issuer.yaml` | ClusterIssuers staging + produção |
| `k8s/ingress.yaml` | Ingress com TLS para o domínio |
| `k8s/kube-news-blue.yaml` | Service alterado de LoadBalancer → ClusterIP |

## Helm releases instalados

| Release | Namespace | Chart |
|---|---|---|
| `ingress-nginx` | `ingress-nginx` | `ingress-nginx/ingress-nginx` |
| `cert-manager` | `cert-manager` | `jetstack/cert-manager` |

## Informações do ambiente atual (AKS AKSCLAUDECODE)

- IP do Ingress: `20.53.187.114`
- Domínio: `jfs-devops.shop`
- Certificado: Let's Encrypt prod, válido até 2026-09-01
- Resource group do AKS: `mc_rg-kube_news_aks-kube-news_australiaeast`
