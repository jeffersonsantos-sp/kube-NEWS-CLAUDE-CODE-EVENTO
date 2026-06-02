variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "aks_subnet_id" {
  type        = string
  description = "Resource ID of the subnet where AKS nodes will be placed"
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "system_node_min_count" {
  type    = number
  default = 1
}

variable "system_node_max_count" {
  type    = number
  default = 3
}

variable "user_node_min_count" {
  type    = number
  default = 1
}

variable "user_node_max_count" {
  type    = number
  default = 3
}

variable "tags" {
  type    = map(string)
  default = {}
}
