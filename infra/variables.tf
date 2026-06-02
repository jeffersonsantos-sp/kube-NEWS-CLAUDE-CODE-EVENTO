variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "location" {
  type        = string
  description = "Azure region for all resources"
  default     = "australiaeast"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the main resource group"
  default     = "rg-kube_news"
}

variable "node_vm_size" {
  type        = string
  description = "VM size for AKS node pools"
  default     = "Standard_B2s_v2"
}

variable "system_node_min_count" {
  type        = number
  description = "Minimum nodes in the system pool"
  default     = 1
}

variable "system_node_max_count" {
  type        = number
  description = "Maximum nodes in the system pool"
  default     = 2
}

variable "user_node_min_count" {
  type        = number
  description = "Minimum nodes in the user pool"
  default     = 1
}

variable "user_node_max_count" {
  type        = number
  description = "Maximum nodes in the user pool"
  default     = 2
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default = {
    project     = "kube-news"
    environment = "prod"
    managed_by  = "terraform"
  }
}
