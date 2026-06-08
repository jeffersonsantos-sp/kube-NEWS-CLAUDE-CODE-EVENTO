resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-kube-news"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-kube-news"
  sku_tier            = "Free"

  default_node_pool {
    name                         = "system"
    min_count                    = var.system_node_min_count
    max_count                    = var.system_node_max_count
    vm_size                      = var.node_vm_size
    vnet_subnet_id               = var.aks_subnet_id
    auto_scaling_enabled         = true
    only_critical_addons_enabled = true
    os_disk_size_gb              = 30
    os_disk_type                 = "Managed"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "10.1.0.0/16"
    dns_service_ip      = "10.1.0.10"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  role_based_access_control_enabled = true
  local_account_disabled            = false

  node_os_upgrade_channel = "NodeImage"

  tags = var.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.node_vm_size
  min_count             = var.user_node_min_count
  max_count             = var.user_node_max_count
  vnet_subnet_id        = var.aks_subnet_id
  auto_scaling_enabled  = true
  mode                  = "User"
  os_disk_size_gb       = 30
  os_disk_type          = "Managed"

  upgrade_settings {
    max_surge = "33%"
  }

  tags = var.tags
}
