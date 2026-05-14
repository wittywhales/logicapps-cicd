# Self-Hosted Agent — Utility Installation

ADO pool: `selfhosted`
VMSS: `ado-selfhosted` in resource group `ado-vmss-selfhosted`
OS: Ubuntu 24.04 (Noble)
Subscription: `fc33352a-e8eb-40e6-8e61-416a39f31865`

---

## Why these utilities are needed

| Utility | Required by | Reason |
|---|---|---|
| `unzip` | `TerraformInstaller@1` task | Extracts the downloaded Terraform binary zip |
| `zip` | `deploy-workflows.yml` Package step | Creates the workflow zip for Logic App zip deploy |
| `azure-cli` | All `AzureCLI@2` tasks | Runs `terraform init`, `terraform apply`, ARM queries |

Ubuntu 24.04 minimal images used by Azure VMSS do not include these by default.

---

## Installing on an existing VMSS instance

Use `az vmss run-command invoke` to run commands on a live instance without SSH.

```bash
# Set variables
SUBSCRIPTION="fc33352a-e8eb-40e6-8e61-416a39f31865"
RG="ado-vmss-selfhosted"
VMSS="ado-selfhosted"
INSTANCE_ID="1"   # use 'az vmss list-instances' to find instance IDs

az account set --subscription "$SUBSCRIPTION"

# Install unzip and zip
az vmss run-command invoke \
  --resource-group "$RG" \
  --name "$VMSS" \
  --instance-id "$INSTANCE_ID" \
  --command-id RunShellScript \
  --scripts "sudo apt-get update -y && sudo apt-get install -y unzip zip"

# Install Azure CLI
az vmss run-command invoke \
  --resource-group "$RG" \
  --name "$VMSS" \
  --instance-id "$INSTANCE_ID" \
  --command-id RunShellScript \
  --scripts "curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
```

To target all current instances at once:

```bash
# Get all instance IDs
INSTANCE_IDS=$(az vmss list-instances \
  --resource-group "$RG" --name "$VMSS" \
  --query "[].instanceId" -o tsv)

for ID in $INSTANCE_IDS; do
  echo "--- Instance $ID ---"
  az vmss run-command invoke \
    --resource-group "$RG" --name "$VMSS" \
    --instance-id "$ID" \
    --command-id RunShellScript \
    --scripts "sudo apt-get update -y && sudo apt-get install -y unzip zip && curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
done
```

> **Note:** `run-command invoke` is synchronous — wait for each command to return before moving to the next instance.

---

## Making it permanent — Custom Script Extension

Installing manually only fixes existing instances. New instances created by scale-out will be missing the tools. Fix this by attaching a custom script extension to the VMSS.

### Option A — via Azure CLI (quickest)

```bash
az vmss extension set \
  --resource-group "$RG" \
  --vmss-name "$VMSS" \
  --name CustomScript \
  --publisher Microsoft.Azure.Extensions \
  --version 2.1 \
  --settings '{
    "commandToExecute": "sudo apt-get update -y && sudo apt-get install -y unzip zip && curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
  }'

# Apply to existing instances
az vmss update-instances \
  --resource-group "$RG" \
  --name "$VMSS" \
  --instance-ids "*"
```

### Option B — via cloud-init (if VMSS is managed by Terraform)

Add a `custom_data` block to the VMSS Terraform resource:

```hcl
custom_data = base64encode(<<-CLOUD_INIT
  #cloud-config
  package_update: true
  packages:
    - unzip
    - zip
  runcmd:
    - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  CLOUD_INIT
)
```

> `cloud-init` runs once on first boot of each new instance — no need to re-run on scale-out.

---

## Verify installation on an instance

```bash
az vmss run-command invoke \
  --resource-group "$RG" \
  --name "$VMSS" \
  --instance-id "$INSTANCE_ID" \
  --command-id RunShellScript \
  --scripts "which az && az --version | head -1; which unzip && unzip --version 2>&1 | head -1; which zip && zip --version 2>&1 | head -1"
```

Expected output:
```
/usr/bin/az
azure-cli 2.x.x
/usr/bin/unzip
UnZip 6.00 ...
/usr/bin/zip
Zip 3.0 ...
```

---

## ADO agent registration

The Azure DevOps agent itself is registered and managed by the VMSS agent pool — you do not need to manually install or register the agent binary. Azure DevOps handles provisioning agents on VMSS instances automatically when the pool is configured.

The utilities above are the only additions needed beyond the standard ADO agent image.
