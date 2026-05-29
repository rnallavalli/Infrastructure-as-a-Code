# Module: Route 53 - Failover Routing with Health Checks
variable "domain_name"            { type = string }
variable "hosted_zone_id"         { type = string }
variable "primary_nlb_dns"        { type = string }
variable "primary_nlb_zone_id"    { type = string }
variable "secondary_nlb_dns"      { type = string }
variable "secondary_nlb_zone_id"  { type = string }
variable "health_check_path"      { type = string }
variable "primary_region"         { type = string }
variable "secondary_region"       { type = string }

resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_nlb_dns
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 10
  regions           = ["us-east-1", "us-west-2", "eu-west-1"]
  tags              = { Name = "primary-health-check" }
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = var.secondary_nlb_dns
  port              = 443
  type              = "HTTPS"
  resource_path     = var.health_check_path
  failure_threshold = 3
  request_interval  = 10
  regions           = ["us-east-1", "us-west-2", "eu-west-1"]
  tags              = { Name = "secondary-health-check" }
}

resource "aws_route53_record" "primary" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  failover_routing_policy { type = "PRIMARY" }
  alias { name = var.primary_nlb_dns; zone_id = var.primary_nlb_zone_id; evaluate_target_health = true }
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id
}

resource "aws_route53_record" "secondary" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  failover_routing_policy { type = "SECONDARY" }
  alias { name = var.secondary_nlb_dns; zone_id = var.secondary_nlb_zone_id; evaluate_target_health = true }
  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary.id
}

resource "aws_cloudwatch_metric_alarm" "primary_health" {
  alarm_name          = "route53-primary-health-failed"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "Primary region health check failed - failover may be active"
  treat_missing_data  = "breaching"
  dimensions          = { HealthCheckId = aws_route53_health_check.primary.id }
}

output "primary_fqdn"              { value = aws_route53_record.primary.fqdn }
output "secondary_fqdn"            { value = aws_route53_record.secondary.fqdn }
output "primary_health_check_id"   { value = aws_route53_health_check.primary.id }
output "secondary_health_check_id" { value = aws_route53_health_check.secondary.id }
