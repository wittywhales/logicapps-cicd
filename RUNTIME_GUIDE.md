# Logic App Standard & Azure Functions — Runtime Guide

Logic App Standard is built directly on top of the Azure Functions runtime. Understanding
the Functions runtime is the key to understanding why `host.json`, `NETFRAMEWORK_VERSION`,
extension bundles, and app settings work the way they do.

---

## How the Runtime Stack Fits Together

```
┌─────────────────────────────────────────────────────────┐
│                  Azure App Service Host                 │
│         (Windows IIS / Kudu / platform layer)           │
├─────────────────────────────────────────────────────────┤
│              Azure Functions Host (~4)                  │
│    ScriptHost, JobHost, WebJobsBuilder, middleware      │
├─────────────────────────────────────────────────────────┤
│         Extension Bundle (Workflows 1.x)                │
│   Logic App-specific connectors, WDL engine, triggers  │
├─────────────────────────────────────────────────────────┤
│          Your Workflow Code (wwwroot/)                   │
│   host.json, connections.json, parameters.json,        │
│   HealthCheck/workflow.json, IngestionSpike/workflow.json│
└─────────────────────────────────────────────────────────┘
```

Each layer has its own version, configuration file, and failure mode.

---

## Layer 1 — The App Service Host

This is the Azure platform layer. It provisions the process sandbox, mounts the
Azure Files content share to `/home/site/wwwroot`, and manages the lifecycle of
the Functions host process.

**Controlled by:**
- App Service Plan SKU (`WS1` for Logic App Standard)
- App setting `NETFRAMEWORK_VERSION`
- App setting `WEBSITE_NODE_DEFAULT_VERSION` (irrelevant for Logic Apps)

**`NETFRAMEWORK_VERSION`**

This setting tells the App Service platform which .NET runtime assemblies to
load into the process. It does not control the C# language version or SDK —
it controls the CLR that the Functions host boots under.

| Value  | .NET version | Use case                          |
|--------|-------------|-----------------------------------|
| `v6.0` | .NET 6      | Default when not set (Functions ~4)|
| `v8.0` | .NET 8      | Required for extension bundle ≥ 1.75 |

Logic App Standard extension bundles newer than ~1.74 were compiled against
.NET 8 APIs. Running them under `v6.0` causes:

```
System.TypeLoadException: Could not load type
'System.Runtime.InteropServices.OSPlatform'
from assembly 'System.Runtime, Version=6.0.0.0'
```

This is what happened in this repo. Fix: `NETFRAMEWORK_VERSION = v8.0`.

---

## Layer 2 — The Azure Functions Host

The Functions host is a .NET process (`func.exe` on Windows) that:

- Reads `host.json` for configuration
- Bootstraps the DI container and middleware pipeline
- Loads extension bundles
- Routes HTTP triggers and manages timer/recurrence triggers
- Exposes the `/runtime/webhooks/workflow/api/management/` management API
- Writes logs to Application Insights

**Version controlled by:**
- Terraform resource field `version = "~4"` on `azurerm_logic_app_standard`
- App setting `FUNCTIONS_EXTENSION_VERSION` (set automatically from the above)

**`FUNCTIONS_EXTENSION_VERSION`**

This is a major version pin. `~4` means "latest patch of Functions 4.x".
You should not set this manually in `app_settings` if the Terraform resource
already has the `version` field — setting it in both places causes drift.

**`FUNCTIONS_WORKER_RUNTIME`**

Tells the host which language worker to start. For Logic App Standard this
must be `dotnet`. Do not set it to `node`, `python`, or `java`.

| Value     | Worker process started |
|-----------|------------------------|
| `dotnet`  | In-process .NET worker |
| `node`    | Node.js worker         |
| `python`  | Python worker          |
| `java`    | Java worker            |

Logic App Standard requires `dotnet` because the workflow engine is a .NET
class library loaded in-process.

---

## Layer 3 — Extension Bundles

Extension bundles are NuGet package collections that the Functions host
downloads and loads at startup. For Logic App Standard the bundle is:

```
Microsoft.Azure.Functions.ExtensionBundle.Workflows
```

This bundle contains:
- The WDL (Workflow Definition Language) engine
- All built-in connectors (HTTP, Schedule, etc.)
- The managed API connection runtime (calls to `azuremonitorlogs`, `office365`, etc.)
- The workflow designer backend
- The management API endpoints

**Configured in `host.json`:**

```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle.Workflows",
    "version": "[1.*, 2.0.0)"
  }
}
```

The `version` field is a NuGet version range:

| Range          | Meaning                                           |
|----------------|---------------------------------------------------|
| `[1.*, 2.0.0)` | Any 1.x version, exclusive of 2.0                |
| `[1.74.0, 1.75.0)` | Pinned to exactly 1.74.x                     |
| `[2.*, 3.0.0)` | Any 2.x (not available yet for Logic Apps)       |

