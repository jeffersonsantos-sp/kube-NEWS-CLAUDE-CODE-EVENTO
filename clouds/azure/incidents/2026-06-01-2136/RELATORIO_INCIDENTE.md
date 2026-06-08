# Relatório de Incidente — kube-news AKS
## Indisponibilidade Total da Aplicação após Migração de Cluster

| Campo | Valor |
|---|---|
| **ID do Incidente** | INC-2026-06-01-2136 |
| **Data de Abertura** | 2026-06-01 21:36 UTC |
| **Data de Encerramento** | 2026-06-01 21:44 UTC |
| **Duração do Impacto** | ~3 horas (18:30 – 21:44 UTC) |
| **Severidade** | CRÍTICA |
| **Status** | Resolvido |
| **Cluster Afetado** | `aks-kube-news` — Azure AKS, Australia East |
| **Aplicação** | kube-news (portal de notícias Node.js + PostgreSQL) |
| **Responsável** | Equipe DevOps / SRE |

---

## 1. Sumário Executivo

A aplicação **kube-news** ficou completamente indisponível por aproximadamente 3 horas após a migração do cluster Kubernetes para uma nova infraestrutura provisionada via Terraform na região **Australia East** (Azure AKS).

A causa raiz foi a ausência de um passo obrigatório no processo de migração: após o provisionamento do novo cluster (`terraform apply`), os manifestos da aplicação não foram reaplicados ao cluster. O namespace `kube-news` não existia, resultando em zero pods, zero serviços e aplicação inacessível.

A infraestrutura do cluster estava completamente saudável — o problema foi exclusivamente operacional, não de plataforma.

A correção foi aplicada em menos de 8 minutos após a detecção do incidente.

---

## 2. Contexto

### 2.1 Histórico do Projeto

O projeto **kube-news** é uma aplicação web de notícias desenvolvida em Node.js com banco de dados PostgreSQL, containerizada via Docker e projetada nativamente para Kubernetes. A aplicação possui:

- Endpoints de saúde (`/health`, `/ready`) mapeados para probes Kubernetes
- Endpoints de chaos engineering (`/unhealth`, `/unreadyfor/:seconds`)
- Métricas Prometheus em `/metrics`
- Estratégia de deploy Blue-Green

### 2.2 O que estava sendo feito no momento do incidente

Na data do incidente, a equipe realizava a **recriação completa da infraestrutura Kubernetes via Terraform**, como parte de uma iniciativa de infraestrutura-como-código. O processo incluiu:

1. Criação do backend remoto de state Terraform (Azure Blob Storage)
2. Provisionamento do Resource Group `rg-kube_news`
3. Provisionamento da VNet `vnet-kube-news` com subnets dimensionadas para fases futuras
4. Provisionamento do cluster AKS `aks-kube-news` com Azure CNI Overlay, dois node pools e autoscaler

Durante o provisionamento do AKS, um erro adicional foi identificado e corrigido:

> **Erro intermediário:** A região `australiaeast` suporta apenas as Availability Zones `1` e `3`. O código Terraform original especificava `zones = ["1", "2", "3"]`, causando erro `AvailabilityZoneNotSupported` da API do Azure. A correção foi aplicada nos dois node pools antes da reaplicação.

Após o `terraform apply` bem-sucedido do cluster, a equipe **não executou o `kubectl apply` dos manifestos da aplicação**, deixando o cluster vazio.

---

## 3. Timeline Detalhada

