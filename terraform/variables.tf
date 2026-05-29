# Variables - Multi-Region Active-Passive Deployment

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "myapp"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "primary_region" {
  description = "Primary (active) region"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary (passive) region"
  type        = string
  default     = "us-west-2"
}

# VPC - Primary
variable "primary_vpc_cidr"         { type = string; default = "10.0.0.0/16" }
variable "primary_public_subnets"   { type = list(string); default = ["10.0.1.0/24","10.0.2.0/24","10.0.3.0/24"] }
variable "primary_private_subnets"  { type = list(string); default = ["10.0.11.0/24","10.0.12.0/24","10.0.13.0/24"] }
variable "primary_database_subnets" { type = list(string); default = ["10.0.21.0/24","10.0.22.0/24","10.0.23.0/24"] }

# VPC - Secondary
variable "secondary_vpc_cidr"         { type = string; default = "10.1.0.0/16" }
variable "secondary_public_subnets"   { type = list(string); default = ["10.1.1.0/24","10.1.2.0/24","10.1.3.0/24"] }
variable "secondary_private_subnets"  { type = list(string); default = ["10.1.11.0/24","10.1.12.0/24","10.1.13.0/24"] }
variable "secondary_database_subnets" { type = list(string); default = ["10.1.21.0/24","10.1.22.0/24","10.1.23.0/24"] }

# DNS & Certificates
variable "domain_name"              { type = string; description = "Application domain" }
variable "hosted_zone_id"           { type = string; description = "Route 53 hosted zone ID" }
variable "primary_certificate_arn"  { type = string; description = "ACM cert in primary region" }
variable "secondary_certificate_arn" { type = string; description = "ACM cert in secondary region" }
variable "health_check_path"        { type = string; default = "/health" }

# ECS Configuration
variable "container_image" { type = string; description = "Docker image URI" }
variable "container_port"  { type = number; default = 8080 }
variable "ecs_cpu"         { type = number; default = 1024 }
variable "ecs_memory"      { type = number; default = 2048 }

variable "ecs_desired_count_primary"   { type = number; default = 3 }
variable "ecs_min_capacity_primary"    { type = number; default = 2 }
variable "ecs_max_capacity_primary"    { type = number; default = 10 }
variable "ecs_desired_count_secondary" { type = number; default = 1; description = "Scaled down for passive" }
variable "ecs_min_capacity_secondary"  { type = number; default = 1 }
variable "ecs_max_capacity_secondary"  { type = number; default = 6 }

# Aurora PostgreSQL
variable "aurora_engine_version"          { type = string; default = "15.4" }
variable "db_name"                        { type = string; default = "appdb" }
variable "db_master_username"             { type = string; default = "dbadmin"; sensitive = true }
variable "aurora_primary_instance_class"  { type = string; default = "db.r6g.xlarge" }
variable "aurora_primary_instance_count"  { type = number; default = 2 }
variable "aurora_secondary_instance_class" { type = string; default = "db.r6g.large" }
variable "aurora_secondary_instance_count" { type = number; default = 1 }
variable "aurora_backup_retention"        { type = number; default = 14 }
