environment          = "dev"
location             = "West Europe"
resource_group_name  = "rg-logicapp-dev"
logic_app_name       = "la-ingestionspike-dev"
storage_account_name = "stlaingestiondev01"

# Target Log Analytics workspace for monitoring
la_target_subscription_id = "fc33352a-e8eb-40e6-8e61-416a39f31865"
la_target_resource_group  = "rg-logicapptest-la"
la_target_workspace_name  = "epamlaw"

# Notification settings
alert_email_recipients   = "sravya_reddyvari@epam.com"
log_analytics_portal_url = ""
