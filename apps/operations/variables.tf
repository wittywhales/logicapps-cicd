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

variable "vnet_integration_subnet_id" {
  description = "Resource ID of the delegated subnet for outbound VNet integration. Set to null to disable."
  type        = string
  default     = null
}
