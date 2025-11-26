# ADR 0003 — Wake/Sleep Architecture for Cost Optimization

## Status
Accepted

## Context
Running a full multi-tier stack (EC2, RDS, ALB) 24/7 costs $25–35/month.  
The project goal is near-zero cost while keeping production-grade infrastructure.

## Decision
Implement **on-demand provisioning** using:
- API Gateway → Lambda → GitHub Actions (wake)
- Idle-Reaper Lambda (sleep/destroy)
- SSM Parameters for heartbeat tracking

## Rationale
- Zero cost while idle  
- Environment spins up only when required  
- Perfect for demos, interviews, and credit-limited accounts  
- Infrastructure always starts “clean” (no drift)  

## Consequences
- Cold start time ~12–15 minutes  
- Requires orchestration pipeline (Lambda + GHA + Terraform)  

