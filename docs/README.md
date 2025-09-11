# AWSsss Multi‑Tier Demo (Terraform + EC2 + ALB + RDS + CI/CD)

This repository contains a **production‑like multi‑tier example** built with Terraform:
- **VPC** with public subnets
- **ALB** routing to an **Auto Scaling Group** (Amazon Linux 2023)
- **RDS Postgres** with AWS‑managed master secret in **Secrets Manager**
- **SSM Parameter Store** for non‑secret config and artifact pointer
- **S3 assets bucket** for app artifacts
- **EC2 user_data** that deploys a small **Node.js/Express + PostgreSQL** app and runs idempotent DB migrations
- **GitHub Actions (OIDC)** for infra and app CI/CD

> Comments in repo code are in **English**, terminal snippets are Unix‑style (bash/zsh).

---

## Repository layout

```
.
├── app/                        # Node app (server.js, public/index.html, package.json)
├── public/                     # (If you prefer serving static only; optional)
├── user_data.sh                # Cloud‑init script run on each EC2 instance
├── main.tf                     # Core networking + ALB + ASG + RDS wiring
├── variables.tf                # Input variables (project_name, region, app_port, etc.)
├── providers.tf                # TF + AWS provider pins
├── ssm.tf                      # SSM Parameter Store keys (/multi-tier-demo/...)
├── artifacts.tf                # Archive & upload initial app artifact to S3
├── iam-github.tf               # GitHub OIDC providers + roles/policies
├── outputs.tf                  # Useful outputs (ALB DNS, RDS endpoint, Secret ARN, bucket)
└── .github/workflows/
    ├── infra.yml              # Terraform plan/apply via OIDC
    └── app.yml                # Build/zip app and upload artifact to S3 + update SSM pointer
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

### First‑boot flow (what `user_data.sh` does)

1. Read **SSM**:
   - `${PARAM_PATH}/assets_bucket` (default `/multi-tier-demo`)
   - `${PARAM_PATH}/app/artifact_key` (defaults to `artifacts/app-initial.zip`)
   - `${PARAM_PATH}/db/*` (optional, if not using Secrets Manager)
2. If `RDS_SECRET_ARN` is set in the Launch Template, **Secrets Manager** has priority for `host/username/password/dbname`.
3. Download the ZIP from `s3://$ASSETS_BUCKET/$ARTIFACT_KEY` into `/opt/app/releases` and extract to `/opt/app/current`.
4. Install dependencies (`npm ci` if lockfile, otherwise `npm install --omit=dev`).
5. Write `/opt/app/current/.env`:
   - `PORT, DB_HOST, DB_USER, DB_PASSWORD, DB_PASS (compat), DB_NAME`
6. **Migrate database** (idempotent SQL fallback):
   - Create DB if missing
   - Ensure `public.notes(id, title, created_at)`
   - Migrate legacy column `text -> title` and drop `text`
   - Create index on `created_at`
7. Create and start **systemd unit** `rdapp.service` (Node app).

---

## Test the app

### From your laptop (through ALB)

```bash
ALB_DNS="$(terraform output -raw alb_dns_name)"

# Health check
curl -sS "http://${ALB_DNS}/health" && echo

# DB check
curl -sS "http://${ALB_DNS}/db" && echo

# Create note
curl -sS -H 'Content-Type: application/json' \
  -d '{"title":"hello from ALB 🎉"}' "http://${ALB_DNS}/api/notes" && echo

# List notes
curl -sS "http://${ALB_DNS}/api/notes" && echo
```

### On an instance (SSH optional if you allow it)

```bash
# Use private IP/localhost and app port (default 3000)
curl -sS "http://127.0.0.1:3000/health" && echo
curl -sS "http://127.0.0.1:3000/db" && echo
```

---

## CI/CD with GitHub Actions (OIDC)

This repo includes two workflows that assume **OIDC roles** created by Terraform:

- **Role for Terraform**: `multi-tier-demo-github-tf`  
  Used by `.github/workflows/infra.yml`

- **Role for App Deploy**: `multi-tier-demo-github-app`  
  Used by `.github/workflows/app.yml` to:
  - Build/zip the app
  - Upload to S3: `s3://multi-tier-demo-assets-*/artifacts/app-<ts>-<sha>.zip`
  - Update SSM key `${PARAM_PATH}/app/artifact_key` to the new ZIP key

### `infra.yml` (Terraform)

- Triggers:
  - Pull request touching `*.tf`: runs **plan**
  - Push to `main` touching `*.tf`: runs **apply**
- Uses the OIDC role: `arn:aws:iam::<account>:role/multi-tier-demo-github-tf`

### `app.yml` (Application)

- Triggers:
  - Push to `main` touching `app/**`, `public/**`, or the workflow file
- Steps:
  1. Assume OIDC role `multi-tier-demo-github-app`
  2. Read SSM `${PARAM_PATH}/assets_bucket`
  3. Build app and zip it
  4. Upload ZIP to `s3://$ASSETS_BUCKET/artifacts/<zip>`
  5. `ssm put-parameter --overwrite` `${PARAM_PATH}/app/artifact_key` to the new key
  6. **ASG rolling replace** will fetch the new artifact for new instances

> **Note:** Existing instances will not self‑update. Rolling updates happen via ASG lifecycle (scale‑in/out, instance refresh) or your deployment policy. You can also trigger an **Instance Refresh** in the ASG after artifact update.

---

## Configuration (SSM + Secrets Manager)

- **Parameter Store prefix**: `/multi-tier-demo` (change via `var.param_path` / `var.namespace`)
  - `/multi-tier-demo/assets_bucket`
  - `/multi-tier-demo/app/artifact_key`
  - `/multi-tier-demo/app/app_port`
  - `/multi-tier-demo/db/*` (host/username/name, optionally password if you set `ssm_write_db_password=true`)

- **RDS Secrets Manager** (preferred for credentials):  
  Terraform output **`rds_master_secret_arn`** passes the ARN to the Launch Template / user data as `RDS_SECRET_ARN`. When set, it **overrides** SSM values for DB connection.

---

## App details

- `server.js` (Express + pg) reads:
  - `PORT`
  - `DB_HOST`, `DB_USER`, `DB_PASSWORD` (and `DB_PASS` for backward compat), `DB_NAME`
  - SSL is enabled with `rejectUnauthorized:false` (safe for RDS defaults; for strict TLS pinning, upload CA and configure accordingly).
- Static UI at `public/index.html` (Bootstrap).

---

## Migrations strategy

- **Today**: user_data runs **idempotent SQL** to ensure the minimal schema.
- **Later (optional)**: adopt **Knex** or **Sequelize** with versioned migrations:
  - Add `knexfile.js` and `/migrations/*`
  - In `user_data.sh`, the script already checks for `knexfile.js` (you can enable the “prefer Knex” block later).  
  - CI can also run migrations out‑of‑band if you prefer (one‑time task, not per‑instance).

---

## Troubleshooting

**Where are logs?**
- Cloud‑init/user‑data: `/var/log/cloud-init-output.log`, `/var/log/rdapp-userdata.log`
- App (systemd): `journalctl -u rdapp.service -e`

**Common issues**

- **`package.json` must be valid JSON**  
  Do **not** put `// comments`. If you need notes, use README or comments in JS files.

- **`.env` heredoc breaks with invalid quoting**  
  The script uses a safe heredoc. If you edit it, keep the structure intact.

- **Cannot reach on port 80**  
  The app listens on `PORT` (default **3000**). The ALB listens on **80** and forwards to target group on `PORT`. Hitting instance `localhost:80` won’t work; use `localhost:3000` or go through the ALB DNS on port 80.

- **“ParameterAlreadyExists” in SSM**  
  Terraform state no longer owns that key. Either delete manually or set `overwrite = true` on the resource.

---

## Clean up

```bash
terraform destroy -auto-approve
```

If SSM parameters were created outside of Terraform or left behind, remove them manually to avoid conflicts on next apply.

---

## Screenshots

Place screenshots in `docs/` and reference them here. Examples (optional):

```
docs/
├── terraform-apply.png          # Plan/apply output
├── alb-health.png               # /health via ALB
├── ssm-parameters.png           # SSM keys in console
├── rds-secret.png               # Secrets Manager entry
└── cloud-init-log.png           # /var/log/cloud-init-output.log
```

Embed like:

```md
![ALB health](docs/alb-health.png)
```

---

## Security notes

- Least‑privilege for CI is implemented: the app role can only access `multi-tier-demo-assets-*` and SSM under your `${param_path}`.
- DB creds should come from **Secrets Manager** (preferred). SSM `password` is disabled by default (`ssm_write_db_password=false`).

---

## Useful one‑liners

```bash
# Show outputs raw
terraform output -json | jq

# Tail user data log
sudo tail -f /var/log/rdapp-userdata.log

# App logs
sudo journalctl -u rdapp.service -f

# Curl through ALB (replace with your output)
ALB_DNS="multi-tier-demo-alb-XXXXX.us-east-1.elb.amazonaws.com"
curl -sS "http://${ALB_DNS}/health" && echo
curl -sS "http://${ALB_DNS}/db" && echo
```

---

## License

MIT (or your choice).

---

### Attributions

- Amazon Linux 2023, ALB, RDS, SSM, Secrets Manager
- Terraform AWS Provider
- Node.js, Express, pg, Bootstrap
