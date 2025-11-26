# Runbook — Destroy Not Triggered

## 1. Summary
Idle-Reaper should destroy the environment when it has been idle long enough.  
If destroy does **not** trigger, stale infrastructure may remain online, increasing cost.

This runbook describes how to diagnose and manually initiate destroy.

---

## 2. Symptoms
- Environment remains **awake** past the configured idle timeout  
- `/status` reports “ready” indefinitely  
- Idle-Reaper Lambda logs show no destroy attempts  
- SSM parameter `/multi-tier-demo/destroy_dispatched_epoch` does not update  
- GitHub Actions `infra.yml` not triggered automatically  

---

## 3. Diagnostics

### 3.1 Check Idle-Reaper Lambda logs

```bash
aws logs tail /aws/lambda/multi-tier-demo-idle-reaper --since 15m
```

Look for:
- `IDLE_MINUTES` too high  
- GitHub token missing or invalid  
- “cooldown active” message  
- Lambda timeouts or throttling  

---

### 3.2 Verify last heartbeat

```bash
aws ssm get-parameter \
  --name /multi-tier-demo/last_wake \
  --query 'Parameter.Value' \
  --output text
```

If timestamp is **recent**, environment is still “active”.

If timestamp is **old** but destroy not triggered → reaper failed.

---

### 3.3 Check destroy cooldown

```bash
aws ssm get-parameter \
  --name /multi-tier-demo/destroy_dispatched_epoch \
  --query 'Parameter.Value' \
  --output text
```

If value exists → cooldown is preventing destroy.

Cooldown normally lasts **30 minutes**.

---

### 3.4 Check GitHub Actions workflow permissions

```bash
gh api repos/rusets/aws-multi-tier-infra/actions/workflows
```

Confirm:
- Workflow is enabled  
- INFRA_ARMED == “on”  

---

## 4. Remediation

### Step 1 — Clear cooldown

```bash
aws ssm delete-parameter \
  --name /multi-tier-demo/destroy_dispatched_epoch
```

---

### Step 2 — Manually trigger destroy

```bash
gh workflow run infra.yml \
  -f action=destroy \
  -f auto_approve=true
```

Wait for full destroy: **5–8 minutes**.

---

### Step 3 — Re-enable automation (if disabled)

```bash
gh variable set INFRA_ARMED -b on -R rusets/aws-multi-tier-infra
```

---

## 5. Root Causes

| Category | Examples |
|---------|----------|
| **Cooldown stuck** | Parameter persists due to failed execution |
| **GitHub token invalid** | Reaper cannot trigger workflow |
| **SSM parameter drift** | Heartbeat not updating |
| **OIDC misconfigured** | Reaper can’t assume GitHub role |
| **Workflow disabled** | GitHub Actions blocked |

---

## 6. Prevention
- Rotate GitHub PAT regularly  
- Keep cooldown logic simple (30min default)  
- Ensure Lambda concurrency = 1  
- Avoid rapid wake/destroy cycles during testing  
- Enable GH Actions cleanup to avoid stale runs  

---

## 7. Escalation
If destroy never triggers even after resets:

1. Recreate GitHub PAT in SSM.  
2. Delete and recreate Lambda IAM role.  
3. Re-run entire control-plane Terraform.  

If still unresolved → proceed to `rollback.md`.
