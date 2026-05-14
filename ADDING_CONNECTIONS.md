# Adding a New API Connection

## How to discover connector properties

Before writing any code, query the managed API definition for the connector:

```bash
az rest --method get \
  --url "https://management.azure.com/subscriptions/<SUB>/providers/Microsoft.Web/locations/<REGION>/managedApis/<CONNECTOR>?api-version=2016-06-01" \
  --query "{
    authType: properties.connectionParameters.token.type,
    resourceId: properties.connectionParameters.token.oAuthSettings.properties.AzureActiveDirectoryResourceId,
    oboSupported: properties.connectionParameters.token.oAuthSettings.properties.IsOnbehalfofLoginSupported,
    parameterValueSets: properties.parameterValueSets
  }" -o json
```

Replace `<CONNECTOR>` with the connector name (e.g. `azuremonitorlogs`, `office365`, `keyvault`, `servicebus`).

---

## The four fields that drive every decision

| Field | What it tells you |
|---|---|
| `authType` | `oauthSetting` = OAuth/MSI possible. `apiKey` / `basicAuth` = no MSI, needs credentials. |
| `oboSupported` | `true` = On-Behalf-Of supported, so **managed identity works**. `false` = OAuth user consent only. |
| `resourceId` | The Azure AD audience for the token. Becomes `audience` in `connections.json`. |
| `parameterValueSets` | If it contains `managedIdentityAuth`, MSI is explicitly declared. If `null`, MSI may still work via V2 connection kind. |

### Reference: connectors already in this project

| | `azuremonitorlogs` | `office365` |
|---|---|---|
| `authType` | `oauthSetting` | `oauthSetting` |
| `oboSupported` | `true` | `true` |
| `resourceId` | `https://management.core.windows.net/` | `https://graph.microsoft.com` |
| `parameterValueSets` | `null` | `null` |
| **MSI works?** | Yes | No — requires a signed-in user mailbox |

> `office365` has `oboSupported: true` but MSI does not work for sending email because the connector requires a delegated user context (a real mailbox). OAuth consent is mandatory.

---

## Decision checklist

```
1. Query managedApis/<connector-name>

2. authType == oauthSetting?
   └─ No  → use parameterValues in connections.tf (API key / basic auth)
   └─ Yes → continue

3. oboSupported == true?
   └─ No  → OAuth user consent required, no MSI, treat like office365
   └─ Yes → MSI is viable, use parameterValueSet: managedIdentityAuth

4. Note resourceId
   → this is the audience in connections.json connectionProperties.authentication

5. Find the backend API the connector calls internally
   → add to additionalAudiences if different from resourceId
   → check connector docs or read the error message on first run

6. Assign RBAC role to the Logic App MSI on the target resource
```

---

## What to add and where

There are four files to update when adding a new connection.

### 1. `infrastructure/connections.tf`

Add the connection resource inside the ARM template in the existing
`azurerm_resource_group_template_deployment.connections` resource, and add its
name and ID to `outputs`. Then add its access policy inside
`connection_access_policies`.

**MSI connection (oboSupported: true):**

```json
{
  "type": "Microsoft.Web/connections",
  "apiVersion": "[providers('Microsoft.Web','connections').apiVersions[0]]",
  "name": "[variables('<connector>Name')]",
  "location": "[parameters('location')]",
  "kind": "V2",
  "properties": {
    "displayName": "<Human readable name>",
    "api": {
      "id": "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), '<connector>')]"
    },
    "parameterValueSet": {
      "name": "managedIdentityAuth",
      "values": {}
    }
  }
}
```

**OAuth / credential connection (oboSupported: false, or user-context required):**

```json
{
  "type": "Microsoft.Web/connections",
  "apiVersion": "[providers('Microsoft.Web','connections').apiVersions[0]]",
  "name": "[variables('<connector>Name')]",
  "location": "[parameters('location')]",
  "kind": "V2",
  "properties": {
    "displayName": "<Human readable name>",
    "api": {
      "id": "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), '<connector>')]"
    }
  }
}
```
No `parameterValueSet` — the connection will require manual authorization in the portal after creation.

Add to `outputs`:
```json
"<connector>ConnectionId": {
  "type": "String",
  "value": "[resourceId('Microsoft.Web/connections', variables('<connector>Name'))]"
},
"<connector>ConnectionName": {
  "type": "String",
  "value": "[variables('<connector>Name')]"
}
```

Add access policy inside `connection_access_policies` (required for all V2 connections):
```json
{
  "type": "Microsoft.Web/connections/accessPolicies",
  "apiVersion": "2016-06-01",
  "name": "[concat(parameters('<connector>Name'), '/', parameters('policyName'))]",
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
```

### 2. `infrastructure/main.tf`

Add app settings for the new connection and any required RBAC role assignment.

