# Proposta de Arquitetura Cloud — kube-news no Azure AKS

**Documento:** Proposta Tecnica-Executiva  
**Versao:** 1.0  
**Data:** 25/05/2026  
**Classificacao:** Interno — Para Aprovacao da Diretoria  
**Preparado por:** Equipe de Engenharia / DevOps  

---

## 1. Resumo Executivo

O projeto **kube-news** e uma aplicacao web de noticias desenvolvida em Node.js com banco de dados PostgreSQL, empacotada em container Docker e projetada nativamente para execucao em ambiente Kubernetes. A aplicacao ja possui instrumentacao de monitoramento (Prometheus), endpoints de saude compatíveis com Kubernetes e suporte a testes de resiliencia.

Esta proposta apresenta a arquitetura recomendada para operacao da aplicacao no **Microsoft Azure**, utilizando o **Azure Kubernetes Service (AKS)** como plataforma de orquestracao de containers, complementado por servicos gerenciados de banco de dados, rede, seguranca e CI/CD.

A adocao desta arquitetura resulta em uma plataforma com:

- **Alta disponibilidade:** SLA de 99.95% (AKS) e 99.99% (banco de dados com HA zone-redundant)
- **Escalabilidade automatica** de pods e nos conforme demanda real
- **Seguranca em multiplas camadas**, desde protecao contra DDoS ate isolamento de rede privada
- **Deploy automatizado** via pipeline CI/CD integrado ao repositorio Git
- **Recuperacao automatica de falhas** sem intervencao manual

---

## 2. Problema

### 2.1 Contexto Atual

A aplicacao **kube-news** opera atualmente em ambiente local com `docker-compose`, adequado apenas para desenvolvimento. Esta abordagem apresenta limitacoes criticas para um ambiente de producao:

| Limitacao | Impacto |
|---|---|
| Ausencia de alta disponibilidade | Qualquer falha de servidor derruba a aplicacao completamente |
| Escalabilidade manual | Impossivel responder a picos de acesso de forma automatica |
| Backup e recuperacao nao gerenciados | Risco de perda de dados em caso de falha |
| Ausencia de SSL/TLS centralizado | Dados trafegeados sem criptografia padronizada |
| Deploy manual e propenso a erros | Tempo de inatividade durante atualizacoes |
| Sem monitoramento centralizado | Falhas descobertas apenas pelo usuario final |

### 2.2 Necessidade de Negocio

A organizacao necessita de uma infraestrutura que suporte o crescimento da plataforma de noticias com garantias formais de disponibilidade, seguranca adequada a dados de producao e processos de deploy que permitam evolucao contínua do produto sem interrupcao do servico.

---

## 3. Arquitetura Proposta

### 3.1 Visao Geral

A arquitetura adota o modelo **cloud-native gerenciado** na Microsoft Azure, onde cada componente critico e substituido por um servico gerenciado com SLA garantido pela Microsoft.

```
                        INTERNET
                            |
                  +-------------------+
                  |  Azure Front Door  |  WAF global + CDN + TLS + failover geografico
                  |  (Standard/Premium)|
                  +-------------------+
                            |
                  +-------------------+
                  |  Application       |  WAF regional L7 + Ingress HTTPS
                  |  Gateway WAF v2    |  Rate limiting + OWASP rules
                  +-------------------+
                            |
              +-----------------------------+
              |   Azure Kubernetes Service  |
              |   (AKS — Standard Tier)     |
              |                             |
              |  +----------+ +----------+  |
              |  |  Pod     | |  Pod     |  |  HPA: escala automatica
              |  | kube-news| | kube-news|  |  baseada em CPU, mem
              |  |  :8080   | |  :8080   |  |  e metricas Prometheus
              |  +----------+ +----------+  |
              |     Zona A        Zona B     |
              +-----------------------------+
                            |
              +-----------------------------+
              |  Azure DB para PostgreSQL   |
              |  Flexible Server            |
              |  (General Purpose, Zone-HA) |
              |  Primary [Zona A]           |
              |  Standby [Zona B] — sincrono|
              +-----------------------------+

  Servicos de suporte:
  +------------------+  +------------------+  +------------------+
  | Azure Container  |  | Azure Key Vault  |  | Azure Monitor    |
  | Registry (ACR)   |  | (Secrets/Certs)  |  | + Grafana + Prom |
  +------------------+  +------------------+  +------------------+
```

### 3.2 Componentes e Justificativas

#### Azure Kubernetes Service (AKS) — Plataforma de Execucao

