terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
  # backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

data "azurerm_log_analytics_workspace" "target" {
  name                = var.la_target_workspace_name
  resource_group_name = var.la_target_resource_group
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    environment = var.environment
    project     = "logic-app-standard"
  }
}

# ---------------------------------------------------------------------------
# Storage Account — required for Logic App Standard runtime
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "this" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags = {
    environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# Log Analytics + Application Insights — observability
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.logic_app_name}-law"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags = {
    environment = var.environment
  }
}

resource "azurerm_application_insights" "this" {
  name                = "${var.logic_app_name}-ai"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags = {
    environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# App Service Plan — WorkflowStandard (WS1) SKU for Logic App Standard
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "this" {
  name                = "${var.logic_app_name}-asp"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Windows"
  sku_name            = "WS1"
  tags = {
    environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# Logic App Standard
# ---------------------------------------------------------------------------
#
# Dependency chain (avoids circular references):
#   1. connections ARM deployment  (standalone — no Logic App dependency)
#   2. Logic App                   (references connection outputs in app_settings)
#
resource "azurerm_logic_app_standard" "this" {
  name                       = var.logic_app_name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  version                    = "~4"
  app_service_plan_id        = azurerm_service_plan.this.id
  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    # --- Runtime ---
    "FUNCTIONS_WORKER_RUNTIME"     = "dotnet"
    "WEBSITE_NODE_DEFAULT_VERSION" = "~18"
    "NETFRAMEWORK_VERSION"         = "v8.0"

    # --- Observability ---
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string

    # --- Managed API Connections: Azure Monitor Logs ---
    # connectionRuntimeUrl is captured from ARM reference() at deploy time —
    # no pipeline step or ignore_changes needed for this connection.
    "AZUREMONITORLOGS_API_ID"                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/azuremonitorlogs"
    "AZUREMONITORLOGS_CONNECTION_ID"         = local.connection_outputs.azuremonitorlogsConnectionId.value
    "AZUREMONITORLOGS_CONNECTION_RUNTIMEURL" = local.connection_outputs.azuremonitorlogsConnectionRuntimeUrl.value

    # --- Managed API Connections: Office 365 ---
    # connectionRuntimeUrl is assigned by Azure at connection creation time,
    # available immediately in the ARM output. OAuth consent in the portal
    # is required to make the connection functional, but not to get the URL.
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

  tags = {
    environment = var.environment
  }
}

resource "azurerm_role_assignment" "azuremonitorlogs_reader" {
  scope                = data.azurerm_log_analytics_workspace.target.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_logic_app_standard.this.identity[0].principal_id
}

# ---------------------------------------------------------------------------
# Workflow Zip Deploy
#
# archive_file zips the workflows directory at plan time and computes a
# SHA256 hash. terraform_data only redeploys when the hash changes, so a
# pure infra-only apply (no workflow file changes) is a no-op here.
# ---------------------------------------------------------------------------
data "archive_file" "workflows" {
  type        = "zip"
  source_dir  = "${path.module}/../workflows"
  output_path = "${path.module}/../workflows.zip"
  excludes = [
    "local.settings.json",
    "workflow-designtime",
  ]
}

resource "terraform_data" "deploy_workflows" {
  triggers_replace = {
    workflows_hash = data.archive_file.workflows.output_sha256
  }

  depends_on = [azurerm_logic_app_standard.this]

  provisioner "local-exec" {
    command = <<-EOT
      az functionapp deployment source config-zip \
        --name "${azurerm_logic_app_standard.this.name}" \
        --resource-group "${azurerm_resource_group.this.name}" \
        --src "${data.archive_file.workflows.output_path}"
    EOT
  }
}
