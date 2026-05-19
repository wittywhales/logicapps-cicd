terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
  # backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

# ---------------------------------------------------------------------------
# Logic App Standard — base infrastructure via shared module
# ---------------------------------------------------------------------------
module "logic_app" {
  source = "../../modules/logic-app-standard"

  name                        = var.logic_app_name
  location                    = var.location
  environment                 = var.environment
  storage_account_name        = var.storage_account_name
  workflows_dir               = "${path.module}/workflows"
  vnet_integration_subnet_id  = var.vnet_integration_subnet_id

  app_settings = {
    "ENVIRONMENT" = var.environment
  }
}