O AKS e o servico gerenciado de Kubernetes da Microsoft Azure. A aplicacao kube-news foi desenvolvida nativamente para Kubernetes, evidenciado pelos endpoints `/health` e `/ready` (mapeados diretamente para `livenessProbe` e `readinessProbe`), pelos endpoints de chaos (`/unhealth`, `/unreadyfor/:seconds`) e pelo proprio nome do projeto.

- **Tier recomendado:** Standard (SLA de 99.95% com Availability Zones)
- **Node pool inicial:** 3 nos `Standard_D2s_v3` (2 vCPUs, 8 GB RAM cada) distribuidos em 2 zonas
- **Horizontal Pod Autoscaler (HPA):** escala pods automaticamente com base em CPU e nas metricas Prometheus ja expostas em `/metrics`
- **Cluster Autoscaler:** adiciona/remove nos conforme a carga total

#### Azure Database for PostgreSQL Flexible Server — Banco de Dados

Servico gerenciado de PostgreSQL com suporte a alta disponibilidade zone-redundant. Eliminando a necessidade de gerenciar o servidor de banco de dados, backups, patches e failover manualmente.

- **Tier:** General Purpose (obrigatorio para habilitar HA)
- **SKU inicial:** `Standard_D2ds_v4` (2 vCPUs, 8 GB RAM)
- **Alta Disponibilidade:** Zone-Redundant (standby em zona diferente, replicacao sincrona)
- **SLA com HA:** 99.99% de disponibilidade
- **RTO (tempo de recuperacao):** 60 a 120 segundos (automatico, sem intervencao manual)
- **RPO (perda maxima de dados):** Zero (replicacao sincrona confirmada antes do commit)
- **Backups:** automaticos com retencao configuravel de 7 a 35 dias (PITR)
- **SSL:** obrigatorio (`DB_SSL_REQUIRE=true`)
- **Acesso:** exclusivamente via Private Endpoint dentro da VNet

#### Azure Container Registry (ACR) — Repositorio de Imagens

Armazena as imagens Docker da aplicacao com seguranca e integracao nativa ao AKS.

- **Tier recomendado:** Standard (100 GiB incluidos, anonimous pull, zone redundancy)
- **Integracao AKS:** via Managed Identity (sem credenciais hardcoded)
- **Vulnerability scanning:** integrado ao Microsoft Defender for Containers

#### Azure Application Gateway WAF v2 — Seguranca de Entrada Regional

Load balancer de camada 7 com Web Application Firewall integrado. Protege contra ataques OWASP Top 10 antes que o trafego chegue aos pods.

- **WAF v2** com regras gerenciadas OWASP CRS
- Terminacao SSL centralizada
- Rate limiting e protecao contra bots
- Integrado ao AKS via Application Gateway Ingress Controller (AGIC)

#### Azure Front Door — CDN e Failover Global

Ponto de entrada global com distribuicao geografica, aceleracao de performance e failover automatico.

- **Tier recomendado:** Standard (custo menor) ou Premium (WAF managed rules OWASP)
- CDN para assets estaticos (CSS, imagens, SVGs ja presentes no projeto)
- Roteamento inteligente para menor latencia por regiao
- Failover automatico em caso de indisponibilidade regional

#### Azure Key Vault — Gerenciamento de Segredos

As credenciais do banco de dados (atualmente em variaveis de ambiente) e certificados TLS sao armazenados no Key Vault e injetados nos pods via CSI Driver — sem expor segredos em arquivos YAML ou logs de CI/CD.

#### Azure Monitor + Managed Prometheus + Azure Managed Grafana — Observabilidade

A aplicacao ja exporta metricas no formato Prometheus em `/metrics`. O Azure oferece coleta gerenciada dessas metricas sem necessidade de instalar agentes adicionais.

- **Azure Monitor:** coleta de logs e metricas de infraestrutura
- **Managed Prometheus:** scraping automatico do endpoint `/metrics` da aplicacao
- **Azure Managed Grafana:** dashboards para `http_requests_total`, latencia por rota, taxa de erros
- **Alertas:** configurados para CPU alta, taxa de erros acima de threshold e falhas de pod

#### Azure DevOps Pipelines — CI/CD

Pipeline de entrega continua que automatiza o ciclo: codigo -> build -> testes -> deploy.

```
git push (branch main)
  └► Azure Pipeline
       ├─ npm audit (seguranca de dependencias)
       ├─ docker build + push → ACR
       ├─ helm upgrade --install → AKS (staging)
       ├─ health check: /health + /ready
       └─ promote → producao (aprovacao manual ou automatica)
```

