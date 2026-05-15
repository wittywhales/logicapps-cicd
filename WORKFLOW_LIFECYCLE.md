# Logic App Workflow Development Lifecycle

```mermaid
flowchart LR
    subgraph SBX["☁️ SBX — Design"]
        s1(["Portal GUI\nDesigner"])
        s2(["Iterate &\nTest"])
        s3(["Export\nworkflow.json"])
        s1 --> s2 --> s3
    end

    subgraph REPO["📁 Git Repo"]
        r1(["Update\nworkflows/"])
        r2(["Update Terraform\nif connections changed"])
        r3(["PR → merge\nto main"])
        r1 --> r2 --> r3
    end

    subgraph DEV["☁️ DEV — Validate"]
        d1(["terraform plan\n+ apply"])
        d2(["Zip deploy\nvia archive_file"])
        d3(["Test &\nValidate"])
        d1 --> d2 --> d3
    end

    subgraph PROD["☁️ PROD — Live"]
        p1(["terraform plan\n+ apply"])
        p2(["Approval\nGate"])
        p3(["Zip deploy\nvia archive_file"])
        p1 --> p2 --> p3
    end

    SBX -->|"copy JSON\nto repo"| REPO
    REPO -->|"pipeline auto-triggers\non main merge"| DEV
    DEV -->|"manual trigger\nwhen validated"| PROD
```

## Environment Roles

| Environment | Purpose | Deployment |
|---|---|---|
| **SBX** | GUI designer — build and iterate workflows using the portal; no pipeline | Manual (portal) |
| **DEV** | Terraform deployment testing — validates IaC changes before prod | Auto on `main` merge |
| **PROD** | Live environment — identical Terraform config, different `.tfvars` | Manual trigger + approval gate |

## Key Rules

- **SBX is the only environment where the portal designer is used.** Workflows built here are exported as `workflow.json` and committed to the repo.
- **SBX is never deployed from Terraform** — it exists purely for GUI-based development.
- **DEV and PROD are identical in structure** — same Terraform code, different `environments/*.tfvars` (resource names, email recipients, workspace targets).
- **Workflow zip deploy happens automatically inside `terraform apply`** — no separate pipeline stage needed.
