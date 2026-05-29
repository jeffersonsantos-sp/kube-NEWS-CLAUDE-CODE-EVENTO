# Post-Mortem — Aplicação kube-news implantada no namespace incorreto

| Campo | Valor |
|---|---|
| **Data do Incidente** | 28/05/2026 |
| **Severidade** | Média |
| **Status** | Resolvido |
| **Duração** | ~30 minutos (detecção até resolução completa) |
| **Cluster** | AKSCLAUDECODE (AKS — Azure) |
| **Autor** | Jefferson |

---

## 1. Resumo Executivo

A aplicação `kube-news` e seu banco de dados `postgres` foram implantados no namespace `default` do cluster AKS em vez do namespace dedicado `kube-news`. Os manifestos aplicados eram de um diretório de backup (`k8s-bo/`), resultando em uma configuração incorreta: imagem errada, sem separação de ConfigMap/Secret, sem padrão Blue-Green e sem isolamento de namespace. O namespace `kube-news` existia no cluster mas estava vazio. O incidente foi detectado por inspeção manual e corrigido com a aplicação dos manifestos corretos do diretório `k8s/`.

---

## 2. Impacto

- Aplicação funcional mas fora do namespace correto, violando o isolamento de recursos e a arquitetura definida para o projeto.
- Imagem da aplicação incorreta (`fabricioveronez/imersao-kube-news:v1`) em vez da imagem do projeto (`updateinformatica/claude-devops:1.0`).
- Padrão Blue-Green não aplicado — somente 1 réplica em RollingUpdate simples.
- Secret com nome incorreto (`postgres-secret` em vez de `kube-news-secret`) e sem separação de ConfigMap.
- PVC do postgres no namespace errado (dados seriam perdidos em uma limpeza de namespace).
- O Service `kube-news` no `default` ficou com um IP externo diferente do esperado (`20.200.229.22`), potencialmente causando inconsistência em configurações de DNS/ingress externas.

---

## 3. Linha do Tempo

| Horário (UTC) | Evento |
|---|---|
| ~21:56 | Manifestos do diretório `k8s-bo/` aplicados ao cluster sem especificar namespace — recursos criados em `default` |
| ~22:00 | Namespace `kube-news` identificado como existente mas vazio |
| ~22:25 | Início da investigação: contexto do cluster, namespaces e recursos verificados via MCP Kubernetes |
| ~22:27 | Causa raiz identificada — comparação entre estado do cluster e manifestos em `k8s/` |
| ~22:28 | Plano de ação criado e apresentado |
| ~22:30 | Fase 1: Manifestos corretos de `k8s/kube-news-blue.yaml` aplicados no namespace `kube-news` |
| ~22:31 | Fase 2: Deployment `kube-news-green` e Service `kube-news-preview` aplicados |
| ~22:32 | Pods em CrashLoopBackOff por race condition com postgres (esperado no cold start) |
| ~22:33 | Todos os 5 pods em `1/1 Running` — aplicação estável |
| ~22:34 | Fase 3: Recursos do namespace `default` removidos (deployments, services, pvc, secret) |
| ~22:35 | Validação final: `default` limpo, `kube-news` com stack completo operacional |

---

## 4. Causa Raiz

**Aplicação dos manifestos do diretório errado sem especificação de namespace.**

O repositório contém dois conjuntos de manifestos:

| Diretório | Propósito | Namespace | Padrão |
|---|---|---|---|
| `k8s/` | Manifestos oficiais do projeto | `kube-news` (explícito) | Blue-Green, Secret/ConfigMap separados, PVC, probes |
| `k8s-bo/` | Arquivos de backup/legado | Nenhum (vai para `default`) | RollingUpdate simples, Secret monolítico |

O comando `kubectl apply -f k8s-bo/` foi executado sem `-n kube-news`, fazendo com que todos os recursos fossem criados no namespace padrão (`default`) do contexto atual.

---

## 5. Evidências Coletadas

### 5.1 Estado incorreto (namespace `default`)

```
NAME                             READY   STATUS    RESTARTS   AGE
pod/kube-news-76c78597bf-rwgj5   1/1     Running   3          7m20s
pod/postgres-6d6cd8469f-nrsk9    1/1     Running   0          7m18s

NAME                        READY   CONTAINERS   IMAGES
deployment.apps/kube-news   1/1     kube-news    fabricioveronez/imersao-kube-news:v1
deployment.apps/postgres    1/1     postgres     postgres:15-alpine
```

### 5.2 Namespace `kube-news` vazio

```
kubectl get all -n kube-news
(sem output — namespace existia mas estava vazio)
```

### 5.3 Divergência de configuração identificada

| Item | k8s-bo/ (INCORRETO) | k8s/ (CORRETO) |
|---|---|---|
| Imagem | `fabricioveronez/imersao-kube-news:v1` | `updateinformatica/claude-devops:1.0` |
| Secret | `postgres-secret` | `kube-news-secret` |
| ConfigMap | Não utilizado | `kube-news-config` |
| Réplicas | 1 | 2 blue + 2 green |
| Deployment | `kube-news` (simples) | `kube-news-blue` + `kube-news-green` |
| Service routing | Sem label `version` | `version: blue` (produção) / `version: green` (preview) |

