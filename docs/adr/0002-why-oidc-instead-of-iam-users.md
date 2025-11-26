# ADR 0002 — Why OIDC Was Used Instead of IAM Users

## Status
Accepted

## Context
GitHub Actions needs access to AWS for Terraform apply/destroy operations.
Using long-lived IAM access keys is insecure and requires rotation.

## Decision
Use **OIDC federation between GitHub and AWS** for short-lived credentials.

## Rationale
- Zero static credentials in repo or runner  
- 100% least-privilege access scoped to role  
- Automatic session expiration  
- Industry best practice for CI/CD  
- Fine-grained trust policy limits to the exact repo and branch  

## Consequences
- Slightly more complex role setup  
- Requires AWS IAM understanding  
