output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.this.name
}

output "logic_app_name" {
  description = "Name of the Logic App Standard resource"
  value       = azurerm_logic_app_standard.this.name
}

output "logic_app_default_hostname" {
  description = "Default hostname of the Logic App"
  value       = azurerm_logic_app_standard.this.default_hostname
}

output "logic_app_principal_id" {
  description = "Principal ID of the Logic App system-assigned managed identity"
  value       = azurerm_logic_app_standard.this.identity[0].principal_id
}

output "azuremonitorlogs_connection_id" {
  description = "Resource ID of the Azure Monitor Logs API connection"
  value       = local.connection_outputs.azuremonitorlogsConnectionId.value
}

output "azuremonitorlogs_connection_name" {
  description = "Name of the Azure Monitor Logs API connection"
  value       = local.connection_outputs.azuremonitorlogsConnectionName.value
}
output "azuremonitorlogs_connection_runtime_url" {
  description = "Runtime URL of the Azure Monitor Logs API connection (Managed Identity — available immediately)"
  value       = local.connection_outputs.azuremonitorlogsConnectionRuntimeUrl.value
}
output "office365_connection_id" {
  description = "Resource ID of the Office 365 API connection"
  value       = local.connection_outputs.office365ConnectionId.value
}

output "office365_connection_name" {
  description = "Name of the Office 365 API connection"
  value       = local.connection_outputs.office365ConnectionName.value
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.this.name
}