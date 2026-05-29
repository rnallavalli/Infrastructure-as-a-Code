# Module: NLB - Internet-facing Network Load Balancer (Public Subnet)
variable "project_name"      { type = string }
variable "environment"       { type = string }
variable "vpc_id"            { type = string }
variable "public_subnets"    { type = list(string) }
variable "alb_target_ips"    { type = string }
variable "health_check_path" { type = string }

resource "aws_lb" "nlb" {
  name               = "${var.project_name}-${var.environment}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.public_subnets
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = true
  tags = { Name = "${var.project_name}-nlb" }
}

resource "aws_lb_target_group" "nlb_to_alb" {
  name        = "${var.project_name}-nlb-to-alb"
  port        = 443
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "alb"
  health_check {
    enabled             = true
    protocol            = "HTTPS"
    path                = var.health_check_path
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }
  tags = { Name = "${var.project_name}-nlb-tg" }
}

resource "aws_lb_target_group_attachment" "alb" {
  target_group_arn = aws_lb_target_group.nlb_to_alb.arn
  target_id        = var.alb_target_ips
  port             = 443
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 443
  protocol          = "TCP"
  default_action { type = "forward"; target_group_arn = aws_lb_target_group.nlb_to_alb.arn }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"
  default_action { type = "forward"; target_group_arn = aws_lb_target_group.nlb_to_alb.arn }
}

output "nlb_arn"      { value = aws_lb.nlb.arn }
output "nlb_dns_name" { value = aws_lb.nlb.dns_name }
output "nlb_zone_id"  { value = aws_lb.nlb.zone_id }
