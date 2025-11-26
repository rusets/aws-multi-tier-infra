# Cost Model & Optimization

This project is built around wake-on-demand architecture to minimize AWS cost.

## Cost While Awake
Approximate monthly cost if the environment stays online continuously:
- **EC2 ASG:** $10–15/month
- **RDS t3.micro:** $12–15/month
- **S3 + CloudFront:** < $1/month
- **Lambda + API GW:** negligible (< $0.10)
- **SSM Parameters:** free (standard tier)

Total always-on ≈ **$25–32/month**

## Cost While Sleeping
With autosleep after X minutes:
- EC2 → $0  
- RDS → $0 (destroyed)  
- Only S3/CF/SSM remain → < **$1/month**

## Wake Overhead

Each wake event incurs the following operational cost and time:

- **GitHub Actions runner time:** ~1–2 minutes  
- **Terraform operations:** 3–5 minutes  
- **AWS service cold starts:**  
  - EC2 ASG instance warm-up: 60–120 seconds  
  - RDS initialization: 2–4 minutes  
- **Total wake time:** typically **8–15 minutes**  
  (from pressing “Wake” to the application responding over HTTPS)

There is **no persistent cost** once the idle reaper destroys all resources.

## Key Optimization Principles
- Destroy infrastructure on inactivity  
- Stateless frontend via S3  
- OIDC (no permanent IAM users)  
- Auto-scaling app layer only during active sessions
