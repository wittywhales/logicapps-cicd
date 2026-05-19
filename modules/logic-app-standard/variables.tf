variable "name" {
  description = "Base name for the Logic App and derived resources (ASP, storage, etc.)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "West Europe"
}

variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
}

variable "storage_account_name" {
  description = "Name of the storage account for Logic App runtime (must be globally unique, 3-24 lowercase alphanumeric)"
  type        = string
}

variable "app_settings" {
  description = "Additional app settings to merge with the base runtime settings. Use this for connection URLs, domain config, etc."
  type        = map(string)
  default     = {}
}

variable "workflows_dir" {
  description = "Absolute or relative path to the workflows directory to zip-deploy"
  type        = string
}

variable "vnet_integration_subnet_id" {
  description = "Resource ID of the delegated subnet (Microsoft.Web/serverFarms) for outbound VNet integration. When set, storage network rules restrict access to this subnet and all outbound traffic routes through the VNet. Set to null to disable."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
