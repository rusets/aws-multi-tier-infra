# Monitoring & Observability

The project uses AWS-native monitoring to track health and lifecycle events.

## CloudWatch Metrics
- **EC2 ASG metrics**
  - CPUUtilization
  - StatusCheckFailed
  - GroupInServiceInstances
- **RDS metrics**
  - CPUUtilization
  - FreeStorageSpace
  - DatabaseConnections
- **ALB metrics**
  - TargetResponseTime
  - HTTPCode_ELB_5XX_Count

## Application Metrics
- Heartbeat timestamp (SSM)
- App artifact version (SSM)
- Deploy success/failure events (GitHub Actions)

## Logs
- **Lambda (idle reaper):** wake → sleep → destroy logic  
- **Terraform Actions:** masked logs with short retention  
- **ALB access logs:** optional for traffic analysis

## Alerts (recommended)
- Wake failure  
- Destroy failure  
- ASG instance unhealthy  
- RDS storage low  
- Excessive cold starts  
