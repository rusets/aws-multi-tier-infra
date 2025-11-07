# AWS Multi-Tier Demo (Terraform + EC2 + ALB + RDS + CI/CD)

This repository contains a **production-like multi-tier example** built with Terraform:
- **VPC** with public/private subnets
- **ALB** routing to an **Auto Scaling Group** (Amazon Linux 2023)
- **RDS Postgres** with AWS-managed master secret in **Secrets Manager**
- **SSM Parameter Store** for non-secret config and artifact pointer
- **S3 assets bucket** for application artifacts
- **EC2 user_data** that deploys a small **Node.js/Express + PostgreSQL** app and runs idempotent DB migrations
- **GitHub Actions (OIDC)** for infra and app CI/CD

> All comments in Terraform files are in **English**, terminal snippets are Unix-style (bash/zsh).

---

## Repository layout

```
.
├── app/                        # Application source (Node.js/Express + public assets)
├── docs/                       # Screenshots, diagrams, logs for documentation
├── scripts/                    # Helper shell scripts (manual ops/bootstrap)
├── app-initial.zip             # Initial packaged app (uploaded to S3 on first apply)
├── artifacts.tf                # Package & upload app artifact to S3
├── backend.tf                  # S3 + DynamoDB backend config for Terraform state
├── bucket-policy.json          # Minimal IAM policy for Terraform backend S3 bucket
├── github-oidc-provider.json   # OIDC provider definition (GitHub)
├── github-oidc-trust.json      # Trust relationship doc for GitHub → IAM role
├── iam-github.tf               # GitHub OIDC roles, policies, and attachments
├── main.tf                     # Core networking (VPC, Subnets, ALB, ASG, RDS)
├── outputs.tf                  # Terraform outputs (ALB DNS, RDS endpoint, secrets, etc.)
├── providers.tf                # Terraform + AWS provider configuration
├── ssm.tf                      # SSM Parameter Store keys (/multi-tier-demo/…)
├── terraform.tfstate           # Local Terraform state (prefer remote S3 backend)
├── terraform.tfstate.backup    # Backup of state
├── tf-allow-iam-bootstrap.json # Bootstrap IAM policy (allow creating initial roles)
├── tf-backend-access.json      # IAM policy granting access to S3 + DynamoDB backend
├── tf-destroy-extra.json       # IAM policy for destroy (extra permissions if needed)
├── tf-iam-bootstrap.json       # IAM bootstrap policy (create TF role, OIDC, etc.)
├── tf-iam-bootstrap-read.json  # Read-only variant of bootstrap policy
├── tf-iam-read.json            # Minimal read-only policy (e.g., for CI)
├── tf-trust-fix.json           # Updated trust relationship doc for TF role
├── tf-trust.json               # Original trust relationship doc
├── tf-trust.json.bak           # Backup copy of trust doc
├── user_data.sh                # Cloud-init script (deploy app + DB migrations on EC2)
├── variables.tf                # Input variables (region, project_name, app_port, etc.)
└── .github/workflows/
    ├── infra.yml               # CI: Terraform plan/apply/destroy via OIDC
    └── app.yml                 # CI: Build app, upload artifact, update SSM + ASG refresh
```

---

## Prerequisites

- Terraform **>= 1.6** (repo pins 1.9.5 in CI, but 1.6+ works)
- AWS account + credentials locally for first bootstrap (`aws configure`)  
  After that, CI uses **OIDC** and does not need stored keys.
- Region: default **us-east-1** (change via `variables.tf` if needed)
- Node 18+ locally only if you want to run the app yourself

---

## Quick start (local Terraform)

```bash
# 1) Init
terraform init

# 2) Review plan
terraform plan

# 3) Apply (creates VPC, ALB, RDS, S3, SSM, IAM, ASG, etc.)
terraform apply -auto-approve

# 4) Grab outputs
terraform output
# alb_dns_name = multi-tier-demo-alb-XXXXXXXX.us-east-1.elb.amazonaws.com
# rds_endpoint = multi-tier-demo-db.xxxxxx.us-east-1.rds.amazonaws.com
# rds_master_secret_arn = arn:aws:secretsmanager:us-east-1:...:secret:...
# s3_assets_bucket = multi-tier-demo-assets-<rand>
```

### First-boot flow (user_data.sh)

1. Read **SSM** parameters:
   - `${PARAM_PATH}/assets_bucket`
   - `${PARAM_PATH}/app/artifact_key`
   - `${PARAM_PATH}/db/*` (optional)
2. If `RDS_SECRET_ARN` is set → Secrets Manager has priority.
3. Download the ZIP artifact from S3 → `/opt/app/releases` → extract to `/opt/app/current`.
4. Install dependencies (`npm ci` or `npm install`).
5. Write `.env` with `PORT`, DB creds, etc.
6. Run idempotent SQL migrations (create DB if missing, alter schema if needed).
7. Start `rdapp.service` systemd unit.

---

## CI/CD with GitHub Actions (OIDC)

- **Role for Terraform**: `multi-tier-demo-github-tf`  
  Used by `.github/workflows/infra.yml`

- **Role for App Deploy**: `multi-tier-demo-github-app`  
  Used by `.github/workflows/app.yml` to:
  - Build/zip the app
  - Upload to S3
  - Update SSM key `${PARAM_PATH}/app/artifact_key`
  - Trigger ASG rolling replace

---

## Configuration (SSM + Secrets Manager)

- **Parameter Store prefix**: `/multi-tier-demo`
- Keys:
  - `/multi-tier-demo/assets_bucket`
  - `/multi-tier-demo/app/artifact_key`
  - `/multi-tier-demo/app/app_port`
  - `/multi-tier-demo/db/*`
- **Secrets Manager**:
  - Terraform output `rds_master_secret_arn` is passed to instances.
  - Overrides SSM values for DB connection.

---

## App details

- Express app (`server.js`) with PostgreSQL (`pg`).
- Static UI at `public/index.html`.
- Environment from `.env` (written in `user_data.sh`).

---

## Migrations strategy

- Current: simple SQL idempotent migrations inside `user_data.sh`.
- Future: add Knex/Sequelize migrations.

---

## Troubleshooting

- Logs: `/var/log/cloud-init-output.log`, `/var/log/rdapp-userdata.log`
- App logs: `journalctl -u rdapp.service -e`
- Common issues:
  - Invalid `package.json`
  - Wrong `.env` heredoc
  - Port confusion (use ALB DNS on 80, not EC2:80)

---

## Clean up

```bash
terraform destroy -auto-approve
```

If SSM parameters or policies are left behind, remove them manually.

---

## Screenshots

Store screenshots in `docs/`:

```
docs/
├── terraform-apply.png
├── alb-health.png
├── ssm-parameters.png
├── rds-secret.png
└── cloud-init-log.png
```

---

## Security notes

- CI roles use **least privilege** (S3 + SSM only).
- DB credentials come from Secrets Manager by default.

---

## License

MIT (or your choice).
