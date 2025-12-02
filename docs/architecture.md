## Project Structure

```text
aws-multi-tier-infra/
├── .checkov.yml                      # Checkov policy-as-code configuration
├── LICENSE                           # MIT License for the entire project
├── README.md                         # Main documentation (architecture + usage)
│
├── .github/                          # GitHub Actions + templates
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug.md                    # Bug report form
│   │   └── feature.md                # Feature request form
│   ├── pull_request_template.md       # PR checklist for contributors
│   └── workflows/
│       ├── app.yml                   # Build & package Notes App to artifacts
│       ├── cleanup.yml               # Auto-delete old GitHub Actions logs/artifacts
│       ├── infra.yml                 # Terraform apply/destroy via OIDC
│       └── terraform-ci.yml          # fmt/validate/tflint/tfsec/checkov
│
├── app/                               # Notes App (backend + simple UI)
│   ├── public/                        # Static assets (HTML/CSS/JS/img)
│   ├── package.json
│   └── server.js                      # Node.js Express backend
│
├── bootstrap/
│   └── user_data.sh                   # EC2 bootstrap script (installs app + pulls SSM configs)
│
├── build/                             # Local build artifacts (Not committed)
│
├── docs/                              # Full documentation set
│   ├── architecture.md                # Architecture overview + diagrams
│   ├── cost.md                        # Cost model & Free Tier strategy
│   ├── monitoring.md                  # Metrics, alarms, health checks
│   ├── slo.md                         # SLO/SLI definitions for the demo
│   ├── threat-model.md                # Security assumptions & risks
│   ├── adr/                           # Architectural Decision Records (ADR-0001..)
│   ├── runbooks/                      # Operational runbooks (wake fail / destroy fail)
│   ├── diagrams/                      # Mermaid diagrams + PNG exports
│   └── screens/                       # Screenshots used inside README
│
├── infra/                             # Terraform (main compute/data plane)
│   ├── .tflint.hcl                    # TFLint configuration
│   ├── alb_domain.tf                  # ALB domain, TLS, Route 53 records
│   ├── artifacts.tf                   # App artifact bucket + upload logic
│   ├── backend.tf                     # Terraform backend (S3 + DynamoDB)
│   ├── locals.paths.tf                # Local values for artifact & build paths
│   ├── main.tf                        # Core infra (VPC, subnets, ALB, EC2, RDS)
│   ├── outputs.tf                     # Important outputs for Lambdas/control plane
│   ├── providers.tf                   # Providers + version constraints
│   ├── ssm.tf                         # SSM params (config, runtime values)
│   ├── variables.tf                   # Input variables for main infra
│   └── control-plane/                 # Serverless wake/sleep automation
│       ├── api.tf                     # API Gateway (HTTP) routes for wake/status
│       ├── backend.tf                 # Control-plane remote state backend
│       ├── dist/                      # Bundled Lambda deployment packages
│       ├── idle.tf                    # Idle Reaper logic + event rules
│       ├── lambdas.tf                 # Lambda sources (wake, status, heartbeat, reaper)
│       ├── outputs.tf                 # Exposed ARNs, endpoints for wait-site
│       ├── terraform.tfvars.example   # Example variables for reference
│       ├── variables.tf               # Control-plane input variables
│       └── versions.tf                # Required providers & versions
│
├── lambda/                            # Raw Lambda sources (Python)
│   ├── heartbeat/                     # Updates /last_wake SSM param
│   ├── idle_reaper/                   # Triggers destroy via GitHub API
│   ├── status/                        # Reports (idle / waking / ready)
│   └── wake/                          # Triggers GitHub Actions “apply”
│
├── scripts/
│   └── rdapp.service                  # Systemd unit for Notes App on EC2
│
└── wait-site/
    └── index.html                     # Static “Wake” page (status + progress bar)
```
---

# Architecture Overview

This project implements a cost-optimized, wake-on-demand multi-tier application on AWS.

## Core Components

- **VPC & Subnets** — isolated network layout with public/private segmentation.
- **Application Layer (EC2 ASG)** — Auto Scaling Group running the demo Notes App.
- **Data Layer (RDS)** — Amazon RDS with AWS-managed master password and private access.
- **Static Assets (S3)** — S3 bucket serving frontend bundles and static content.
- **ALB + Custom Domain** — Application Load Balancer with Route 53 DNS for friendly URL.
- **API Gateway (wake trigger)** — HTTP API that triggers the GitHub Actions “apply” pipeline.
- **Idle Reaper** — Lambda function monitoring inactivity and triggering automatic destroy.
- **Heartbeat Lambda** — periodically updates a heartbeat timestamp in SSM.
- **Status Lambda** — reports current infra state back to the wait-site.
- **SSM Parameter Store** — application configuration, artifact versioning, heartbeats.
- **Terraform IaC** — complete infrastructure lifecycle via GitHub OIDC and remote state.

## Wake → Run → Sleep Lifecycle

1. User opens the **wait-site** and clicks **“Wake”**.
2. The **wake Lambda** calls GitHub Actions to run **Terraform apply**.
3. Terraform provisions the full stack (VPC, ALB, EC2 ASG, RDS, SSM, etc.).
4. Once the stack is healthy, the user is redirected from the wait-site to the app.
5. The app (or a separate heartbeat Lambda) keeps updating an SSM heartbeat timestamp.
6. The **Idle Reaper** periodically checks inactivity via SSM:
   - If the system is idle longer than the configured timeout → triggers **Terraform destroy**.
7. After destroy, the system returns to the **minimal idle state** with only:
   - wait-site (S3 + CloudFront),
   - wake/status/control-plane Lambdas,
   - Terraform state backend.



