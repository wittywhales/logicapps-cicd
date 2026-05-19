# Presentation Speech Notes — Azure Logic Apps Standard CI/CD with Terraform

---

## 1. What We're Building and Why

We need to manage Azure Logic Apps Standard fully through Terraform and deploy workflows via a proper CI/CD pipeline — rather than building everything by hand in the Azure portal and hoping it stays consistent across environments.

Logic App Standard runs like a proper App Service — it has its own hosting plan, storage account, app settings, and the workflows are just JSON files deployed as a zip package.

---

## 2. What Are API Connections?

Before we get into the code, let me explain what a connection actually is.

A **connection** is a link between a Logic App action and a backend service — like Azure Monitor Logs or Office 365 Outlook. It sits in the middle as a Microsoft-managed HTTP proxy, sometimes called the API Hub. So when a workflow runs a "Run Query" action against Log Analytics, it's not calling the Log Analytics API directly. It calls the connection, and the connection calls the backend on its behalf.

The connection handles two things:
- Translating the generic workflow action schema into the actual API calls the backend expects
- Handling authentication — so the Logic App authenticates to the connection, and the connection separately authenticates to the backend

This proxy lives at a unique URL called the **connection runtime URL**, and that URL is assigned by Azure when the connection resource is first created.

---

## 3. The Problem: Terraform Has No Native Resource for Connections

When you create a connection from the Azure portal, it gets created automatically in the background — you don't even notice it happening. But when you're managing everything through Terraform, you have to create that connection yourself as an explicit resource.

The problem is: **the AzureRM Terraform provider has no native resource for `Microsoft.Web/connections`**.

So what we do is use an ARM template deployment inside Terraform — specifically `azurerm_resource_group_template_deployment`. We embed the ARM template JSON directly in the Terraform code, and Terraform submits it to Azure Resource Manager. This gives us the full ARM capability without needing a separate deployment pipeline.

We do this in two passes:
1. First ARM deployment creates the connection resources themselves
2. Second ARM deployment attaches **access policies** to each connection — this is what actually grants the Logic App's managed identity permission to use them at runtime

---

## 4. The connections.json Problem — Hardcoded vs Parameterized

Here's another gotcha. When you design a workflow in the portal, Logic App Standard generates a `connections.json` file that wires up all the connections the workflow uses. If you just export that file directly, it will have **hardcoded values** in it — things like the connection ID, the API ID, and the runtime URL baked directly as strings.

That's a problem because those values are different in every environment — DEV and PROD will have completely different connection resource IDs and runtime URLs.

The solution is to **parameterize** `connections.json` using app settings. Instead of hardcoded values, each field references an app setting using the `@appsetting('...')` syntax that Logic Apps supports natively. So the runtime URL becomes `@appsetting('AZUREMONITORLOGS_CONNECTION_RUNTIMEURL')`, and that app setting is populated by Terraform at deploy time using the ARM output from the connection deployment.

The same approach applies to `parameters.json` — workflow-level parameters like the Log Analytics workspace name, subscription ID, and email recipients all read from app settings, so the same workflow JSON works across every environment without modification.

---

## 5. How the Runtime URL Flows Through the System

The connection runtime URL is the key piece of runtime config. Here's how it travels:

1. Terraform runs the ARM template → connection resource is created in Azure
2. ARM assigns a unique runtime URL to that connection and puts it in the deployment output
3. Terraform reads that output using `jsondecode(... output_content)` and writes it as an app setting on the Logic App
4. `connections.json` references that app setting
5. At runtime, the Logic App reads the app setting → resolves the runtime URL → calls the connection

This means no manual steps are needed after deploy for connections that use Managed Identity auth.

---

## 6. Authentication — Managed Identity vs OAuth

We have two connectors in this project, and they use different authentication:

**Azure Monitor Logs** uses **Managed Identity**. The Logic App has a system-assigned identity, and we give that identity the "Log Analytics Reader" role on the target workspace. At runtime, the Logic App acquires an MSI token and hands it to the connection. No human needs to be involved at any point. Fully automated.