| Horário (UTC) | Evento |
|---|---|
| ~18:30 | `terraform apply` do bootstrap concluído — Storage Account `stkubenewstfstate` e container `tfstate` criados |
| ~18:35 | `terraform init` na pasta `infra/` concluído — backend remoto conectado |
| ~18:36 | Primeiro `terraform apply` da infra principal falha com `AvailabilityZoneNotSupported` (zona 2 não disponível em `australiaeast`) |
| ~18:38 | Correção aplicada: `zones = ["1", "3"]` nos dois node pools |
| ~18:40 | Segundo `terraform apply` iniciado |
| ~18:52 | `terraform apply` concluído — cluster `aks-kube-news` provisionado com sucesso |
| 18:52–21:36 | Cluster vazio. Aplicação indisponível. Namespace `kube-news` inexistente |
| 21:36 | Incidente detectado e diagnóstico iniciado |
| 21:36 | `kubectl get namespaces` confirma ausência do namespace `kube-news` |
| 21:36 | Causa raiz identificada: manifestos não reaplicados após recriação do cluster |
| 21:36 | `kubectl apply -f k8s/kube-news-blue.yaml` executado |
| 21:37 | Namespace, Secret, ConfigMap, PVC, Deployments e Services criados |
| 21:38 | Pod `postgres` em `Running` |
| 21:38–21:40 | Pods `kube-news-blue` em `CrashLoopBackOff` (race condition: app tentou conectar ao banco antes de estar pronto) |
| 21:41 | Kubernetes reinicia os pods automaticamente após postgres estabilizar |
| 21:44 | Todos os pods em `1/1 Running`. Aplicação acessível em `http://20.28.131.107` |

---

## 4. Análise Técnica

### 4.1 Infraestrutura Terraform Criada

| Recurso | Nome | Região | Status |
|---|---|---|---|
| Resource Group (state) | `rg-tfstate-kube-news` | australiaeast | Criado |
| Storage Account | `stkubenewstfstate` | australiaeast | Criado |
| Blob Container | `tfstate` | — | Criado |
| Resource Group (app) | `rg-kube_news` | australiaeast | Criado |
| Virtual Network | `vnet-kube-news` | australiaeast | Criado |
| Subnet AKS | `snet-aks` (`10.0.0.0/22`) | — | Criada |
| Subnet PostgreSQL | `snet-postgres` (`10.0.4.0/24`) | — | Criada (reserva fase 2) |
| Subnet Private Endpoints | `snet-private-ep` (`10.0.5.0/24`) | — | Criada (reserva fase 2) |
| NSG | `nsg-aks` | australiaeast | Criado |
| AKS Cluster | `aks-kube-news` | australiaeast | Criado |
| Node Pool System | `system` (1–3x `Standard_D2s_v3`) | Zonas 1 e 3 | Criado |
| Node Pool User | `user` (1–3x `Standard_D2s_v3`) | Zonas 1 e 3 | Criado |

### 4.2 Estado do Cluster no Momento do Incidente

```
$ kubectl get namespaces
NAME              STATUS   AGE
default           Active   166m
kube-node-lease   Active   166m
kube-public       Active   166m
kube-system       Active   166m
# kube-news AUSENTE

$ kubectl get all -n kube-news
No resources found in kube-news namespace.
```

### 4.3 Estado dos Nodes

```
NAME                             STATUS   ROLES   AGE    VERSION
aks-system-39531238-vmss000000   Ready    <none>  165m   v1.34.7
aks-user-32769649-vmss000000     Ready    <none>  160m   v1.34.7
```

Ambos os nodes saudáveis — confirma que o problema não era de infraestrutura.

### 4.4 Erro Intermediário — Availability Zones

```
Error: creating Kubernetes Cluster (aks-kube-news):
  "code": "AvailabilityZoneNotSupported",
  "message": "The zone(s) '2' for resource 'system' is not supported.
              The supported zones for location 'australiaeast' are '1,3'"
```

**Correção aplicada em `infra/modules/aks/main.tf`:**

```hcl
# Antes (incorreto)
zones = ["1", "2", "3"]

# Depois (correto para australiaeast)
zones = ["1", "3"]
```

### 4.5 Race Condition no Startup

Após o `kubectl apply`, os pods `kube-news-blue` entraram em `CrashLoopBackOff` (3 restarts) porque tentaram conectar ao PostgreSQL antes de ele estar pronto. Comportamento esperado e autorreparável — o Kubernetes reiniciou os pods automaticamente após o postgres estabilizar. Não foi necessária intervenção adicional.

---

## 5. Estado Final Após Correção