Estrategia de deploy: **Rolling Update** com `maxUnavailable: 0` (zero downtime).

### 3.3 Seguranca em Camadas

| Camada | Controle | Servico Azure |
|---|---|---|
| Rede perimetral | DDoS Protection, WAF global | Azure Front Door Premium |
| Rede regional | WAF OWASP L7, rate limiting | Application Gateway WAF v2 |
| Rede interna | Network Policies, isolamento de pods | AKS + Azure CNI |
| Banco de dados | Private Endpoint (sem IP publico) | PostgreSQL + Private Link |
| Imagens | Acesso via Managed Identity, scan de vulnerabilidades | ACR + Defender |
| Segredos | Vault centralizado, sem plaintext | Azure Key Vault + CSI |
| Container | Execucao como non-root (ja no Dockerfile) | AKS Pod Security |
| Transito | SSL/TLS obrigatorio end-to-end | Front Door + App GW + PostgreSQL |

### 3.4 Alta Disponibilidade e Failover

| Cenario de Falha | Mecanismo de Recuperacao | Tempo Estimado |
|---|---|---|
| Pod da aplicacao falha | Kubernetes reinicia automaticamente (liveness probe) | < 30 segundos |
| Node do cluster falha | Pods redistribuidos nos nos restantes | 1 a 2 minutos |
| Zona de disponibilidade cai | Pods e DB standby em zonas separadas absorvem o trafego | < 2 minutos |
| Banco de dados primario falha | Failover automatico para standby (Zone-HA) | 60 a 120 segundos |
| Deploy com bug critico | Rollback via `helm rollback` ou revert no Git | < 2 minutos |
| Regiao Azure inteira cai | Azure Front Door redireciona para regiao secundaria | 1 a 3 minutos |

---

## 4. Principais Riscos

| Risco | Probabilidade | Impacto | Mitigacao |
|---|---|---|---|
| Custo acima do orcado por crescimento de trafego | Media | Alto | Azure Cost Alerts + Budget limits + Spot nodes para ambientes nao-prod |
| Falha no pipeline de CI/CD bloqueando deploys | Baixa | Medio | Rollback manual via `helm rollback`; agentes self-hosted como fallback |
| Violacao de dados no banco | Muito Baixa | Muito Alto | Private Endpoint, SSL obrigatorio, RBAC restrito, auditoria habilitada |
| Indisponibilidade da regiao Azure primaria | Muito Baixa | Alto | Front Door com failover para regiao secundaria (geo-redundancy) |
| Imagem Docker com vulnerabilidade critica | Media | Alto | Scan automatico no ACR + Microsoft Defender for Containers + politica de atualizacao |
| Falta de conhecimento interno em Kubernetes | Alta (inicial) | Medio | Treinamento da equipe + documentacao operacional na Fase 1 |
| Sequelize `sync({ alter: true })` em producao | Media | Alto | Migrar para migrations explicitas (Sequelize Migrations) antes do go-live |

> **Atencao especial:** O codigo atual usa `seque.sync({ alter: true })` que altera o schema do banco automaticamente no startup. Este comportamento deve ser substituido por migrations controladas antes do ambiente de producao para evitar alteracoes involuntarias de schema durante rollouts.

---

## 5. Custos

> **Aviso:** Todos os valores abaixo sao estimativas baseadas em precos oficiais da Microsoft Azure coletados em maio de 2026 para a regiao **Brazil South** ou **East US**. Precos finais dependem de negociacao de contrato Enterprise, tier de suporte e consumo real. Utilize o **Azure Pricing Calculator** para simulacao precisa.

### 5.1 Custo Mensal Estimado — Ambiente de Producao

| Servico | Configuracao | Custo Est. (USD/mes) |
|---|---|---|
| AKS Standard — Control Plane | 1 cluster, Standard Tier | ~$73 |
| AKS Node Pool — 3 nos | 3x `Standard_D2s_v3` (Linux, pay-as-you-go) | ~$210 |
| PostgreSQL Flexible Server | GP `D2ds_v4`, Zone-HA (primary + standby) | ~$326 + storage |
| PostgreSQL Storage | 32 GB SSD + backups 7 dias | ~$10 |
| Azure Container Registry | Plano Standard (100 GiB incluidos) | ~$20 |
| Application Gateway WAF v2 | Fixed cost + CUs variaveis (trafego baixo/medio) | ~$334 |
| Azure Front Door | Standard (base fee + egress estimado 100 GB) | ~$43 |
| Azure Key Vault | 1 vault, < 10.000 operacoes/mes | ~$5 |
| Azure Monitor / Log Analytics | Ingestao estimada 2 GB/dia | ~$15 |
| Azure DevOps Pipelines | 1 parallel job Microsoft-hosted | $0 (1.800 min/mes gratuitos) |
| **TOTAL ESTIMADO** | | **~$1.036/mes** |

