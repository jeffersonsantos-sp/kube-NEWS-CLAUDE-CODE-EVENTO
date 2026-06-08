output "storage_account_name" {
  description = "Name of the Storage Account holding the Terraform state"
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  description = "Name of the blob container for the state"
  value       = azurerm_storage_container.tfstate.name
}

output "resource_group_name" {
  description = "Resource group containing the state storage resources"
  value       = azurerm_resource_group.tfstate.name
}