```hcl
# In app_settings (both MSI and OAuth connections):
"<CONNECTOR>_API_ID"                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/<connector>"
"<CONNECTOR>_CONNECTION_ID"         = local.connection_outputs.<connector>ConnectionId.value
"<CONNECTOR>_CONNECTION_RUNTIMEURL" = local.connection_outputs.<connector>ConnectionRuntimeUrl.value

# NOTE: No lifecycle.ignore_changes needed. The connectionRuntimeUrl is generated by Azure
# at connection creation time (verified for both MSI and OAuth connectors). Terraform reads
# it from the ARM deployment output and writes it as an app setting. It only changes if the
# connection resource is destroyed and recreated — which Terraform will handle correctly.

# Role assignment (if MSI, scope to the target resource):
resource "azurerm_role_assignment" "<connector>_role" {
  scope                = <target_resource_id>
  role_definition_name = "<Role Name>"
  principal_id         = azurerm_logic_app_standard.this.identity[0].principal_id
}
```

### 3. `workflows/connections.json`

**MSI connection:**

```json
"<referenceName>": {
  "api": {
    "id": "@appsetting('<CONNECTOR>_API_ID')"
  },
  "connection": {
    "id": "@appsetting('<CONNECTOR>_CONNECTION_ID')"
  },
  "connectionRuntimeUrl": "@appsetting('<CONNECTOR>_CONNECTION_RUNTIMEURL')",
  "connectionProperties": {
    "authentication": {
      "audience": "<resourceId from connector definition>",
      "additionalAudiences": ["<backend API audience if different>"],
      "type": "ManagedServiceIdentity"
    }
  },
  "authentication": {
    "type": "ManagedServiceIdentity"
  }
}
```

Omit `additionalAudiences` if the connector only calls the resource identified by `audience`.

**OAuth / user-consent connection:**

```json
"<referenceName>": {
  "api": {
    "id": "@appsetting('<CONNECTOR>_API_ID')"
  },
  "connection": {
    "id": "@appsetting('<CONNECTOR>_CONNECTION_ID')"
  },
  "connectionRuntimeUrl": "@appsetting('<CONNECTOR>_CONNECTION_RUNTIMEURL')",
  "authentication": {
    "type": "ManagedServiceIdentity"
  }
}
```

### 4. `pipelines/templates/deploy-workflows.yml`

Add the new connection to the "Sync Connection Runtime URLs" step:

```bash
<CONNECTOR>_CONN_ID=$(az functionapp config appsettings list \
  --name "$APP" --resource-group "$RG" \
  --query "[?name=='<CONNECTOR>_CONNECTION_ID'].value" -o tsv)

<CONNECTOR>_URL=$(get_runtime_url "$<CONNECTOR>_CONN_ID")

if [ -n "$<CONNECTOR>_URL" ]; then
  SETTINGS="$SETTINGS <CONNECTOR>_CONNECTION_RUNTIMEURL=$<CONNECTOR>_URL"
  echo "✓ <Connector> runtime URL retrieved"
else
  echo "⚠ <Connector> runtime URL unavailable"
fi
```

---

## `additionalAudiences` reference

`additionalAudiences` is not declared in the connector definition. It is the internal backend API the connector calls after authenticating. Without it, the connection falls back to OAuth consent and fails.

| Connector | `audience` | `additionalAudiences` |
|---|---|---|
| `azuremonitorlogs` | `https://management.core.windows.net/` | `["https://api.loganalytics.io"]` |
| `arm` | `https://management.core.windows.net/` | — |
| `keyvault` | `https://vault.azure.net` | — |
| `servicebus` | `https://management.core.windows.net/` | `["https://servicebus.azure.net"]` |
| `office365` | n/a — OAuth user consent | n/a |

If unsure, deploy without `additionalAudiences` first. The error message on a failed run will state `resource=<missing audience>`, which is exactly the value to add.

---

## RBAC roles reference

The `resourceId` from the connector definition identifies the Azure service being called, which determines the required role:

| `resourceId` | Typical role |
|---|---|
| `https://management.core.windows.net/` | Depends on the connector (e.g. Log Analytics Reader for `azuremonitorlogs`) |
| `https://vault.azure.net` | Key Vault Secrets User |
| `https://servicebus.azure.net` | Azure Service Bus Data Receiver or Sender |
| `https://graph.microsoft.com` | Graph API app role grants — not standard RBAC |

---

## Manual steps required after deployment

| Connection type | Manual step |
|---|---|
| MSI (`oboSupported: true`) | None. Runtime URL is available immediately after connection creation and is synced automatically by the pipeline. |
| OAuth / user-consent | Go to Azure Portal → connection resource → **Edit API connection** → **Authorize** → sign in → **Save**. Then re-run the pipeline (Stage 3) to sync the runtime URL. |