```
$ kubectl get pods,svc,pvc -n kube-news

NAME                                  READY   STATUS    RESTARTS
pod/kube-news-blue-75c4f47878-fks8c   1/1     Running   3
pod/kube-news-blue-75c4f47878-j7rnw   1/1     Running   3
pod/postgres-679866d69f-f2nrb         1/1     Running   0

NAME                TYPE           CLUSTER-IP    EXTERNAL-IP     PORT(S)
service/kube-news   LoadBalancer   10.1.125.62   20.28.131.107   80:31653/TCP
service/postgres    ClusterIP      10.1.19.112   <none>          5432/TCP

NAME                         STATUS   VOLUME                                   CAPACITY
persistentvolumeclaim/postgres-pvc   Bound    pvc-86e45585-b251-4350...   5Gi
```

**Aplicação acessível em:** `http://20.28.131.107`

---

## 6. Causa Raiz

> **O processo de recriação do cluster via Terraform não inclui o deploy dos manifestos da aplicação. Após qualquer `terraform apply` que recrie o cluster, os manifestos devem ser reaplicados manualmente ou via pipeline.**

O Terraform provisiona a infraestrutura (cluster, nodes, rede). Ele não conhece nem gerencia os recursos Kubernetes da aplicação (`Namespace`, `Deployment`, `Service`, `PVC`, etc.). Essa responsabilidade pertence ao processo de deploy da aplicação — que não foi executado.

---

## 7. Impacto

| Dimensão | Impacto |
|---|---|
| **Disponibilidade** | 100% de indisponibilidade por ~3 horas |
| **Dados** | Nenhum — dados do PVC preservados (novo PVC criado no novo cluster, sem dados históricos neste cluster) |
| **Usuários** | Todos os usuários afetados durante o período |
| **SLA** | Violação do SLA de 99.95% (AKS Standard Tier garante infraestrutura, não o deploy) |

---

## 8. Lições Aprendidas

| # | Lição | Ação Derivada |
|---|---|---|
| 1 | Terraform provisiona infraestrutura, não aplicações | Criar runbook de pós-provisionamento com `kubectl apply` obrigatório |
| 2 | `australiaeast` suporta apenas zonas 1 e 3 | Documentado e corrigido no código Terraform |
| 3 | Race condition postgres→app é esperada e autorreparável | Considerar `initContainer` para aguardar o banco nas próximas fases |
| 4 | Ausência de pipeline CI/CD amplifica o risco de esquecimento | Fase 3 da PROPOSTA prioriza automação do deploy pós-provisionamento |

---

## 9. Ações Corretivas

### Imediatas (concluídas)

- [x] `kubectl apply -f k8s/kube-news-blue.yaml` executado
- [x] Todos os pods em `Running`
- [x] Serviço `LoadBalancer` com IP externo atribuído
- [x] Correção das Availability Zones no Terraform (`["1", "3"]`)

### Curto Prazo

- [ ] Criar script `scripts/post-provision.sh` que executa o `kubectl apply` após `terraform apply`
- [ ] Adicionar verificação de `kubectl get ns kube-news` no processo de validação pós-deploy
- [ ] Documentar o processo completo de migração no `CLAUDE.md`

### Médio Prazo (Fase 3 — CI/CD)

- [ ] Implementar pipeline que automatiza `terraform apply` + `kubectl apply` em sequência
- [ ] Configurar alertas de disponibilidade no Azure Monitor para detectar ausência de pods em `Running`
- [ ] Adicionar `initContainer` nos pods da aplicação para aguardar o PostgreSQL antes de inicializar

---

## 10. Documentos Relacionados

| Documento | Localização |
|---|---|
| RCA Técnico | `incidents/2026-06-01-2136/INCIDENT_RCA.md` |
| Plano de Ação | `incidents/2026-06-01-2136/ACTION_PLAN.md` |
| Proposta de Arquitetura | `PROPOSTA-AZURE-AKS.md` |
| Documentação da Infraestrutura Terraform | `infra/INFRASTRUCTURE.md` |
| Manifestos Kubernetes | `k8s/kube-news-blue.yaml` |