### 5.2 Oportunidades de Reducao de Custo

| Estrategia | Reducao Estimada |
|---|---|
| Reserved Instances 1 ano (VMs do node pool) | 30 a 40% no custo das VMs |
| Reserved Instances 1 ano (PostgreSQL) | 30 a 40% no compute do banco |
| Spot node pool para ambiente de staging | 60 a 80% no custo dos nos de staging |
| Azure Front Door Standard vs Premium | Economia de ~$287/mes (sem managed WAF rules) |
| Consolidar Application Gateway com Front Door WAF | Elimina $334/mes do App GW em cenarios simples |

**Custo estimado otimizado (com Reserved 1 ano + spot staging):**  
Producao: ~$700 a $800/mes USD

### 5.3 Custo de Implementacao (Unico)

| Item | Estimativa |
|---|---|
| Horas de engenharia DevOps (setup infraestrutura) | 40 a 60 horas |
| Horas de desenvolvimento (ajustes no codigo: migrations, SSL) | 8 a 16 horas |
| Treinamento da equipe operacional | 16 horas |
| Licenca Azure DevOps (ate 5 usuarios Basic) | Gratuito |

---

## 6. Cronograma de Implementacao

### Fase 1 — Fundacao e Infraestrutura (Semanas 1 a 3)

**Objetivo:** Provisionar a infraestrutura base e validar o funcionamento da aplicacao no AKS em ambiente de staging.

| Semana | Atividades |
|---|---|
| **1** | - Criacao do Resource Group e VNet na Azure |
| | - Provisionamento do AKS (Standard Tier, 2 nos iniciais, 2 AZs) |
| | - Criacao do ACR e integracao com AKS via Managed Identity |
| | - Criacao do Azure Key Vault e configuracao inicial de segredos |
| **2** | - Provisionamento do PostgreSQL Flexible Server (GP, sem HA inicialmente) |
| | - Configuracao de Private Endpoint para o banco |
| | - Build da imagem Docker e push para o ACR |
| | - Deploy manual inicial da aplicacao no AKS (staging) |
| **3** | - Configuracao do Application Gateway WAF v2 e Ingress Controller (AGIC) |
| | - Configuracao de TLS com certificado gerenciado |
| | - Validacao end-to-end: acesso HTTPS, conexao ao banco, metricas |
| | - Documentacao operacional do ambiente |

**Criterio de saida:** Aplicacao acessivel via HTTPS no ambiente de staging, metricas visiveis, banco conectado via SSL.

---

### Fase 2 — Producao, Seguranca e Observabilidade (Semanas 4 a 6)

**Objetivo:** Habilitar alta disponibilidade, ativar o ambiente de producao e configurar monitoramento completo.

| Semana | Atividades |
|---|---|
| **4** | - Ativacao de High Availability Zone-Redundant no PostgreSQL |
| | - Ajuste do codigo: substituicao do `sync({ alter: true })` por Sequelize Migrations |
| | - Configuracao do `DB_SSL_REQUIRE=true` via Key Vault |
| | - Configuracao do HPA (Horizontal Pod Autoscaler) baseado em CPU |
| **5** | - Configuracao do Azure Front Door (CDN + failover) |
| | - Integracao do Azure Monitor + Managed Prometheus com o endpoint `/metrics` |
| | - Criacao dos dashboards no Azure Managed Grafana |
| | - Configuracao de alertas: taxa de erro, CPU, pod restarts, disponibilidade do banco |
| **6** | - Configuracao do Cluster Autoscaler (scale out/in automatico de nos) |
| | - Expansao do node pool para 3 nos distribuidos em 3 AZs |
| | - Testes de failover: simulacao de falha de pod, node e banco |
| | - Uso dos endpoints de chaos (`/unhealth`, `/unreadyfor/:seconds`) para validar probes |
| | - Aprovacao formal e go-live para producao |

**Criterio de saida:** Producao ativa com HA habilitado, failover testado e validado, dashboards operacionais funcionando.

---

