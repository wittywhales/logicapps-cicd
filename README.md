# Logic App Standard — CI/CD with Terraform & Azure DevOps

End-to-end CI/CD for an **Azure Logic App Standard** workload.  
Terraform provisions infrastructure, Azure DevOps Pipelines deploy workflows.

---

## Directory Structure

```
logicapps/
├── infrastructure/               # Terraform — Azure resources
│   ├── main.tf                   # Provider, all Azure resources
│   ├── connections.tf            # API connections + access policies (ARM)
│   ├── variables.tf              # Input variables
│   ├── outputs.tf                # Outputs consumed by the pipeline
│   └── environments/
│       ├── dev.tfvars            # Dev environment values
│       └── prod.tfvars           # Prod environment values
│
├── workflows/                    # Logic App workflow code (deployed via zip)
│   ├── host.json                 # Functions runtime extension bundle config
│   ├── connections.json          # Connector bindings → @appsetting() references
│   ├── parameters.json           # Workflow parameters → @appsetting() references
│   ├── .funcignore               # Files excluded from zip deploy
│   ├── IngestionSpike/
│   │   └── workflow.json         # Main workflow: Log Analytics spike detection
│   └── HealthCheck/
│       └── workflow.json         # Smoke-test workflow (HTTP → 200)
│
└── pipelines/                    # Azure DevOps YAML pipelines
    ├── azure-pipelines.yml       # Full pipeline: Infra + Workflows (3 stages)
    ├── infra-only-pipeline.yml   # Infrastructure-only pipeline (2 stages)
    └── templates/
        ├── terraform-steps.yml   # Reusable: TF init → plan → publish artifact
        └── deploy-workflows.yml  # Reusable: sync runtime URLs + zip deploy
```

---

## How the Files Link Together

### 1. Infrastructure Layer (Terraform)

The dependency chain is designed to avoid a **circular reference** between the
Logic App and its API connections:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        variables.tf                                 │
│  Defines all inputs (environment, names, target workspace info)     │
│  Consumed by ──► main.tf and connections.tf                         │
└─────────────────────────────────────────────────────────────────────┘
                                │
            ┌───────────────────┼───────────────────┐
            ▼                                       ▼
┌───────────────────────┐              ┌────────────────────────────┐
│     connections.tf    │              │         main.tf            │
│                       │              │                            │
│  Step 1: ARM deploy   │              │  RG, Storage, ASP (WS1),  │
│  creates connections  │──outputs──►  │  Log Analytics, App Insights│
│  (no Logic App dep)   │  conn IDs    │  Logic App Standard        │
│                       │              │                            │
│  Step 2: ARM deploy   │◄──identity── │  app_settings = {          │
│  creates access       │  principal   │    ...CONNECTION_ID =      │
│  policies (needs      │     ID       │      conn output values    │
│  Logic App identity)  │              │  }                         │
└───────────────────────┘              └────────────────────────────┘
                                                    │
                                                    ▼
                                       ┌────────────────────────────┐
                                       │        outputs.tf          │
                                       │  logic_app_name,           │
                                       │  resource_group_name,      │
                                       │  connection IDs/names,     │
                                       │  principal_id              │
                                       │                            │
                                       │  Consumed by ──► pipeline  │
                                       │  Stage 2 (Apply) exports   │
                                       │  these as ADO variables    │
                                       └────────────────────────────┘
