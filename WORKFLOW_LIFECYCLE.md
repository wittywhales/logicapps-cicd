# Logic App Workflow Development Lifecycle

```mermaid
flowchart LR
    subgraph SBX["☁️ SBX — Design"]
        s1(["Design workflow\nin Portal GUI"])
        s2(["Test &\niterate"])
        s3(["Export\nworkflow.json"])
        s1 --> s2 --> s3
    end

    subgraph REPO["📁 Git Repo"]
        r1(["Add / update\nworkflows/"])
        r2(["Add connections\nin connections.tf\nif new connector"])
        r3(["Update\nconnections.json\n+ parameters.json"])
        r4(["Update tfvars\nif new config"])
        r5(["PR → merge\nto main"])
        r1 --> r2 --> r3 --> r4 --> r5
    end

    subgraph DEV["☁️ DEV — Validate"]
        d1(["terraform apply\ninfra + connections\n+ zip deploy"])
        d2(["Authorize OAuth\nconnections\nif new connector"])
        d3(["Test &\nValidate"])
        d1 --> d2 --> d3
    end

    subgraph PROD["☁️ PROD — Live"]
        p1(["Manual Approval\nGate"])
        p2(["terraform apply\ninfra + connections\n+ zip deploy"])
        p3(["Authorize OAuth\nconnections\nif new connector"])
        p1 --> p2 --> p3
    end

    SBX -->|"commit JSON\nto repo"| REPO
    REPO -->|"pipeline auto-triggers\non main merge"| DEV
    DEV -->|"manual trigger\nwhen validated"| PROD
```

## Environment Roles

| Environment | Purpose | Deployment |
|---|---|---|
| **SBX** | GUI designer — build and iterate workflows using the portal; no pipeline | Manual (portal only) |
| **DEV** | Terraform deployment testing — validates IaC and workflow changes before prod | Auto on `main` merge |
| **PROD** | Live environment — identical Terraform config, different `.tfvars` | Manual trigger + approval gate |

## Key Rules

- **SBX is the only environment where the portal designer is used.** Workflows built here are exported as `workflow.json` and committed to the repo.
- **SBX is never deployed from Terraform** — it exists purely for GUI-based development.
- **DEV and PROD are identical in structure** — same Terraform code, different `environments/*.tfvars` (resource names, email recipients, workspace targets).
- **Zip deploy is part of `terraform apply`** — `archive_file` zips `workflows/` at plan time; `terraform_data` runs `az functionapp deployment source config-zip` only when workflow content changes (hash-based). No separate pipeline stage.
- **OAuth connections** (e.g. Office 365) need one-time manual portal authorization per environment after first `terraform apply`. The runtime URL is already set by Terraform; only the consent step is manual.
