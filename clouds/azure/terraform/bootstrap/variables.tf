variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "location" {
  type        = string
  description = "Azure region for the state storage resources"
  default     = "australiaeast"
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique name for the Storage Account (3-24 chars, lowercase alphanumeric only)"
  default     = "stkubenewstfstate2026"
}

variable "tags" {
  type = map(string)
  default = {
    project    = "kube-news"
    managed_by = "terraform"
    purpose    = "tfstate"
  }
}
