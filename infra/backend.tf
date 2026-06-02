terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-kube-news"
    storage_account_name = "stkubenewstfstate"
    container_name       = "tfstate"
    key                  = "prod/terraform.tfstate"
  }
}
