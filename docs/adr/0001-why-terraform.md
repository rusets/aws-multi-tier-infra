# ADR 0001 — Why Terraform Was Chosen

## Status
Accepted

## Context
The project requires consistent, repeatable provisioning of AWS infrastructure across multiple services:
EC2, RDS, ALB, VPC, API Gateway, Lambda, S3, CloudFront, and IAM roles.

Infrastructure drift and manual AWS Console changes would introduce risk and inconsistency.

## Decision
Use **Terraform** as the primary Infrastructure-as-Code tool.

## Rationale
- Mature ecosystem and strong AWS provider support  
- Declarative model with clear diff/plan workflow  
- Battle-tested state management with S3 + DynamoDB locks  
- Built-in modularity for multi-tier architectures  
- Ideal integration with GitHub Actions using OIDC  

## Consequences
- State storage required (solved via S3/DynamoDB)  
- Initial learning curve for complex modules  