The host downloads the bundle to the agent's tool cache and loads it on startup.
If the bundle version requires a newer .NET than `NETFRAMEWORK_VERSION` provides,
you get a `TypeLoadException` at host startup.

**Bundle version to .NET version compatibility:**

| Bundle range   | .NET requirement |
|----------------|-----------------|
| 1.0 – 1.74     | .NET 6+          |
| 1.75 – current | .NET 8+          |

**Where the bundle is cached:**

On the VMSS agent: `/home/AzDevOps/.nuget/packages/` or the agent's tool cache.
On App Service: Platform-managed, re-downloaded on each cold start if not cached.

---

## Layer 4 — Your Workflow Code (wwwroot/)

This is the layer you control. The Functions host reads it from Azure Files.

### File structure

```
wwwroot/
├── host.json              ← Functions host config (your layer)
├── connections.json       ← connector bindings for all workflows
├── parameters.json        ← workflow parameter defaults (via @appsetting)
├── .funcignore            ← files excluded from zip deploy
├── HealthCheck/
│   └── workflow.json      ← stateless HTTP trigger workflow
└── IngestionSpike/
    └── workflow.json      ← stateful recurrence trigger workflow
```

### `host.json`

This is the primary configuration file for the Functions host layer.
Every setting in it applies to the entire Logic App instance (all workflows).

```json
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle.Workflows",
    "version": "[1.*, 2.0.0)"
  }
}
```

The `version: "2.0"` is the host.json schema version — always `2.0` for
Functions v2+. It has nothing to do with the Functions runtime version or
the extension bundle version.

Additional settings you can add to `host.json`:

```json
{
  "version": "2.0",
  "extensionBundle": { ... },
  "logging": {
    "logLevel": {
      "default": "Warning",
      "Host.Results": "Error",
      "Function": "Warning"
    },
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "maxTelemetryItemsPerSecond": 5
      }
    }
  },
  "functionTimeout": "00:10:00"
}
```

`functionTimeout` only applies to stateless workflows. Stateful workflows
are durable and not subject to this timeout.

### `connections.json`

Maps the connector reference names used inside `workflow.json` to actual
Azure resources. Every value must use `@appsetting()` — hardcoding
resource IDs or URLs here makes the workflow environment-specific.

```json
{
  "managedApiConnections": {
    "azuremonitorlogs": {
      "api":   { "id": "@appsetting('AZUREMONITORLOGS_API_ID')" },
      "connection": { "id": "@appsetting('AZUREMONITORLOGS_CONNECTION_ID')" },
      "connectionRuntimeUrl": "@appsetting('AZUREMONITORLOGS_CONNECTION_RUNTIMEURL')",
      "connectionProperties": {
        "authentication": {
          "type": "ManagedServiceIdentity",
          "audience": "https://management.azure.com/"
        }
      },
      "authentication": { "type": "ManagedServiceIdentity" }
    }
  }
}
```

There are two `authentication` blocks for managed identity connectors:

- **Outer `authentication`**: Used by the Logic App runtime to authenticate
  to the connection gateway (`*.azure-apihub.net`) when proxying the call.
- **`connectionProperties.authentication`**: Passed through to the target
  service (in this case, tells Azure Monitor Logs to use the managed identity
  of the calling Logic App).

### `parameters.json`

Defines workflow-level parameters that are shared across all workflows in the
Logic App. Each parameter's value is typically an `@appsetting()` reference
so the actual value comes from app settings managed by Terraform.

```json
{
  "la_workspaceName": {
    "type": "String",
    "value": "@appsetting('LA_TARGET_WORKSPACE_NAME')"
  }
}
```

Individual `workflow.json` files declare which parameters they use in
`definition.parameters`, and the runtime resolves them via `parameters.json`.

### `workflow.json`

The WDL definition for a single workflow. Key fields:

```json
{
  "definition": {
    "$schema": "...",
    "contentVersion": "1.0.0.0",
    "triggers": { ... },
    "actions": { ... },
    "parameters": {
      "la_workspaceName": { "type": "string", "defaultValue": "" }
    }
  },
  "kind": "Stateful"
}
```

**`kind` field:**

| Value       | Description                                                         |
|-------------|---------------------------------------------------------------------|
| `Stateful`  | Workflow state is persisted to storage. Supports long-running flows, retry, history. |
| `Stateless` | State is in-memory only. Fast, no history, no retry across restarts. Suited for synchronous HTTP flows. |

Stateful workflows store their run history in Azure Blob Storage under the
storage account attached to the Logic App. This is why `storage_account_name`
and `storage_account_access_key` are required on the Terraform resource.

---

## App Settings Reference

All app settings live on the Logic App resource and are set by Terraform.

