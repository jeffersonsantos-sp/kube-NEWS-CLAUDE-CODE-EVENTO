output "resource_group_name" {
  description = "Name of the main resource group"
  value       = azurerm_resource_group.main.name
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.networking.vnet_name
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS subnet"
  value       = module.networking.aks_subnet_id
}

output "postgres_subnet_id" {
  description = "Resource ID of the PostgreSQL delegated subnet (ready for phase 2)"
  value       = module.networking.postgres_subnet_id
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "node_resource_group" {
  description = "Auto-generated resource group for AKS node resources"
  value       = module.aks.node_resource_group
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity (ready for phase 2)"
  value       = module.aks.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  description = "Kubelet identity object ID (needed for ACR role assignment in phase 2)"
  value       = module.aks.kubelet_identity_object_id
}

output "get_credentials_command" {
  description = "Command to configure kubectl with this cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name} --context AKSCLAUDECODE"
}
