# Module: ECS Fargate - Private subnet cluster with autoscaling
variable "project_name"           { type = string }
variable "environment"            { type = string }
variable "region"                 { type = string }
variable "vpc_id"                 { type = string }
variable "private_subnets"        { type = list(string) }
variable "alb_target_group_arn"   { type = string }
variable "alb_security_group_id"  { type = string }
variable "container_image"        { type = string }
variable "container_port"         { type = number }
variable "cpu"                    { type = number }
variable "memory"                 { type = number }
variable "desired_count"          { type = number }
variable "min_capacity"           { type = number }
variable "max_capacity"           { type = number }
variable "db_endpoint"            { type = string }
variable "db_name"                { type = string }
variable "db_credentials_arn"     { type = string }
variable "enable_execute_command" { type = bool }

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-${var.region}"
  setting { name = "containerInsights"; value = "enabled" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy { capacity_provider = "FARGATE"; weight = 70; base = 1 }
  default_capacity_provider_strategy { capacity_provider = "FARGATE_SPOT"; weight = 30 }
}

resource "aws_security_group" "ecs" {
  name   = "${var.project_name}-${var.environment}-ecs-sg-${var.region}"
  vpc_id = var.vpc_id
  ingress { from_port = var.container_port; to_port = var.container_port; protocol = "tcp"; security_groups = [var.alb_security_group_id] }
  egress  { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-${var.region}-task-exec"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "secrets" {
  name   = "secrets-access"
  role   = aws_iam_role.task_execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [var.db_credentials_arn] }] })
}
resource "aws_iam_role" "task" {
  name = "${var.project_name}-${var.region}-task"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}-${var.environment}-${var.region}"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([{
    name  = "${var.project_name}-app"
    image = var.container_image
    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
    environment = [
      { name = "DB_HOST", value = var.db_endpoint },
      { name = "DB_NAME", value = var.db_name },
      { name = "AWS_REGION", value = var.region }
    ]
    secrets = [
      { name = "DB_USERNAME", valueFrom = "${var.db_credentials_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${var.db_credentials_arn}:password::" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = { "awslogs-group" = aws_cloudwatch_log_group.app.name, "awslogs-region" = var.region, "awslogs-stream-prefix" = "ecs" }
    }
  }])
  runtime_platform { operating_system_family = "LINUX"; cpu_architecture = "X86_64" }
}

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-${var.environment}-svc"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  enable_execute_command = var.enable_execute_command
  network_configuration { subnets = var.private_subnets; security_groups = [aws_security_group.ecs.id]; assign_public_ip = false }
  load_balancer { target_group_arn = var.alb_target_group_arn; container_name = "${var.project_name}-app"; container_port = var.container_port }
  deployment_circuit_breaker { enable = true; rollback = true }
  lifecycle { ignore_changes = [desired_count, task_definition] }
}

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification { predefined_metric_type = "ECSServiceAverageCPUUtilization" }
    target_value = 60.0; scale_in_cooldown = 300; scale_out_cooldown = 60
  }
}

output "cluster_name"      { value = aws_ecs_cluster.main.name }
output "service_name"      { value = aws_ecs_service.app.name }
output "security_group_id" { value = aws_security_group.ecs.id }
