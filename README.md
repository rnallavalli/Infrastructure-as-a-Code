# Multi-Region Active-Passive AWS Deployment

Terraform infrastructure-as-code for a multi-region active-passive deployment on AWS with Jenkins CI/CD integration.

## Architecture

Internet/Mobile → Route 53 (Failover) → NLB (Public) → ALB (Private) → ECS Fargate → Aurora PostgreSQL Global DB

- **Primary region** (us-east-1): Active — 3 ECS tasks, Aurora writer
- **Secondary region** (us-west-2): Passive — 1 ECS task, Aurora reader replica
- **Route 53**: Failover routing with health checks for automatic failover

## Project Structure

See the `terraform/` directory for the complete deployment code including:
- VPC with 3-tier subnets (public/private/database)
- NLB (internet-facing) → ALB (internal) → ECS Fargate
- Aurora PostgreSQL Global Database with cross-region replication
- Route 53 failover routing with health checks
- Jenkins CI/CD pipeline (14 stages with approval gates)

## Quick Start

```bash
cd terraform
terraform init
terraform plan -var-file=environments/production.tfvars -out=tfplan
terraform apply tfplan
```
