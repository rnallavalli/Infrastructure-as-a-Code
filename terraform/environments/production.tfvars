# production.tfvars - Production Environment Configuration
project_name = "myapp"
environment  = "production"

primary_region   = "us-east-1"
secondary_region = "us-west-2"

domain_name               = "api.example.com"
hosted_zone_id            = "Z0123456789ABCDEFGHIJ"
primary_certificate_arn   = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"
secondary_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/def-456"
health_check_path         = "/health"

primary_vpc_cidr         = "10.0.0.0/16"
primary_public_subnets   = ["10.0.1.0/24","10.0.2.0/24","10.0.3.0/24"]
primary_private_subnets  = ["10.0.11.0/24","10.0.12.0/24","10.0.13.0/24"]
primary_database_subnets = ["10.0.21.0/24","10.0.22.0/24","10.0.23.0/24"]

secondary_vpc_cidr         = "10.1.0.0/16"
secondary_public_subnets   = ["10.1.1.0/24","10.1.2.0/24","10.1.3.0/24"]
secondary_private_subnets  = ["10.1.11.0/24","10.1.12.0/24","10.1.13.0/24"]
secondary_database_subnets = ["10.1.21.0/24","10.1.22.0/24","10.1.23.0/24"]

container_image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/myapp:latest"
container_port              = 8080
ecs_cpu                     = 1024
ecs_memory                  = 2048
ecs_desired_count_primary   = 3
ecs_min_capacity_primary    = 2
ecs_max_capacity_primary    = 10
ecs_desired_count_secondary = 1
ecs_min_capacity_secondary  = 1
ecs_max_capacity_secondary  = 6

aurora_engine_version           = "15.4"
db_name                         = "appdb"
db_master_username              = "dbadmin"
aurora_primary_instance_class   = "db.r6g.xlarge"
aurora_primary_instance_count   = 2
aurora_secondary_instance_class = "db.r6g.large"
aurora_secondary_instance_count = 1
aurora_backup_retention         = 14