```

**Step-by-step Terraform execution order:**

1. `connections.tf` — ARM template creates plain `Microsoft.Web/connections` for
   `azuremonitorlogs` and `office365`. This has **no dependency** on the Logic App.
2. `main.tf` — Creates the Logic App Standard with a `SystemAssigned` identity.
   Its `app_settings` reference `local.connection_outputs` (the connection IDs
   output from Step 1). This creates an implicit dependency.
3. `connections.tf` — A second ARM template creates **access policies** on each
   connection, granting the Logic App's managed identity permission to use them.
   This depends on both the connection names (Step 1) and the Logic App's
   `principal_id` (Step 2).
4. `main.tf` — Assigns `Log Analytics Reader` to the Logic App identity on the
   target Log Analytics workspace so the `azuremonitorlogs` connector can use
   Managed Identity at runtime.

### 2. Workflow Layer

```
┌─────────────────────────────────────────────────────────────────────┐
│                     connections.json                                 │
│                                                                     │
│  Maps connector reference names used in workflow.json               │
│  (e.g. "azuremonitorlogs", "office365") to Azure resources.         │
│                                                                     │
│  Every value is an @appsetting() reference:                         │
│    api.id              → @appsetting('AZUREMONITORLOGS_API_ID')     │
│    connection.id       → @appsetting('AZUREMONITORLOGS_CONN_ID')    │
│    connectionRuntimeUrl→ @appsetting('AZUREMONITORLOGS_CONN_..URL') │
│                                                                     │
│  Auth: outer `authentication` uses ManagedServiceIdentity for both  │
│  connections in Azure; `connectionProperties.authentication` is     │
│  added only where the target connector supports Managed Identity.   │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ referenced by
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│               IngestionSpike/workflow.json                           │
│                                                                     │
│  Uses connector actions like:                                       │
│    "Run query and list results (V2)" → connection: azuremonitorlogs │
│    "Send an email (V2)"             → connection: office365         │
│                                                                     │
│  Uses @parameters() for environment-specific values:                │
│    @parameters('la_subscriptionId')                                 │
│    @parameters('la_resourceGroup')                                  │
│    @parameters('la_workspaceName')                                  │
│    @parameters('alertEmailRecipients')                              │
│    @parameters('logAnalyticsBaseUrl')                                │
└─────────────────────┬───────────────────────────────────────────────┘
                      │ parameters resolved via
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      parameters.json                                │
│                                                                     │
│  Maps each workflow parameter to an @appsetting():                  │
│    la_subscriptionId    → @appsetting('LA_TARGET_SUBSCRIPTION_ID')  │
│    la_resourceGroup     → @appsetting('LA_TARGET_RESOURCE_GROUP')   │
│    la_workspaceName     → @appsetting('LA_TARGET_WORKSPACE_NAME')   │
│    alertEmailRecipients → @appsetting('ALERT_EMAIL_RECIPIENTS')     │
│    logAnalyticsBaseUrl  → @appsetting('LOG_ANALYTICS_PORTAL_URL')   │
└─────────────────────────────────────────────────────────────────────┘
```

**The linking key is `@appsetting()`.**  Both `connections.json` and
`parameters.json` resolve their values from the Logic App's **Application
Settings**, which are set by Terraform in `main.tf → app_settings {}`.

### 3. How App Settings Bridge Terraform ↔ Workflows

```
         TERRAFORM (main.tf)                         WORKFLOWS
         ───────────────────                         ─────────
  app_settings = {
    AZUREMONITORLOGS_API_ID        = "..."  ──►  connections.json → @appsetting('AZUREMONITORLOGS_API_ID')
    AZUREMONITORLOGS_CONNECTION_ID = "..."  ──►  connections.json → @appsetting('AZUREMONITORLOGS_CONNECTION_ID')
    OFFICE365_API_ID               = "..."  ──►  connections.json → @appsetting('OFFICE365_API_ID')
    OFFICE365_CONNECTION_ID        = "..."  ──►  connections.json → @appsetting('OFFICE365_CONNECTION_ID')
    LA_TARGET_SUBSCRIPTION_ID      = "..."  ──►  parameters.json  → @appsetting('LA_TARGET_SUBSCRIPTION_ID')
    LA_TARGET_RESOURCE_GROUP       = "..."  ──►  parameters.json  → @appsetting('LA_TARGET_RESOURCE_GROUP')
    LA_TARGET_WORKSPACE_NAME       = "..."  ──►  parameters.json  → @appsetting('LA_TARGET_WORKSPACE_NAME')
    ALERT_EMAIL_RECIPIENTS         = "..."  ──►  parameters.json  → @appsetting('ALERT_EMAIL_RECIPIENTS')
    LOG_ANALYTICS_PORTAL_URL       = "..."  ──►  parameters.json  → @appsetting('LOG_ANALYTICS_PORTAL_URL')
  }
```

This means **workflow code never contains hardcoded environment values**.
Changing environments only requires a different `.tfvars` file.

### 4. Pipeline Flow

```
azure-pipelines.yml
│
├── Stage 1: Plan
│   └── templates/terraform-steps.yml
│       ├── checkout self + common-templates
│       ├── install_terraform.yml@common-templates
│       ├── init_terraform.yml@common-templates
│       ├── terraform plan -var-file=environments/<env>.tfvars -out=tfplan
│       └── PublishPipelineArtifact (tfplan)
│
├── Stage 2: Apply (environment approval gate)
│   ├── DownloadPipelineArtifact (tfplan)
│   ├── terraform apply -auto-approve tfplan
│   └── Export TF outputs as pipeline variables:
│       ├── LOGIC_APP_NAME
│       └── RESOURCE_GROUP_NAME
│
└── Stage 3: Deploy Workflows
    └── templates/deploy-workflows.yml
        │
        ├── Step 1: Sync Connection Runtime URLs
        │   ├── Read CONNECTION_ID values from Logic App app settings
        │   ├── Call az rest to get connectionRuntimeUrl from each connection
        │   └── az functionapp config appsettings set → updates *_CONNECTION_RUNTIMEURL
        │
        ├── Step 2: Zip the workflows/ directory
        │
        └── Step 3: AzureFunctionApp@1 zip deploy to Logic App Standard
