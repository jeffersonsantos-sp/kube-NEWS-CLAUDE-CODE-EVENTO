# Infraestrutura Terraform — kube-news AKS (Azure)

**Projeto:** kube-news  
**Provedor:** Microsoft Azure  
**Região:** Australia East (`australiaeast`)  
**Gerenciamento:** Terraform >= 1.7 / Provider azurerm ~> 4.0  

---

## Visão Geral

Infraestrutura provisionada inteiramente via Terraform seguindo as melhores práticas:

- State remoto em Azure Blob Storage com versionamento e locking
- VNet explícita com subnets dimensionadas para as fases futuras
- AKS com Azure CNI Overlay, dois node pools separados e autoscaler
- Workload Identity habilitado desde a fase 1
- Sem credenciais hardcoded — autenticação via `az login` (local) ou Service Principal via variáveis de ambiente (CI/CD)

---

## Estrutura de Arquivos

```
infra/
├── bootstrap/                  # Executado UMA vez para criar o backend remoto
│   ├── main.tf                 # Resource Group + Storage Account + Container
│   ├── variables.tf
│   └── outputs.tf
│
├── modules/
│   ├── networking/             # VNet e subnets
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── aks/                    # Cluster AKS + node pools
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
│
├── main.tf                     # Orquestra Resource Group + módulos
├── variables.tf
├── outputs.tf
├── backend.tf                  # Configuração do backend remoto
├── versions.tf                 # Pin de versões + provider
└── terraform.tfvars.example    # Modelo para terraform.tfvars (não comitar)
```

---

## Recursos Provisionados

### Bootstrap (state)

| Recurso | Nome | Finalidade |
|---|---|---|
| Resource Group | `rg-tfstate-kube-news` | Contêiner do backend |
| Storage Account | `stkubenewstfstate` | Armazena o `.tfstate` |
| Blob Container | `tfstate` | Container privado com versionamento |

### Infra principal

| Recurso | Nome | Finalidade |
|---|---|---|
| Resource Group | `rg-kube_news` | Contêiner de todos os recursos de aplicação |
| Virtual Network | `vnet-kube-news` | Rede privada `10.0.0.0/16` |
| Subnet AKS | `snet-aks` | `10.0.0.0/22` — IPs para nodes do cluster |
| Subnet PostgreSQL | `snet-postgres` | `10.0.4.0/24` — delegada para PostgreSQL Flexible Server (fase 2) |
| Subnet Private Endpoints | `snet-private-ep` | `10.0.5.0/24` — reserva para ACR, Key Vault (fases futuras) |
| NSG | `nsg-aks` | Associado à subnet AKS para regras futuras |
| AKS Cluster | `aks-kube-news` | Cluster Standard Tier, Azure CNI Overlay |
| Node Pool System | `system` | 1–3 nodes `Standard_D2s_v3`, zonas 1 e 3, somente addons críticos |
| Node Pool User | `user` | 1–3 nodes `Standard_D2s_v3`, zonas 1 e 3, cargas de aplicação |

---

## Decisões de Arquitetura

| Decisão | Escolha | Justificativa |
|---|---|---|
| Backend de state | Azure Blob Storage | Locking nativo, versionamento, sem secrets locais |
| Plugin de rede | Azure CNI Overlay | Pods com IPs de overlay — não esgota IPs da VNet; compatível com AGIC e Private Endpoints |
| Política de rede | `azure` | Integrada nativamente, sem agente extra |
| Node pools | System + User separados | Sistema isola addons críticos; aplicação escala independentemente |
| Identidade | `SystemAssigned` | Sem credenciais para rotacionar; integração nativa com ACR e Key Vault futuros |
| OIDC Issuer | Habilitado | Pré-requisito para Workload Identity (fases 2 e 3) |
| OS upgrade | `NodeImage` | Patches de segurança automáticos nos nodes |
| Autoscaler | Habilitado (1–3 nodes) | Escala automática sem intervenção manual |

---

## Design de Rede

```
VNet: 10.0.0.0/16
│
├── snet-aks          10.0.0.0/22   → AKS nodes (1022 IPs disponíveis)
├── snet-postgres     10.0.4.0/24   → Delegada: Microsoft.DBforPostgreSQL/flexibleServers
└── snet-private-ep   10.0.5.0/24   → Private Endpoints (ACR, Key Vault, etc.)

Pod CIDR (overlay):   192.168.0.0/16  → não consome IPs da VNet
Service CIDR:         10.1.0.0/16
DNS Service IP:       10.1.0.10
```

---

## Availability Zones — Australia East

> **Atenção:** A região `australiaeast` suporta apenas as zonas **1 e 3**.  
> A zona 2 não está disponível nessa região.  
> Os node pools estão configurados com `zones = ["1", "3"]`.

---

## Sequência de Deploy

### Pré-requisito
```bash
az login
az account set --subscription "0e8a7592-106a-46f3-9e02-2ac20bc75b4a"
```

### Passo 1 — Bootstrap (executa uma única vez)
```bash
cd infra/bootstrap

# Criar terraform.tfvars com o subscription_id
echo 'subscription_id = "0e8a7592-106a-46f3-9e02-2ac20bc75b4a"' > terraform.tfvars

terraform init
terraform apply
```

Resultado: Resource Group `rg-tfstate-kube-news`, Storage Account `stkubenewstfstate` e Container `tfstate` criados no Azure.

### Passo 2 — Infra principal
```bash
cd infra

echo 'subscription_id = "0e8a7592-106a-46f3-9e02-2ac20bc75b4a"' > terraform.tfvars

terraform init      # conecta ao backend remoto criado no Passo 1
terraform plan      # revisar antes de aplicar
terraform apply
```

### Passo 3 — Conectar kubectl
```bash
# O output entrega o comando pronto:
terraform output get_credentials_command

# Exemplo do resultado:
az aks get-credentials \
  --resource-group rg-kube_news \
  --name aks-kube-news \
  --context AKSCLAUDECODE
```

---

## Outputs Disponíveis

| Output | Descrição |
|---|---|
| `resource_group_name` | Nome do Resource Group principal |
| `vnet_name` | Nome da VNet |
| `aks_subnet_id` | ID da subnet AKS |
| `postgres_subnet_id` | ID da subnet PostgreSQL (uso na fase 2) |
| `cluster_name` | Nome do cluster AKS |
| `node_resource_group` | Resource Group gerado automaticamente pelo AKS (`MC_*`) |
| `oidc_issuer_url` | URL do OIDC Issuer para Workload Identity |
| `kubelet_identity_object_id` | Object ID da identidade kubelet (para role assignment no ACR na fase 2) |
| `get_credentials_command` | Comando pronto para configurar o `kubectl` |

---

## Destruir a Infraestrutura

```bash
# Infra principal (AKS, VNet, RG)
cd infra
terraform destroy

# Bootstrap (state storage) — somente se quiser remover tudo
cd infra/bootstrap
terraform destroy
```

> Destruir o bootstrap antes da infra principal apaga o state remoto e impossibilita o gerenciamento via Terraform.

---

## Fase 2 — Recursos Planejados

A infraestrutura desta fase já está preparada para receber:

- **PostgreSQL Flexible Server** — subnet `snet-postgres` delegada e pronta
- **Azure Container Registry (ACR)** — `kubelet_identity_object_id` exportado para role assignment
- **Azure Key Vault** — subnet `snet-private-ep` reservada para Private Endpoint
- **Workload Identity** — OIDC Issuer habilitado no cluster