### Fase 3 — CI/CD, Otimizacao e Governanca (Semanas 7 a 10)

**Objetivo:** Automatizar o ciclo de entrega, otimizar custos e estabelecer praticas de governanca.

| Semana | Atividades |
|---|---|
| **7** | - Configuracao do Azure DevOps Pipelines (ou GitHub Actions) |
| | - Pipeline de build: `npm audit` + `docker build` + push ACR |
| | - Pipeline de deploy: `helm upgrade` no AKS com health check automatico |
| **8** | - Configuracao de ambientes separados: `dev`, `staging`, `prod` no pipeline |
| | - Aprovacao manual obrigatoria para promocao para `prod` |
| | - Configuracao de rollback automatico em caso de falha no health check pos-deploy |
| **9** | - Configuracao de Reserved Instances para VMs e PostgreSQL (reducao de custo) |
| | - Revisao de Network Policies (isolamento entre pods) |
| | - Configuracao de Pod Security Standards e auditoria do Key Vault |
| **10** | - Treinamento operacional da equipe: runbooks, resposta a incidentes, uso do Grafana |
| | - Revisao final de custos vs orcamento |
| | - Documentacao final de arquitetura e handover para operacoes |

**Criterio de saida:** Pipeline CI/CD funcionando do commit ao deploy em producao, equipe treinada, custos dentro do orcamento aprovado.

---

## 7. Referencias Oficiais

Todos os dados tecnicos e de preco apresentados neste documento foram obtidos das seguintes fontes oficiais da Microsoft, consultadas em **25 de maio de 2026**:

1. **AKS — Tiers de Preco e SLA**  
   https://learn.microsoft.com/en-us/azure/aks/free-standard-pricing-tiers  
   *(Atualizado em: janeiro de 2026)*

2. **AKS — Pagina de Precos Oficial**  
   https://azure.microsoft.com/en-us/pricing/details/kubernetes-service/

3. **AKS — SLA Oficial (versao v1.1)**  
   https://azure.microsoft.com/support/legal/sla/kubernetes-service/v1_1/

4. **PostgreSQL Flexible Server — Opcoes de Compute**  
   https://learn.microsoft.com/en-us/azure/postgresql/compute-storage/concepts-compute  
   *(Atualizado em: fevereiro de 2026)*

5. **PostgreSQL Flexible Server — Pagina de Precos**  
   https://azure.microsoft.com/en-us/pricing/details/postgresql/flexible-server/

6. **PostgreSQL Flexible Server — Alta Disponibilidade e Confiabilidade**  
   https://learn.microsoft.com/en-us/azure/reliability/reliability-database-postgresql  
   *(Atualizado em: maio de 2026)*

7. **Azure Container Registry — SKUs e Planos**  
   https://learn.microsoft.com/en-us/azure/container-registry/container-registry-skus  
   *(Atualizado em: marco de 2026)*

8. **Azure Container Registry — Precos**  
   https://azure.microsoft.com/en-us/pricing/details/container-registry/

9. **Application Gateway — Entendendo os Precos**  
   https://learn.microsoft.com/en-us/azure/application-gateway/understanding-pricing  
   *(Atualizado em: novembro de 2025)*

10. **Application Gateway — Pagina de Precos**  
    https://azure.microsoft.com/en-us/pricing/details/application-gateway/

11. **Azure Front Door — Entendendo os Precos**  
    https://learn.microsoft.com/en-us/azure/frontdoor/understanding-pricing  
    *(Atualizado em: setembro de 2025)*

12. **Azure Front Door — Pagina de Precos**  
    https://azure.microsoft.com/en-us/pricing/details/frontdoor/

13. **Azure DevOps Services — Precos**  
    https://azure.microsoft.com/en-us/pricing/details/devops/azure-devops-services/

14. **Azure DevOps Pipelines — Licenciamento de Parallel Jobs**  
    https://learn.microsoft.com/en-us/azure/devops/pipelines/licensing/concurrent-jobs

15. **Azure Virtual Machines Linux — Precos**  
    https://azure.microsoft.com/en-us/pricing/details/virtual-machines/linux/

16. **Azure Pricing Calculator (simulacao personalizada)**  
    https://azure.microsoft.com/pt-br/pricing/calculator/

---

*Este documento foi preparado com base em dados oficiais da Microsoft Azure. Os precos e SLAs estao sujeitos a alteracoes pela Microsoft. Recomenda-se validar os valores no Azure Pricing Calculator antes da aprovacao final do orcamento.*
