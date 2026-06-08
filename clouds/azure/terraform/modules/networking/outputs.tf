output "vnet_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.this.name
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "postgres_subnet_id" {
  description = "Resource ID of the PostgreSQL delegated subnet"
  value       = azurerm_subnet.postgres.id
}

output "private_ep_subnet_id" {
  description = "Resource ID of the Private Endpoints subnet"
  value       = azurerm_subnet.private_endpoints.id
}
