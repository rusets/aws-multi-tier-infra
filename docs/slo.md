# Service Level Objectives (SLO)

These SLOs are defined for the demo architecture and describe expected operational behavior.

## Availability SLO
- **Target Uptime:** 95% (demo environment wakes/sleeps by design)
- **Wake Success Rate:** 99% (GitHub Actions apply must succeed)

## Performance SLO

- **EC2 cold start (ASG instance launch):** 60–120 seconds  
- **RDS initialization (cold start after create):** 2–4 minutes  
- **ALB provisioning + target registration:** 1–2 minutes  
- **Infrastructure apply duration (Terraform):** 3–5 minutes  
- **Full stack readiness:** typically **8–15 minutes** after a wake event  
  (from pressing “Wake” to serving traffic over HTTPS)

## Error Budget
The demo is allowed:
- Failed wakes: < 2 per month  
- Infra deployment failures: < 1 per 20 applies  
- Timeout failures: < 1 per 50 requests

## Latency Targets
- App response latency: < 200ms (steady state)  
- ALB → EC2 hop: < 30ms

These SLOs help validate system health and guide improvements.
