terraform {
  backend "azurerm" {
    resource_group_name  = "rg-kube-news-tfstate"
    storage_account_name = "stkubenewstfstate2026"
    container_name       = "kubenews-tfstate"
    key                  = "prod/terraform.tfstate"
  }
}
