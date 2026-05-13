# ---------------------------------------------------------------------------
# Managed API Connections — created via ARM because the azurerm provider
# does not have a native resource for Microsoft.Web/connections.
#
# The connection resources are created as plain managed API connections.
# Runtime authentication is then controlled from workflows/connections.json.
#
# connectionRuntimeUrl handling:
#   azuremonitorlogs — Managed Identity auth: URL is assigned at creation,
#                      captured via ARM reference() and managed by Terraform.
#   office365        — OAuth auth: URL only becomes meaningful after manual
#                      OAuth consent in the Azure Portal. Terraform intentionally
#                      leaves this blank and the pipeline syncs it post-consent.
# ---------------------------------------------------------------------------

locals {
  connection_outputs = jsondecode(
    azurerm_resource_group_template_deployment.connections.output_content
  )
}

# ---- Step 1: Connection resources (no dependency on Logic App) ----
resource "azurerm_resource_group_template_deployment" "connections" {
  name                = "${var.logic_app_name}-connections"
  resource_group_name = azurerm_resource_group.this.name
  deployment_mode     = "Incremental"

  parameters_content = jsonencode({
    location         = { value = var.location }
    connectionPrefix = { value = var.logic_app_name }
  })

  template_content = <<-TEMPLATE
    {
      "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
      "contentVersion": "1.0.0.0",
      "parameters": {
        "location":         { "type": "String" },
        "connectionPrefix": { "type": "String" }
      },
      "variables": {
        "azuremonitorlogsName": "[concat(parameters('connectionPrefix'), '-azuremonitorlogs-mi')]",
        "office365Name":        "[concat(parameters('connectionPrefix'), '-office365-v2')]"
      },
      "resources": [
        {
          "type": "Microsoft.Web/connections",
          "apiVersion": "[providers('Microsoft.Web','connections').apiVersions[0]]",
          "name": "[variables('azuremonitorlogsName')]",
          "location": "[parameters('location')]",
          "kind": "V2",
          "properties": {
            "displayName": "Azure Monitor Logs",
            "alternativeParameterValues": {},
            "api": {
              "id": "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), 'azuremonitorlogs')]"
            },
            "authenticatedUser": {},
            "connectionState": "Enabled",
            "customParameterValues": {},
            "parameterValueSet": {
              "name": "managedIdentityAuth",
              "values": {}
            }
          }
        },
        {
          "type": "Microsoft.Web/connections",
          "apiVersion": "[providers('Microsoft.Web','connections').apiVersions[0]]",
          "name": "[variables('office365Name')]",
          "location": "[parameters('location')]",
          "kind": "V2",
          "properties": {
            "alternativeParameterValues": {},
            "displayName": "Office 365 Outlook",
            "api": {
              "id": "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), 'office365')]"
            },
            "authenticatedUser": {},
            "connectionState": "Enabled",
            "customParameterValues": {}
          }
        }
      ],
      "outputs": {
        "azuremonitorlogsConnectionId": {
          "type": "String",
          "value": "[resourceId('Microsoft.Web/connections', variables('azuremonitorlogsName'))]"
        },
        "azuremonitorlogsConnectionName": {
          "type": "String",
          "value": "[variables('azuremonitorlogsName')]"
        },
        "azuremonitorlogsConnectionRuntimeUrl": {
          "type": "String",
          "value": "[reference(variables('azuremonitorlogsName'), '2018-07-01-preview').connectionRuntimeUrl]"
        },
        "office365ConnectionId": {
          "type": "String",
          "value": "[resourceId('Microsoft.Web/connections', variables('office365Name'))]"
        },
        "office365ConnectionName": {
          "type": "String",
          "value": "[variables('office365Name')]"
        }
      }
    }
  TEMPLATE
}

# ---- Step 2: Access policies — grants the Logic App identity permission to
#              call each V2 connection at runtime. Requires the Logic App's
#              system-assigned principal_id, so this runs after main.tf. ----
resource "azurerm_resource_group_template_deployment" "connection_access_policies" {
  name                = "${var.logic_app_name}-connection-access-policies"
  resource_group_name = azurerm_resource_group.this.name
  deployment_mode     = "Incremental"

  # Explicit dependency ensures the Logic App exists before we read its identity.
  depends_on = [azurerm_logic_app_standard.this]

  parameters_content = jsonencode({
    location             = { value = var.location }
    tenantId             = { value = data.azurerm_client_config.current.tenant_id }
    principalId          = { value = azurerm_logic_app_standard.this.identity[0].principal_id }
    policyName           = { value = var.logic_app_name }
    azuremonitorlogsName = { value = local.connection_outputs.azuremonitorlogsConnectionName.value }
    office365Name        = { value = local.connection_outputs.office365ConnectionName.value }
  })

  template_content = <<-TEMPLATE
    {
      "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
      "contentVersion": "1.0.0.0",
      "parameters": {
        "location":             { "type": "String" },
        "tenantId":             { "type": "String" },
        "principalId":          { "type": "String" },
        "policyName":           { "type": "String" },
        "azuremonitorlogsName": { "type": "String" },
        "office365Name":        { "type": "String" }
      },
      "resources": [
        {
          "type": "Microsoft.Web/connections/accessPolicies",
          "apiVersion": "2016-06-01",
          "name": "[concat(parameters('azuremonitorlogsName'), '/', parameters('policyName'))]",
          "location": "[parameters('location')]",
          "properties": {
            "principal": {
              "type": "ActiveDirectory",
              "identity": {
                "tenantId": "[parameters('tenantId')]",
                "objectId": "[parameters('principalId')]"
              }
            }
          }
        },
        {
          "type": "Microsoft.Web/connections/accessPolicies",
          "apiVersion": "2016-06-01",
          "name": "[concat(parameters('office365Name'), '/', parameters('policyName'))]",
          "location": "[parameters('location')]",
          "properties": {
            "principal": {
              "type": "ActiveDirectory",
              "identity": {
                "tenantId": "[parameters('tenantId')]",
                "objectId": "[parameters('principalId')]"
              }
            }
          }
        }
      ]
    }
  TEMPLATE
}