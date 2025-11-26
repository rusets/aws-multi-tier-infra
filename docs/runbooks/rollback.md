# Runbook — Rollback After Failed Deploy

## 1. Summary
Rollback is needed when `terraform apply` partially provisions the environment  
or produces a broken state that cannot be resolved by re-running apply.

This runbook defines safe, deterministic recovery steps.

---

## 2. Symptoms
Rollback is required if:

- ALB created but EC2 not registered  
- RDS created but app cannot connect  
- Terraform state drift detected  
- `apply` fails repeatedly at the same resource  
- GH Actions gets stuck in apply → error → wake loop  

---

## 3. Diagnostics

### 3.1 Inspect last Terraform run

```bash
gh run list -w infra.yml
gh run view <run-id>
```

Check for:
- Subnet CIDR conflicts  
- Route53 record already exists  
- ALB name already exists  
- RDS instance stuck in “creating”  

---

### 3.2 Check AWS resources for drift

```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=multi-tier-demo-*"
aws rds describe-db-instances
aws elbv2 describe-load-balancers
```

If resources exist that **should not**, rollback is required.

---

### 3.3 Check DynamoDB TF lock

```bash
aws dynamodb scan \
  --table-name multi-tier-demo-tfstate-LOCK \
  --query "Items"
```

If stale lock exists → must delete manually.

---

## 4. Remediation (Rollback Procedure)

### Step 1 — Reset destroy cooldown

```bash
aws ssm delete-parameter \
  --name /multi-tier-demo/destroy_dispatched_epoch
```

---

### Step 2 — Force full destroy

```bash
gh workflow run infra.yml \
  -f action=destroy \
  -f auto_approve=true
```

Wait 5–8 minutes until infrastructure is fully gone.

---

### Step 3 — Verify clean slate

```bash
aws ec2 describe-instances
aws rds describe-db-instances
aws elbv2 describe-load-balancers
```

All must return **empty** for demo resources.

---

### Step 4 — Apply fresh deployment

```bash
gh workflow run infra.yml \
  -f action=apply \
  -f auto_approve=true
```

Wait 12–15 minutes for full wake.

---

## 5. Root Causes

| Category | Examples |
|---------|----------|
| **Terraform drift** | External manual edits break state |
| **Interrupted destroy** | RDS or ALB left partially deleted |
| **State corruption** | DynamoDB lock stuck |
| **Version mismatch** | Outdated AMI, outdated provider version |
| **Network conflicts** | Overlapping CIDRs |

---

## 6. Prevention
- Never modify AWS infra manually  
- Keep provider versions pinned  
- Avoid interrupting destroy runs  
- Keep AMI ID up to date  
- Run `terraform fmt + validate` pre-PR  
- Enable terraform-ci.yml with tfsec/checkov  

---

## 7. Escalation
If rollback repeatedly fails:

1. Delete S3 state file manually  
2. Delete DynamoDB lock table rows  
3. Rebuild from scratch:

```bash
rm -rf .terraform terraform.tfstate*
terraform init
```

4. Re-run apply.

If still broken → open `wake-failure.md` or run post-mortem.
