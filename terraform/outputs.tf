# Outputs - Multi-Region Active-Passive Deployment

output "application_url" {
  description = "Application URL (Route 53 failover endpoint)"
  value       = "https://${var.domain_name}"
}

output "primary_nlb_dns" {
  description = "Primary region NLB DNS name"
  value       = module.nlb_primary.nlb_dns_name
}

output "secondary_nlb_dns" {
  description = "Secondary region NLB DNS name"
  value       = module.nlb_secondary.nlb_dns_name
}

output "primary_ecs_cluster" {
  description = "Primary ECS cluster name"
  value       = module.ecs_primary.cluster_name
}

output "secondary_ecs_cluster" {
  description = "Secondary ECS cluster name"
  value       = module.ecs_secondary.cluster_name
}

output "primary_ecs_service" {
  description = "Primary ECS service name"
  value       = module.ecs_primary.service_name
}

output "aurora_primary_endpoint" {
  description = "Aurora primary writer endpoint"
  value       = module.aurora.primary_endpoint
  sensitive   = true
}

output "aurora_reader_endpoint" {
  description = "Aurora secondary reader endpoint"
  value       = module.aurora.reader_endpoint
  sensitive   = true
}

output "aurora_global_cluster_id" {
  description = "Aurora global cluster ID (for failover operations)"
  value       = module.aurora.global_cluster_id
}

output "primary_health_check_id" {
  description = "Route 53 health check ID for primary region"
  value       = module.route53.primary_health_check_id
}
