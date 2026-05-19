terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

data "azurerm_client_config" "current" {}

locals {
  base_tags = merge(
    {
      environment = var.environment
      managed_by  = "terraform"
    },
    var.tags
  )

  # Base app settings every Logic App Standard needs
  base_app_settings = merge(
    {
      "FUNCTIONS_WORKER_RUNTIME"     = "dotnet"
      "WEBSITE_NODE_DEFAULT_VERSION" = "~24"
      "NETFRAMEWORK_VERSION"         = "v8.0"

      # Observability
      "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.this.instrumentation_key
      "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.this.connection_string
    },
    # VNet content routing (only when VNet integration is enabled)
    var.vnet_integration_subnet_id != null ? { "WEBSITE_CONTENTOVERVNET" = "1" } : {}
  )
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  name     = "${var.name}-rg"
  location = var.location
  tags     = local.base_tags
}

# ---------------------------------------------------------------------------
# Storage Account — required for Logic App Standard runtime
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  # When VNet integration is enabled, restrict storage access to the integration
  # subnet only (+ Azure-internal service bypass for management plane traffic).
  dynamic "network_rules" {
    for_each = var.vnet_integration_subnet_id != null ? [1] : []
    content {
      default_action             = "Deny"
      bypass                     = ["AzureServices"]
      virtual_network_subnet_ids = [var.vnet_integration_subnet_id]
    }
  }

  tags = local.base_tags
}

# ---------------------------------------------------------------------------
# Log Analytics + Application Insights — observability
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name}-law"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.base_tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name}-ai"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.base_tags
}

# ---------------------------------------------------------------------------
# App Service Plan — WorkflowStandard (WS1) SKU for Logic App Standard
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "this" {
  name                = "${var.name}-asp"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Windows"
  sku_name            = "WS1"
  tags                = local.base_tags
}

# ---------------------------------------------------------------------------
# Logic App Standard
# ---------------------------------------------------------------------------
resource "azurerm_logic_app_standard" "this" {
  name                       = var.name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  version                    = "~4"
  app_service_plan_id        = azurerm_service_plan.this.id
  storage_account_name       = azurerm_storage_account.this.name
  storage_account_access_key = azurerm_storage_account.this.primary_access_key
  https_only                 = true

  site_config {
    vnet_route_all_enabled    = var.vnet_integration_subnet_id != null ? true : false
    use_32_bit_worker_process = false
  }

  # Outbound VNet integration — subnet must be delegated to Microsoft.Web/serverFarms
  virtual_network_subnet_id  = var.vnet_integration_subnet_id
  # Route content share traffic through the VNet when integration is enabled
  vnet_content_share_enabled = var.vnet_integration_subnet_id != null ? true : false

  identity {
    type = "SystemAssigned"
  }

  app_settings = merge(local.base_app_settings, var.app_settings)

  tags = local.base_tags
}

# ---------------------------------------------------------------------------
# Workflow Zip Deploy
#
# archive_file zips the workflows directory at plan time and computes a
# SHA256 hash. terraform_data only redeploys when the hash changes.
# ---------------------------------------------------------------------------
data "archive_file" "workflows" {
  type        = "zip"
  source_dir  = var.workflows_dir
  output_path = "${var.workflows_dir}/../workflows.zip"
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
    command = "az functionapp deployment source config-zip --name ${azurerm_logic_app_standard.this.name} --resource-group ${azurerm_resource_group.this.name} --src ${data.archive_file.workflows.output_path}"
  }
}
