## Project Structure

```text
aws-multi-tier-infra/
├── .checkov.yml                      # Checkov config (policy-as-code)
├── .gitignore                        # Ignore rules (builds, .terraform/, logs)
├── .tflint.hcl                       # TFLint config (lint rules for Terraform)
├── LICENSE                           # MIT License (root-level, always)
├── README.md                         # Main documentation (architecture + usage)
│
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug.md                    # Bug report form
│   │   └── feature.md                # Feature request form
│   ├── pull_request_template.md       # PR checklist
│   └── workflows/
│       ├── app.yml                   # App build → artifacts S3
│       ├── cleanup.yml               # Auto-purge old GitHub Actions logs
│       ├── infra.yml                 # Terraform apply/destroy via OIDC
│       └── terraform-ci.yml          # fmt/validate/lint/security scans
│
├── app/                               # Notes App (Node.js)
│   ├── public/
│   ├── package.json
│   └── server.js
│
├── bootstrap/
│   └── user_data.sh                   # EC2 bootstrap (install app + fetch SSM)
│
├── build/                             # Local build output (ignored)
│
├── docs/                              # All documentation
│   ├── architecture.md
│   ├── cost.md
│   ├── monitoring.md
│   ├── slo.md
│   ├── threat-model.md
│   ├── adr/
│   ├── runbooks/
│   ├── diagrams/
│   └── screens/
│
├── infra/                             # Terraform — main infra
│   ├── alb_domain.tf
│   ├── artifacts.tf
│   ├── backend.tf
│   ├── locals.paths.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── ssm.tf
│   ├── variables.tf
│   └── control-plane/                 # Serverless wake/sleep automation
│       ├── api.tf
│       ├── backend.tf
│       ├── dist/
│       ├── idle.tf
│       ├── lambdas.tf
│       ├── outputs.tf
│       ├── terraform.tfvars.example
│       ├── variables.tf
│       └── versions.tf
│
├── lambda/                            # Python sources (raw Lambdas)
│   ├── heartbeat/
│   ├── idle_reaper/
│   ├── status/
│   └── wake/
│
├── scripts/
│   └── rdapp.service                  # systemd unit for Notes App
│
└── wait-site/
    └── index.html                     # Static wait page (S3+CloudFront)
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



