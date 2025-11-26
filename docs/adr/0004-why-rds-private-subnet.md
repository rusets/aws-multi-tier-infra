# ADR 0004 — Why RDS Is Deployed in Private Subnets

## Status
Accepted

## Context
The application uses an RDS MySQL database. Exposing the database publicly would increase attack surface and violate AWS security best practices.

## Decision
Deploy RDS into **private subnets** with no public IP.

## Rationale
- Database is not reachable from internet  
- Only EC2 in private network can connect  
- Automatic compliance with CIS/AWS Well-Architected  
- Reduces risk of scanning, brute force, and leakage  

## Consequences
- Requires NAT for outbound engine updates  
- No direct local access without port forwarding or SSM tunnels  
