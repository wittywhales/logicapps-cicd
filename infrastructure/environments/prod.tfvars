environment          = "prod"
location             = "West Europe"
resource_group_name  = "rg-logicapp-prod"
logic_app_name       = "la-ingestionspike-prod"
storage_account_name = "stlaingestionprod"

# Target Log Analytics workspace for monitoring
la_target_subscription_id = "02277fc5-a6c3-4631-9556-a586800e1675"
la_target_resource_group  = "rg-log-mgmt-prd-westeurope-01"
la_target_workspace_name  = "nbsapucscoms"

# Notification settings
alert_email_recipients   = "ies_cis_azure_engineering_all_org@novartis.com"
log_analytics_portal_url = "https://portal.azure.com#@f35a6974-607f-47d4-82d7-ff31d7dc53a5/blade/Microsoft_OperationsManagementSuite_Workspace/Logs.ReactView/resourceId/%2Fsubscriptions%2F02277fc5-a6c3-4631-9556-a586800e1675%2Fresourcegroups%2Frg-log-mgmt-prd-westeurope-01%2Fproviders%2Fmicrosoft.operationalinsights%2Fworkspaces%2Fnbsapucscoms/source/LogsBlade.AnalyticsShareLinkToQuery"
