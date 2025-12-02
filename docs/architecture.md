## Project Structure

```text
aws-multi-tier-infra/
├── .checkov.yml
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug.md                    # Bug report template
│   │   └── feature.md                # Feature request template
│   ├── pull_request_template.md      # Pull Request checklist
│   └── workflows/
│       ├── app.yml                   # App CI/CD (build & deploy artifacts)
│       ├── cleanup.yml               # GitHub logs / artifacts cleanup
│       ├── infra.yml                 # Terraform apply/destroy via OIDC
│       └── terraform-ci.yml          # fmt / validate / security checks
├── app/
│   ├── public/                       # Static assets for Notes App
│   ├── package.json
│   └── server.js                     # Node.js Notes App (backend + simple UI)
├── bootstrap/
│   └── user_data.sh                  # EC2 bootstrap script:
│                                     # - install runtime
│                                     # - fetch secrets/configs from SSM
│                                     # - start app service
├── build/                            # Build artifacts (ignored in source control)
├── docs/
│   ├── architecture.md               # This file — architecture overview + structure
│   ├── cost.md                       # Cost profile & optimization strategies
│   ├── monitoring.md                 # Metrics, dashboards, health checks
│   ├── slo.md                        # Service Level Objectives and SLIs
│   ├── threat-model.md               # Threat model & security assumptions
│   ├── adr/                          # Architectural Decision Records
│   ├── runbooks/                     # Incident response & operational runbooks
│   ├── diagrams/                     # Architecture diagrams (Mermaid/PNG)
│   └── screens/                      # Screenshots of UI and AWS console
├── infra/
|   ├── .tflint.hcl
│   ├── alb_domain.tf                 # ALB hostname, Route 53 records, HTTPS
│   ├── artifacts.tf                  # App build/package -> S3 artifact bucket
│   ├── backend.tf                    # Terraform remote state (S3 + DynamoDB)
│   ├── locals.paths.tf               # Paths and naming for builds and artifacts
│   ├── main.tf                       # Core infra: VPC, subnets, ALB, ASG, RDS, SGs
│   ├── outputs.tf                    # Outputs used by lambdas and external systems
│   ├── providers.tf                  # AWS provider & required versions
│   ├── ssm.tf                        # SSM parameter definitions (config, heartbeats)
│   ├── variables.tf                  # Input variables for the stack
│   └── control-plane/                # Serverless wake/sleep control plane
│       ├── api.tf                    # HTTP API for wake/status endpoints
│       ├── backend.tf                # Separate remote state for control-plane
│       ├── dist/                     # Bundled Lambda deployment packages
│       ├── idle.tf                   # Idle Reaper scheduler and permissions
│       ├── lambdas.tf                # Lambda functions (wake, status, heartbeat, reaper)
│       ├── outputs.tf
│       ├── terraform.tfvars.example  # Sample vars for control-plane
│       ├── variables.tf
│       └── versions.tf               # Required versions
├── lambda/
│   ├── heartbeat/                    # Lambda: updates SSM heartbeat timestamp
│   ├── idle_reaper/                  # Lambda: checks idle time and triggers destroy
│   ├── status/                       # Lambda: reports infra status to wait-site
│   └── wake/                         # Lambda: triggers GitHub Actions apply
├── scripts/
│   └── rdapp.service                 # systemd unit file for Notes App on EC2
└── wait-site/
    └── index.html                    # Static “Wake” page with progress / status UI
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



