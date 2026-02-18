# Incident: GitHub Token Expiration Impacting Auto-Destroy Pipeline

Date: February 2026  
Environment: Multi-Tier AWS Demo (Wake/Sleep Architecture)

---

## Summary

The automated destroy workflow stopped triggering after the configured idle timeout.

The Idle-Reaper Lambda executed successfully, but the GitHub workflow responsible for running `terraform destroy` was never dispatched.

The root cause was an expired GitHub Personal Access Token stored in AWS SSM.

No Terraform, infrastructure, or application logic changes were involved.

---

## Architecture Context

The environment uses an event-driven wake/sleep model:

- Idle-Reaper Lambda runs every minute.
- After `IDLE_MINUTES`, it triggers a GitHub `workflow_dispatch`.
- GitHub Actions executes `terraform destroy`.
- Infrastructure is fully torn down.

The GitHub API authentication token is stored securely in AWS SSM.

---

## Timeline

Initial symptom:
Auto-destroy did not trigger after idle timeout.

Observation:
- Lambda executed normally.
- Auto Scaling Group scaled to zero.
- No Terraform destroy workflow appeared in GitHub Actions.

CloudWatch logs showed:

github_dispatch_http_error  
401 Bad credentials

Manual API test confirmed:

GitHub API returned 401 when authenticating with the stored token.

Root cause identified:
GitHub Personal Access Token had expired.

---

## Impact

- Auto-destroy workflow failed silently.
- Infrastructure remained deployed longer than expected.
- Manual intervention required.
- Minor additional cloud cost exposure.
- No security breach or data impact.

---

## Root Cause

The GitHub Personal Access Token used for workflow dispatch had expired.

The Idle-Reaper Lambda:

1. Retrieved the token from AWS SSM.
2. Attempted GitHub workflow dispatch.
3. Received HTTP 401.
4. Failed to trigger destroy workflow.

The automation logic itself functioned correctly.

The failure occurred at the external API authentication layer.

---

## Resolution

- Deleted expired GitHub token.
- Generated a new token with required scopes (repo, workflow).
- Updated the SSM SecureString parameter.
- Manually validated GitHub API authentication.
- Confirmed successful workflow dispatch.

Auto-destroy resumed normal operation immediately.

No infrastructure code modifications were required.

---

## Detection & Observability Notes

The failure was not immediately obvious because:

- Lambda did not crash.
- Logs contained 401 errors but no fatal exceptions.
- Terraform was never invoked, so no Terraform-level errors appeared.

Improvement opportunity:
Add CloudWatch metric filter or alarm on github_dispatch_http_error events.

---

## Preventive Improvements

Potential hardening options:

- CloudWatch alarm on GitHub dispatch failures.
- Token expiration tracking policy.
- Migration from PAT to GitHub App authentication.
- Add retry and failure visibility in automation logs.
- Prevent scale-to-zero before successful dispatch confirmation.

---

## Engineering Takeaways

- Infrastructure automation depends on external credential lifecycle.
- Expired tokens can silently break CI/CD-driven orchestration.
- Observability must extend across integration boundaries.
- Automation pipelines should validate external API authentication explicitly.

The incident reinforced the importance of treating credential management as part of production reliability.

Infrastructure code remained correct.