**Office 365 Outlook** is different. Even though the connector technically supports on-behalf-of flows, sending email requires a **delegated user context** — a real mailbox. So this one requires **manual OAuth authorization in the portal after the first Terraform deployment**. You go to the connection resource, click "Edit API connection", authorize with the account that should send the emails, and save. That stores a refresh token in the connection resource. After that, it works automatically on every workflow run.

This is a one-time step per environment — you do it once in DEV, and once in PROD. It doesn't block the deployment itself; it just means the email action will fail until that authorization is done.

---

## 7. Folder Structure

Let's walk through how the repo is organized:

```
logicapps/
├── infrastructure/          ← All Terraform code lives here
│   ├── main.tf              ← Logic App, storage, app service plan, observability, zip deploy
│   ├── connections.tf       ← ARM templates for connection resources and access policies
│   ├── variables.tf
│   ├── outputs.tf
│   └── environments/
│       ├── dev.tfvars       ← DEV-specific values (names, workspace, recipients)
│       └── prod.tfvars      ← PROD-specific values
│
├── workflows/               ← Logic App workflow code — this gets zipped and deployed
│   ├── connections.json     ← Wires up connections using @appsetting() references
│   ├── parameters.json      ← Workflow parameters, also using @appsetting() references
│   ├── host.json            ← Runtime configuration for the Logic App host
│   ├── IngestionSpike/
│   │   └── workflow.json    ← The actual workflow definition (trigger + actions)
│   └── HealthCheck/
│       └── workflow.json    ← Another workflow
│
└── pipelines/               ← Azure DevOps pipeline definitions
    ├── azure-pipelines.yml  ← Main pipeline: Plan → Apply (includes zip deploy)
    └── templates/           ← Reusable pipeline step templates
```

The `workflows/` directory is the Logic App's "app code". Terraform zips it up using `archive_file`, computes a SHA256 hash of the zip, and only runs the zip deploy step when the hash changes. So if you only change infrastructure config — nothing in `workflows/` — the zip deploy is skipped entirely.

---

## 8. Workflow Development Lifecycle

Here's the day-to-day flow for building and shipping a workflow:

**Step 1 — Design in Sandbox.**
You never design workflows directly in DEV or PROD. There's a dedicated Sandbox environment where you use the portal's visual designer to build and test the workflow. The portal gives you drag-and-drop, test runs, real output — it's the right tool for this phase.

**Step 2 — Export and commit.**
Once the workflow is working, you export the `workflow.json` from the portal and drop it into the `workflows/` folder in the repo. At this point you also need to make sure:
- If you added a new connector, add it to `connections.tf` and `connections.json`
- Update `parameters.json` if there are new config values
- Update the relevant `.tfvars` with any new variable values

Then you raise a PR and merge to main.

**Step 3 — Pipeline deploys to DEV automatically.**
Merging to main triggers the Azure DevOps pipeline. It runs `terraform plan`, waits for review, then `terraform apply`. The apply handles everything: infrastructure, connections, access policies, and the zip deploy of the workflows. After the first apply, if the Office 365 connector is new, you do the OAuth authorization step in the portal.

**Step 4 — Manual trigger to PROD.**
PROD is never deployed automatically. Once DEV is validated, you manually trigger the pipeline with the PROD environment, approve the gate, and Terraform applies with the prod `.tfvars`. Same zip, same connections — just different resource names and config values.

---

## 9. Key Things to Remember

- Terraform has no native connection resource → we use ARM templates embedded in Terraform
- `connections.json` must use `@appsetting()` references, not hardcoded IDs — otherwise it breaks in every environment except the one it was exported from
- The runtime URL flows from ARM output → Terraform app setting → `connections.json` at runtime
- Azure Monitor Logs = fully automated via Managed Identity
- Office 365 = one manual OAuth authorization in the portal per environment, after first deploy
- Workflow zip deploy is part of `terraform apply` — no separate pipeline stage needed

---

*End of speech notes.*
