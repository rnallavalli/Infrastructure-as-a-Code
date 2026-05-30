# Platform Abstraction Layer

**Deploy multi-region infrastructure by editing one YAML file. No Terraform knowledge required.**

## How It Works

```
Developer edits          Platform translates        Terraform executes
+-----------------+      +------------------+       +------------------+
| app-config.yaml | ---> | scripts/generate | --->  | terraform apply  |
| (simple YAML)   |      | (auto-validates) |       | (infra created)  |
+-----------------+      +------------------+       +------------------+
```

Developers fill in `app-config.yaml` with their app details. The platform handles everything else.

## Quick Start

```bash
# 1. Edit your config
cp app-config.yaml my-service.yaml
vi my-service.yaml    # fill in your app details

# 2. Validate
make validate CONFIG=my-service.yaml

# 3. Deploy
make deploy CONFIG=my-service.yaml
```

## What Developers Configure

| Section | What you set | What the platform decides |
|---------|-------------|--------------------------|
| **app** | name, environment | Resource naming, tagging |
| **container** | image, port, health check | Task definitions, load balancer rules |
| **scaling** | profile (small/medium/large), min/max tasks | CPU/memory, autoscaling policies |
| **database** | name, profile, instance count | Aurora Global DB, replication, encryption |
| **dns** | domain name, zone ID | Route 53 failover, health checks |
| **certificates** | ACM ARNs | TLS termination, listener config |

## Scaling Profiles

| Profile | CPU | Memory | Use Case |
|---------|-----|--------|----------|
| small | 0.5 vCPU | 1 GB | Internal tools, lightweight APIs |
| medium | 1 vCPU | 2 GB | Standard web services |
| large | 2 vCPU | 4 GB | Heavy processing |
| xlarge | 4 vCPU | 8 GB | Data-intensive, ML inference |

## Commands

| Command | What it does |
|---------|-------------|
| `make validate` | Check your YAML for errors |
| `make dry-run` | Preview generated config |
| `make plan` | Generate + terraform plan |
| `make deploy` | Full deployment |
| `make destroy` | Tear down everything |

## What Gets Created (Automatically)

Your one YAML file creates a complete multi-region active-passive deployment:

- **VPC** with public, private, and database subnets across 3 AZs (both regions)
- **NLB** (internet-facing) in public subnets
- **ALB** (internal) in private subnets with TLS 1.3
- **ECS Fargate** cluster with autoscaling and circuit breakers
- **Aurora PostgreSQL** Global Database with cross-region replication
- **Route 53** failover routing with health checks
- **Secrets Manager** with cross-region secret replication
- **CloudWatch** logs, Container Insights, and VPC flow logs

## Validation

The translator validates your config before generating anything:

- Required fields are present and non-empty
- App names follow AWS naming rules (max 28 chars)
- Scaling min/max/desired are logically consistent
- CIDR blocks are valid and large enough for subnets
- ACM ARNs match expected format
- Production environments enforce minimum HA requirements

## Files

| File | Purpose |
|------|---------|
| `app-config.yaml` | Your application config (edit this) |
| `scripts/generate.py` | YAML-to-Terraform translator |
| `Makefile` | Developer-friendly commands |
