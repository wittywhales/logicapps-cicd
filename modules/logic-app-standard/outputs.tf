output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "Resource ID of the resource group"
  value       = azurerm_resource_group.this.id
}

output "logic_app_name" {
  description = "Name of the Logic App Standard resource"
  value       = azurerm_logic_app_standard.this.name
}

output "logic_app_id" {
  description = "Resource ID of the Logic App Standard"
  value       = azurerm_logic_app_standard.this.id
}

output "logic_app_principal_id" {
  description = "Principal ID of the Logic App system-assigned managed identity"
  value       = azurerm_logic_app_standard.this.identity[0].principal_id
}

output "logic_app_tenant_id" {
  description = "Tenant ID of the Logic App managed identity"
  value       = azurerm_logic_app_standard.this.identity[0].tenant_id
}

output "logic_app_default_hostname" {
  description = "Default hostname of the Logic App"
  value       = azurerm_logic_app_standard.this.default_hostname
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.this.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.this.name
}

output "subscription_id" {
  description = "Current subscription ID (convenience output for connection templates)"
  value       = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  description = "Current tenant ID (convenience output for access policies)"
  value       = data.azurerm_client_config.current.tenant_id
}
