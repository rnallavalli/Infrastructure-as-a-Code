# Module: Aurora PostgreSQL Global Database
terraform {
  required_providers {
    aws = { source = "hashicorp/aws"; configuration_aliases = [aws.primary, aws.secondary] }
  }
}
variable "project_name"                  { type = string }
variable "environment"                   { type = string }
variable "engine_version"                { type = string }
variable "primary_vpc_id"                { type = string }
variable "primary_database_subnets"      { type = list(string) }
variable "primary_ecs_security_group"    { type = string }
variable "primary_instance_class"        { type = string }
variable "primary_instance_count"        { type = number }
variable "secondary_vpc_id"              { type = string }
variable "secondary_database_subnets"    { type = list(string) }
variable "secondary_ecs_security_group"  { type = string }
variable "secondary_instance_class"      { type = string }
variable "secondary_instance_count"      { type = number }
variable "db_name"                       { type = string }
variable "master_username"               { type = string }
variable "backup_retention_period"       { type = number }
variable "preferred_backup_window"       { type = string }

resource "random_password" "master" { length = 32; special = true }

resource "aws_secretsmanager_secret" "db" {
  provider = aws.primary
  name     = "${var.project_name}/${var.environment}/aurora-credentials"
  replica  { region = "us-west-2" }
}
resource "aws_secretsmanager_secret_version" "db" {
  provider  = aws.primary
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ username = var.master_username, password = random_password.master.result, dbname = var.db_name })
}

resource "aws_security_group" "primary" {
  provider = aws.primary; name = "${var.project_name}-aurora-primary-sg"; vpc_id = var.primary_vpc_id
  ingress { from_port = 5432; to_port = 5432; protocol = "tcp"; security_groups = [var.primary_ecs_security_group] }
  egress  { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_security_group" "secondary" {
  provider = aws.secondary; name = "${var.project_name}-aurora-secondary-sg"; vpc_id = var.secondary_vpc_id
  ingress { from_port = 5432; to_port = 5432; protocol = "tcp"; security_groups = [var.secondary_ecs_security_group] }
  egress  { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_db_subnet_group" "primary" {
  provider = aws.primary; name = "${var.project_name}-aurora-primary"; subnet_ids = var.primary_database_subnets
}
resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary; name = "${var.project_name}-aurora-secondary"; subnet_ids = var.secondary_database_subnets
}
resource "aws_rds_global_cluster" "main" {
  provider                  = aws.primary
  global_cluster_identifier = "${var.project_name}-${var.environment}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.db_name
  storage_encrypted         = true
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary
  cluster_identifier = "${var.project_name}-${var.environment}-primary"
  global_cluster_identifier = aws_rds_global_cluster.main.id
  engine = "aurora-postgresql"; engine_version = var.engine_version
  database_name = var.db_name; master_username = var.master_username; master_password = random_password.master.result
  db_subnet_group_name = aws_db_subnet_group.primary.name; vpc_security_group_ids = [aws_security_group.primary.id]
  backup_retention_period = var.backup_retention_period; storage_encrypted = true; deletion_protection = true
  skip_final_snapshot = false; final_snapshot_identifier = "${var.project_name}-primary-final"
}
resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary; count = var.primary_instance_count
  identifier = "${var.project_name}-primary-${count.index}"; cluster_identifier = aws_rds_cluster.primary.id
  instance_class = var.primary_instance_class; engine = "aurora-postgresql"; engine_version = var.engine_version
}
resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary
  cluster_identifier = "${var.project_name}-${var.environment}-secondary"
  global_cluster_identifier = aws_rds_global_cluster.main.id
  engine = "aurora-postgresql"; engine_version = var.engine_version
  db_subnet_group_name = aws_db_subnet_group.secondary.name; vpc_security_group_ids = [aws_security_group.secondary.id]
  storage_encrypted = true; deletion_protection = true; skip_final_snapshot = true
  depends_on = [aws_rds_cluster.primary]
  lifecycle { ignore_changes = [replication_source_identifier] }
}
resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary; count = var.secondary_instance_count
  identifier = "${var.project_name}-secondary-${count.index}"; cluster_identifier = aws_rds_cluster.secondary.id
  instance_class = var.secondary_instance_class; engine = "aurora-postgresql"; engine_version = var.engine_version
}
output "primary_endpoint"  { value = aws_rds_cluster.primary.endpoint }
output "reader_endpoint"   { value = aws_rds_cluster.secondary.endpoint }
output "global_cluster_id" { value = aws_rds_global_cluster.main.id }
output "secret_arn"        { value = aws_secretsmanager_secret.db.arn }