```

**Stage variable passing:** Stage 2 reads `terraform output -raw logic_app_name`
and publishes it as `##vso[task.setvariable ...]`. Stage 3 consumes it via
`$[ stageDependencies.Apply.ApplyTerraform.outputs[...] ]`.

---

## Connection Runtime URL Lifecycle

```
 1. terraform apply
    └── Creates API connections (ARM)
    └── Creates Logic App with CONNECTION_RUNTIMEURL = "" (empty)
    └── lifecycle.ignore_changes prevents Terraform from overwriting later

 2. Manual: Azure Portal → Resource Group → Office 365 connection → "Authorize"
    └── One-time OAuth consent per environment for Office 365
    └── Azure Monitor Logs uses runtime Managed Identity plus RBAC on the target workspace

 3. Pipeline Stage 3 (deploy-workflows.yml)
    └── az rest --uri <connection-id>?api-version=2018-07-01-preview
    └── Reads properties.connectionRuntimeUrl
    └── az functionapp config appsettings set → persists the URL
    └── Workflows can now call the managed API connectors
```

---

## Environment Configuration

Environment-specific values live in `infrastructure/environments/*.tfvars`:

| Variable | Description | Example (dev) |
|---|---|---|
| `environment` | Environment name | `dev` |
| `resource_group_name` | Resource group | `rg-logicapp-dev` |
| `logic_app_name` | Logic App name | `la-ingestionspike-dev` |
| `storage_account_name` | Storage account | `stlaingestiondev` |
| `la_target_subscription_id` | Monitored LA workspace subscription | `<sub-id>` |
| `la_target_resource_group` | Monitored LA workspace RG | `rg-log-mgmt-dev` |
| `la_target_workspace_name` | Monitored LA workspace name | `la-workspace-dev` |
| `alert_email_recipients` | Email for spike alerts | `team@example.com` |
| `log_analytics_portal_url` | Portal deep-link | `https://portal.azure.com/...` |

---

## Quick Reference: File Cross-References

| Workflow file | Key it uses | Resolved from | Set in Terraform |
|---|---|---|---|
| `connections.json` | `AZUREMONITORLOGS_API_ID` | `@appsetting()` | `main.tf → app_settings` |
| `connections.json` | `AZUREMONITORLOGS_CONNECTION_ID` | `@appsetting()` | `main.tf` ← `connections.tf` output |
| `connections.json` | `AZUREMONITORLOGS_CONNECTION_RUNTIMEURL` | `@appsetting()` | `main.tf` ← `connections.tf` output |
| `connections.json` | `OFFICE365_API_ID` | `@appsetting()` | `main.tf → app_settings` |
| `connections.json` | `OFFICE365_CONNECTION_ID` | `@appsetting()` | `main.tf` ← `connections.tf` output |
| `connections.json` | `OFFICE365_CONNECTION_RUNTIMEURL` | `@appsetting()` | `main.tf` ← `connections.tf` output (authorize in portal post-deploy to enable sending) |
| `parameters.json` | `LA_TARGET_SUBSCRIPTION_ID` | `@appsetting()` | `main.tf` ← `variables.tf` ← `.tfvars` |
| `parameters.json` | `LA_TARGET_RESOURCE_GROUP` | `@appsetting()` | `main.tf` ← `variables.tf` ← `.tfvars` |
| `parameters.json` | `LA_TARGET_WORKSPACE_NAME` | `@appsetting()` | `main.tf` ← `variables.tf` ← `.tfvars` |
| `parameters.json` | `ALERT_EMAIL_RECIPIENTS` | `@appsetting()` | `main.tf` ← `variables.tf` ← `.tfvars` |
| `parameters.json` | `LOG_ANALYTICS_PORTAL_URL` | `@appsetting()` | `main.tf` ← `variables.tf` ← `.tfvars` |

---

## Adding a New Workflow

1. Create `workflows/<WorkflowName>/workflow.json` with the workflow definition.
2. If the workflow uses new connectors, add them to `connections.json` and create
   the corresponding `Microsoft.Web/connections` in `connections.tf`.
3. If the workflow needs environment-specific parameters, add entries to
   `parameters.json` and the matching `app_settings` in `main.tf` + `variables.tf`
   + each `.tfvars` file.
4. Commit and push — the pipeline deploys automatically.

## Adding a New Environment

1. Create `infrastructure/environments/<env>.tfvars` with all variable values.
2. Create a new pipeline (or parameterize the existing one) setting
   `environment: '<env>'` and `stateKey: 'logicapp-<env>.tfstate'`.
3. After first `terraform apply`, authorize API connections in Azure Portal.
4. Re-run the pipeline to sync connection runtime URLs.