| Setting | Layer | Purpose |
|---------|-------|---------|
| `FUNCTIONS_EXTENSION_VERSION` | Functions Host | Major version pin (`~4`) |
| `FUNCTIONS_WORKER_RUNTIME` | Functions Host | Language worker (`dotnet`) |
| `NETFRAMEWORK_VERSION` | App Service Host | .NET CLR version (`v8.0`) |
| `APPINSIGHTS_INSTRUMENTATIONKEY` | Functions Host | App Insights telemetry |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Functions Host | Preferred over ikey |
| `APP_KIND` | App Service Host | Must be `workflowApp` (set by platform) |
| `AzureWebJobsStorage` | Functions Host | Storage for triggers/leases (set by platform from `storage_account_name`) |
| `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING` | App Service Host | Azure Files connection (set by platform) |
| `WEBSITE_CONTENTSHARE` | App Service Host | Azure Files share name (set by platform) |
| `AZUREMONITORLOGS_API_ID` | Workflow | Managed API resource ID |
| `AZUREMONITORLOGS_CONNECTION_ID` | Workflow | Connection resource ID |
| `AZUREMONITORLOGS_CONNECTION_RUNTIMEURL` | Workflow | Gateway proxy URL |
| `OFFICE365_CONNECTION_RUNTIMEURL` | Workflow | Gateway proxy URL (set by Terraform; authorize in portal to enable sending) |
| `LA_TARGET_SUBSCRIPTION_ID` | Workflow | KQL target workspace sub |
| `LA_TARGET_RESOURCE_GROUP` | Workflow | KQL target workspace RG |
| `LA_TARGET_WORKSPACE_NAME` | Workflow | KQL target workspace name |

Settings marked "set by platform" are managed by Azure automatically based
on the storage account attached to the Logic App. You do not set them yourself.

---

## Connection Runtime URLs

The `connectionRuntimeUrl` is unique to V2 Standard connections. It is a
dedicated HTTPS proxy endpoint that the Logic App's workflow engine calls when
executing a connector action.

**Format:**
```
https://<gateway-id>.common.logic-<region>.azure-apihub.net/apim/<connector>/<connection-id>/
```

**How it works:**

```
workflow engine
    → connectionRuntimeUrl (the apihub gateway)
        → authenticates using the Logic App's managed identity
            (via outer authentication: ManagedServiceIdentity)
        → proxies to the target service (Log Analytics, Exchange Online, etc.)
            using the connection's own auth (MI or OAuth token)
```

**Why it must be in app settings:**

`connections.json` references it as `@appsetting('..._CONNECTION_RUNTIMEURL')`.
The value is only available after the connection resource exists in Azure, so
Terraform sets it to `""` on first deploy and either:

- Fills it from the ARM `reference()` output (for Managed Identity connections)
- Has it set by the pipeline after manual OAuth consent (for OAuth connections)

The `lifecycle { ignore_changes }` block in `main.tf` prevents Terraform from
blanking it out on subsequent applies.

---

## Cold Start and Runtime Restart Sequence

When the Logic App host process starts (after deploy, restart, or scale-out):

```
1. App Service platform mounts Azure Files to /home/site/wwwroot
2. Functions host process starts
3. host.json is read
4. Extension bundle is downloaded (if not cached) and loaded
5. connections.json is read — connector bindings are registered
6. Each workflow.json is read — triggers are registered
7. Recurrence triggers are evaluated — missed runs may fire immediately
8. HTTP trigger URLs become available
9. Management API becomes available
   → az rest .../workflows returns Healthy/Unhealthy per workflow
```

If step 4 fails (e.g., TypeLoadException), the host stays in Error state.
All workflows appear Unhealthy. The management API returns 503.

---

## Stateful Workflow Storage

Stateful workflow runs write to Azure Blob Storage in this structure:

```
<storage-account>/
└── azure-webjobs-hosts/
    └── leases/
└── flow<logic-app-id>/
    ├── runs/
    │   └── <run-id>/
    │       ├── actions/
    │       └── triggers/
    └── history/
```

Each action's input, output, and status is stored as a separate blob.
This enables:
- Run history in the portal
- Retry from failed action
- Long-running workflows that survive host restarts
- Concurrent runs with isolation

The storage account name and access key on the Terraform resource
(`storage_account_name`, `storage_account_access_key`) are what connects
the Logic App to this storage.

---

## Diagnostic Commands

**Check host runtime state:**
```powershell
az rest --method get `
  --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<name>/host/default/properties/status?api-version=2022-03-01" `
  --query "properties.{state:state,version:version,bundle:extensionBundle}"
```

**Check workflow health:**
```powershell
az rest --method get `
  --url "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Web/sites/<name>/hostruntime/runtime/webhooks/workflow/api/management/workflows?api-version=2022-03-01"
```

**Check connection status:**
```powershell
az rest --method get `
  --url "https://management.azure.com<connection-resource-id>?api-version=2018-07-01-preview" `
  --query "{status:properties.overallStatus,runtimeUrl:properties.connectionRuntimeUrl}"
```

**Restart the host:**
```powershell
az webapp restart --name <logic-app-name> --resource-group <rg>
```

**Stream live logs:**
```powershell
az webapp log tail --name <logic-app-name> --resource-group <rg>
```
