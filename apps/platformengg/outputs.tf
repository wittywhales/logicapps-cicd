output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.logic_app.resource_group_name
}

output "logic_app_name" {
  description = "Name of the Logic App Standard resource"
  value       = module.logic_app.logic_app_name
}

output "logic_app_default_hostname" {
  description = "Default hostname of the Logic App"
  value       = module.logic_app.logic_app_default_hostname
}

output "logic_app_principal_id" {
  description = "Principal ID of the Logic App system-assigned managed identity"
  value       = module.logic_app.logic_app_principal_id
}
