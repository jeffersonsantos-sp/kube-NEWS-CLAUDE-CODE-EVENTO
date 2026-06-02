resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

module "networking" {
  source = "./modules/networking"

  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

module "aks" {
  source = "./modules/aks"

  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  aks_subnet_id         = module.networking.aks_subnet_id
  node_vm_size          = var.node_vm_size
  system_node_min_count = var.system_node_min_count
  system_node_max_count = var.system_node_max_count
  user_node_min_count   = var.user_node_min_count
  user_node_max_count   = var.user_node_max_count
  tags                  = var.tags
}
