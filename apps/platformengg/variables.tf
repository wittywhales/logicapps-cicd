variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev, prod."
  }
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "West Europe"
}

variable "logic_app_name" {
  description = "Name of the Logic App Standard resource"
  type        = string
}

variable "storage_account_name" {
  description = "Name of the storage account for Logic App runtime"
  type        = string
}

variable "la_target_subscription_id" {
  description = "Subscription ID of the Log Analytics workspace to monitor"
  type        = string
}

variable "la_target_resource_group" {
  description = "Resource group of the Log Analytics workspace to monitor"
  type        = string
}

variable "la_target_workspace_name" {
  description = "Name of the Log Analytics workspace to monitor"
  type        = string
}

variable "alert_email_recipients" {
  description = "Email recipients for spike alert notifications"
  type        = string
}

variable "log_analytics_portal_url" {
  description = "Direct link to the Log Analytics workspace in Azure Portal"
  type        = string
  default     = ""
}

variable "vnet_integration_subnet_id" {
  description = "Resource ID of the delegated subnet for outbound VNet integration. Set to null to disable."
  type        = string
  default     = null
}