---

## 6. Ações Corretivas Executadas

1. **Aplicado `k8s/kube-news-blue.yaml` no namespace `kube-news`**, criando:
   - `Namespace/kube-news`
   - `Secret/kube-news-secret`
   - `ConfigMap/kube-news-config`
   - `PersistentVolumeClaim/postgres-pvc` (5Gi)
   - `Deployment/postgres` com readiness/liveness probes
   - `Service/postgres` (ClusterIP)
   - `Deployment/kube-news-blue` (2 réplicas, imagem correta)
   - `Service/kube-news` (LoadBalancer → `version: blue`)

2. **Aplicado `k8s/kube-news-green.yaml` no namespace `kube-news`**, criando:
   - `Deployment/kube-news-green` (2 réplicas)
   - `Service/kube-news-preview` (ClusterIP → `version: green`)

3. **Removido do namespace `default`**:
   - `Deployment/kube-news`
   - `Deployment/postgres`
   - `Service/kube-news`
   - `Service/postgres`
   - `PersistentVolumeClaim/postgres-pvc`
   - `Secret/postgres-secret`

### Estado Final Validado

```
NAMESPACE: kube-news

NAME                                   READY   STATUS    RESTARTS
pod/kube-news-blue-74bdc8bd96-54dxp    1/1     Running   3
pod/kube-news-blue-74bdc8bd96-rwgfw    1/1     Running   3
pod/kube-news-green-599d4d8b59-5jzcr   1/1     Running   2
pod/kube-news-green-599d4d8b59-n4jqm   1/1     Running   2
pod/postgres-66779479f8-88brh          1/1     Running   0

NAME                  TYPE           EXTERNAL-IP      PORT(S)
kube-news             LoadBalancer   20.200.201.126   80:30182/TCP
kube-news-preview     ClusterIP      <none>           8080/TCP
postgres              ClusterIP      <none>           5432/TCP

deployment.apps/kube-news-blue    2/2  updateinformatica/claude-devops:1.0
deployment.apps/kube-news-green   2/2  updateinformatica/claude-devops:1.0
deployment.apps/postgres          1/1  postgres:15-alpine
```

**URL de produção:** `http://20.200.201.126`

---

## 7. Lições Aprendidas

### O que foi bem
- A causa raiz foi identificada rapidamente ao comparar o estado do cluster com os manifestos no repositório.
- O namespace `kube-news` já existia, o que evitou erros de permissão na aplicação dos manifestos corretos.
- Os manifestos em `k8s/` estavam completos e prontos para uso imediato.

### O que falhou
- Nenhuma validação de namespace foi feita antes de executar o `kubectl apply`.
- O diretório `k8s-bo/` (backup/legado) existe no repositório sem nenhuma proteção ou aviso contra uso acidental.
- Não há um processo documentado de deploy que especifique qual diretório e namespace usar.
- O contexto kubectl (`default`) não estava configurado para o namespace `kube-news`, o que permitiu o deploy silencioso no namespace errado.

---

## 8. Ações Preventivas Recomendadas

### Imediatas
- [ ] Remover ou mover o diretório `k8s-bo/` para fora do repositório (ou para uma branch de arquivo), evitando uso acidental.
- [ ] Adicionar um `README` ou `DEPLOY.md` documentando o processo correto de deploy: `kubectl apply -f k8s/ -n kube-news`.
- [ ] Configurar o contexto kubectl para usar `kube-news` como namespace padrão:
  ```bash
  kubectl config set-context --current --namespace=kube-news
  ```

### Médio Prazo
- [ ] Implementar um pipeline CI/CD (GitHub Actions / Azure DevOps) que aplique os manifestos automaticamente a partir de `k8s/` com namespace explícito, eliminando deploys manuais.
- [ ] Adicionar validação de namespace no pipeline via `kubectl apply --dry-run=server` antes de aplicar.
- [ ] Configurar RBAC para restringir deploys de aplicação ao namespace `kube-news`, impedindo criação acidental de recursos em `default`.

### Longo Prazo
- [ ] Adotar uma ferramenta de GitOps (ArgoCD ou Flux) para garantir que o estado do cluster sempre reflita o repositório — desviações são detectadas e alertadas automaticamente.
- [ ] Implementar alertas de monitoramento que detectem recursos de aplicação criados no namespace `default`.

---

## 9. Referências

| Item | Valor |
|---|---|
| Cluster | AKSCLAUDECODE |
| Resource Group | rg-claude-code |
| Namespace correto | `kube-news` |
| Manifestos corretos | `k8s/kube-news-blue.yaml`, `k8s/kube-news-green.yaml` |
| Manifestos legados | `k8s-bo/` (não usar para deploy) |
| IP produção pós-correção | `20.200.201.126` |
| Imagem da aplicação | `updateinformatica/claude-devops:1.0` |
