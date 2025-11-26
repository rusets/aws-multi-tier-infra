# Runbook — Wake Pipeline Failure

## 1. Summary
Wake sequence failed during provisioning (`terraform apply`).  
User sees **Waking…** for too long or the wait-site reports an error.  
System is stuck in a **partial provisioning state**.

---

## 2. Symptoms
You are dealing with this issue if:

- `/status` remains in `waking` for more than **15 minutes**
- No transition to **ready**
- GitHub Actions `infra.yml` run failed
- Environment exists partially (EC2 up but RDS/ALB missing)
- Idle-Reaper does not automatically destroy the broken environment

---

## 3. Diagnostics

### 3.1 Check GitHub Actions logs

```bash
gh run list -w infra.yml
gh run view <run-id>
```

Look for:
- DynamoDB lock errors
- Resource conflicts (e.g., “ALB already exists”)
- Missing Terraform variables
- Invalid subnet CIDRs
- AccessDenied / OIDC assume-role failures

---

### 3.2 Check SSM heartbeat parameter

```bash
aws ssm get-parameter \
  --name /multi-tier-demo/last_wake \
  --query 'Parameter.Value' \
  --output text
```

If timestamp is **old** → heartbeat stuck → wake sequence failed early.

---

### 3.3 Check Lambda wake + status logs

```bash
aws logs tail /aws/lambda/multi-tier-demo-wake --since 15m
aws logs tail /aws/lambda/multi-tier-demo-status --since 15m
```

Watch for:
- Missing GitHub token
- Invalid repository_dispatch payload
- GitHub API errors
- API Gateway → Lambda mapping issues

---

### 3.4 Check DynamoDB lock (possible stale lock)

```bash
aws dynamodb scan \
  --table-name multi-tier-demo-tfstate-LOCK \
  --query "Items"
```

If you see a lock that is older than **10 minutes**, Terraform is stuck.

---

## 4. Remediation

### Step 1 — Reset destroy cooldown (common)
```bash
aws ssm delete-parameter \
  --name /multi-tier-demo/destroy_dispatched_epoch
```

---

### Step 2 — Force-destroy broken infra
```bash
gh workflow run infra.yml \
  -f action=destroy \
  -f auto_approve=true
```

Wait 6–8 minutes.

---

### Step 3 — Retry wake with a fresh apply
```bash
gh workflow run infra.yml \
  -f action=apply \
  -f auto_approve=true
```

Expected full wake time: **12–15 minutes**.

---

## 5. Root Causes

| Category | Examples |
|---------|----------|
| **Terraform drift** | Subnet overlap, Route53 CNAME already exists |
| **Stale resources** | RDS instance interrupted mid-delete |
| **State lock stuck** | DynamoDB lock not released |
| **GH Actions/OIDC issues** | Invalid assume-role request |
| **Lambda errors** | Payload invalid or GitHub API throttled |

---

## 6. Prevention

- Avoid editing AWS resources manually through the console
- Keep ALB, RDS, subnet CIDRs controlled only through Terraform
- Ensure GitHub Actions uses **pinned commit SHAs**
- Min retention for workflow logs + automatic cleanup
- Use TF_LOCK_TIMEOUT ≥ **10 minutes**

---

## 7. Escalation
If wake still fails after destroy → apply → destroy cycle:

1. Delete DynamoDB lock table rows manually.  
2. Manually delete VPC + subnets (if drifted).  
3. Re-run Terraform from scratch.

If still stuck → open `docs/runbooks/rollback.md`.
