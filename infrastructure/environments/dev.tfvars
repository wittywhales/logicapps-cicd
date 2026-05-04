environment          = "dev"
location             = "West Europe"
resource_group_name  = "rg-logicapp-dev"
logic_app_name       = "la-ingestionspike-dev"
storage_account_name = "stlaingestiondev"

# Target Log Analytics workspace for monitoring
la_target_subscription_id = "02277fc5-a6c3-4631-9556-a586800e1675"
la_target_resource_group  = "rg-log-mgmt-prd-westeurope-01"
la_target_workspace_name  = "nbsapucscoms"

# Notification settings
alert_email_recipients   = "your-dev-team@example.com"
log_analytics_portal_url = ""
