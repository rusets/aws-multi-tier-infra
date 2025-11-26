# Threat Model (Simplified)

This document outlines key risks and mitigations for the demo infrastructure.

## Attack Surfaces
- Public ALB endpoint  
- GitHub Actions CI/CD  
- Lambda wake/destroy pipeline  
- S3 static hosting  
- API wake endpoint

## Risks & Mitigations

### 1. Unauthorized Infrastructure Deployment
- **Risk:** attacker triggers destructive apply/destroy  
- **Mitigation:**  
  - GitHub OIDC with least-privilege AWS roles  
  - Repo only allows workflows owned by `rusets`  
  - Masking sensitive strings in logs  

### 2. Leakage of Secrets or Account Info
- **Risk:** AWS account IDs or domains exposed in logs  
- **Mitigation:**  
  - Log masking  
  - Short workflow retention  
  - No static keys — only STS tokens via OIDC  

### 3. Data Exposure via RDS
- **Risk:** RDS endpoint exposed  
- **Mitigation:**  
  - Private subnets  
  - No public access  
  - AWS-managed master secret  

### 4. Malicious Actors Trigger Wake
- **Risk:** infinite wake loops or abuse  
- **Mitigation:**  
  - Idle reaper destroys infra  
  - Rate-limited wake API  
  - SSM timestamp validation  

### 5. Supply Chain Attacks
- **Risk:** unverified GitHub Actions  
- **Mitigation:**  
  - All actions pinned to commit SHA  
  - Only actions from `rusets` allowed  
