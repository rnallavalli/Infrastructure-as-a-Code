###############################################################################
# Multi-Region Active-Passive Deployment
# Internet/Mobile → Route53 → NLB (Public) → ALB (Private) → ECS → Aurora PG
# Jenkins CI/CD Integration
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "multi-region/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

# --- Providers ----------------------------------------------------------------

provider "aws" {
  region = var.primary_region
  alias  = "primary"
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Region      = "primary"
    }
  }
}

provider "aws" {
  region = var.secondary_region
  alias  = "secondary"
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Region      = "secondary"
    }
  }
}

# --- Data Sources -------------------------------------------------------------

data "aws_caller_identity" "current" { provider = aws.primary }
data "aws_availability_zones" "primary" { provider = aws.primary; state = "available" }
data "aws_availability_zones" "secondary" { provider = aws.secondary; state = "available" }

# --- VPC - Primary Region -----------------------------------------------------

module "vpc_primary" {
  source    = "./modules/vpc"
  providers = { aws = aws.primary }

  project_name       = var.project_name
  environment        = var.environment
  region             = var.primary_region
  vpc_cidr           = var.primary_vpc_cidr
  availability_zones = slice(data.aws_availability_zones.primary.names, 0, 3)
  public_subnets     = var.primary_public_subnets
  private_subnets    = var.primary_private_subnets
  database_subnets   = var.primary_database_subnets
}

# --- VPC - Secondary Region ---------------------------------------------------

module "vpc_secondary" {
  source    = "./modules/vpc"
  providers = { aws = aws.secondary }

  project_name       = var.project_name
  environment        = var.environment
  region             = var.secondary_region
  vpc_cidr           = var.secondary_vpc_cidr
  availability_zones = slice(data.aws_availability_zones.secondary.names, 0, 3)
  public_subnets     = var.secondary_public_subnets
  private_subnets    = var.secondary_private_subnets
  database_subnets   = var.secondary_database_subnets
}

# --- NLB (Public Subnet) - Primary -------------------------------------------

module "nlb_primary" {
  source    = "./modules/nlb"
  providers = { aws = aws.primary }

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc_primary.vpc_id
  public_subnets    = module.vpc_primary.public_subnet_ids
  alb_target_ips    = module.alb_primary.alb_dns_name
  health_check_path = var.health_check_path
}

# --- NLB (Public Subnet) - Secondary -----------------------------------------

module "nlb_secondary" {
  source    = "./modules/nlb"
  providers = { aws = aws.secondary }

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc_secondary.vpc_id
  public_subnets    = module.vpc_secondary.public_subnet_ids
  alb_target_ips    = module.alb_secondary.alb_dns_name
  health_check_path = var.health_check_path
}

# --- ALB (Private Subnet) - Primary ------------------------------------------

module "alb_primary" {
  source    = "./modules/alb"
  providers = { aws = aws.primary }

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc_primary.vpc_id
  private_subnets   = module.vpc_primary.private_subnet_ids
  certificate_arn   = var.primary_certificate_arn
  health_check_path = var.health_check_path
}

# --- ALB (Private Subnet) - Secondary ----------------------------------------

module "alb_secondary" {
  source    = "./modules/alb"
  providers = { aws = aws.secondary }

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc_secondary.vpc_id
  private_subnets   = module.vpc_secondary.private_subnet_ids
  certificate_arn   = var.secondary_certificate_arn
  health_check_path = var.health_check_path
}

# --- ECS Cluster - Primary (Active) ------------------------------------------

module "ecs_primary" {
  source    = "./modules/ecs"
  providers = { aws = aws.primary }

  project_name         = var.project_name
  environment          = var.environment
  region               = var.primary_region
  vpc_id               = module.vpc_primary.vpc_id
  private_subnets      = module.vpc_primary.private_subnet_ids
  alb_target_group_arn = module.alb_primary.target_group_arn
  alb_security_group_id = module.alb_primary.security_group_id
  container_image      = var.container_image
  container_port       = var.container_port
  cpu                  = var.ecs_cpu
  memory               = var.ecs_memory
  desired_count        = var.ecs_desired_count_primary
  min_capacity         = var.ecs_min_capacity_primary
  max_capacity         = var.ecs_max_capacity_primary
  db_endpoint          = module.aurora.primary_endpoint
  db_name              = var.db_name
  db_credentials_arn   = module.aurora.secret_arn
  enable_execute_command = true
}

# --- ECS Cluster - Secondary (Passive / Scaled Down) --------------------------

module "ecs_secondary" {
  source    = "./modules/ecs"
  providers = { aws = aws.secondary }

  project_name         = var.project_name
  environment          = var.environment
  region               = var.secondary_region
  vpc_id               = module.vpc_secondary.vpc_id
  private_subnets      = module.vpc_secondary.private_subnet_ids
  alb_target_group_arn = module.alb_secondary.target_group_arn
  alb_security_group_id = module.alb_secondary.security_group_id
  container_image      = var.container_image
  container_port       = var.container_port
  cpu                  = var.ecs_cpu
  memory               = var.ecs_memory
  desired_count        = var.ecs_desired_count_secondary
  min_capacity         = var.ecs_min_capacity_secondary
  max_capacity         = var.ecs_max_capacity_secondary
  db_endpoint          = module.aurora.reader_endpoint
  db_name              = var.db_name
  db_credentials_arn   = module.aurora.secret_arn
  enable_execute_command = true
}

# --- Aurora PostgreSQL Global Database ----------------------------------------

module "aurora" {
  source = "./modules/aurora"
  providers = { aws.primary = aws.primary, aws.secondary = aws.secondary }

  project_name                  = var.project_name
  environment                   = var.environment
  engine_version                = var.aurora_engine_version
  primary_vpc_id                = module.vpc_primary.vpc_id
  primary_database_subnets      = module.vpc_primary.database_subnet_ids
  primary_ecs_security_group    = module.ecs_primary.security_group_id
  primary_instance_class        = var.aurora_primary_instance_class
  primary_instance_count        = var.aurora_primary_instance_count
  secondary_vpc_id              = module.vpc_secondary.vpc_id
  secondary_database_subnets    = module.vpc_secondary.database_subnet_ids
  secondary_ecs_security_group  = module.ecs_secondary.security_group_id
  secondary_instance_class      = var.aurora_secondary_instance_class
  secondary_instance_count      = var.aurora_secondary_instance_count
  db_name                       = var.db_name
  master_username               = var.db_master_username
  backup_retention_period       = var.aurora_backup_retention
  preferred_backup_window       = "03:00-04:00"
}

# --- Route 53 Failover --------------------------------------------------------

module "route53" {
  source    = "./modules/route53"
  providers = { aws = aws.primary }

  domain_name           = var.domain_name
  hosted_zone_id        = var.hosted_zone_id
  primary_nlb_dns       = module.nlb_primary.nlb_dns_name
  primary_nlb_zone_id   = module.nlb_primary.nlb_zone_id
  secondary_nlb_dns     = module.nlb_secondary.nlb_dns_name
  secondary_nlb_zone_id = module.nlb_secondary.nlb_zone_id
  health_check_path     = var.health_check_path
  primary_region        = var.primary_region
  secondary_region      = var.secondary_region
}
