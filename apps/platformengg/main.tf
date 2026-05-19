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

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Target Log Analytics Workspace (for RBAC assignment)
# ---------------------------------------------------------------------------
data "azurerm_log_analytics_workspace" "target" {
  name                = var.la_target_workspace_name
  resource_group_name = var.la_target_resource_group
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
    # --- Managed API Connections: Azure Monitor Logs ---
    "AZUREMONITORLOGS_API_ID"                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/azuremonitorlogs"
    "AZUREMONITORLOGS_CONNECTION_ID"         = local.connection_outputs.azuremonitorlogsConnectionId.value
    "AZUREMONITORLOGS_CONNECTION_RUNTIMEURL" = local.connection_outputs.azuremonitorlogsConnectionRuntimeUrl.value

    # --- Managed API Connections: Office 365 ---
    "OFFICE365_API_ID"                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/office365"
    "OFFICE365_CONNECTION_ID"         = local.connection_outputs.office365ConnectionId.value
    "OFFICE365_CONNECTION_RUNTIMEURL" = local.connection_outputs.office365ConnectionRuntimeUrl.value

    # --- Workflow Configuration ---
    "LA_TARGET_SUBSCRIPTION_ID" = var.la_target_subscription_id
    "LA_TARGET_RESOURCE_GROUP"  = var.la_target_resource_group
    "LA_TARGET_WORKSPACE_NAME"  = var.la_target_workspace_name
    "ALERT_EMAIL_RECIPIENTS"    = var.alert_email_recipients
    "LOG_ANALYTICS_PORTAL_URL"  = var.log_analytics_portal_url
    "ENVIRONMENT"               = var.environment
  }
}

# ---------------------------------------------------------------------------
# RBAC — Grant Logic App MSI read access to the target workspace
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "azuremonitorlogs_reader" {
  scope                = data.azurerm_log_analytics_workspace.target.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = module.logic_app.logic_app_principal_id
}
