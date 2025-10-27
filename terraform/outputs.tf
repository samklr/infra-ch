output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks_cluster.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks_cluster.cluster_oidc_issuer_url
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "backup_s3_bucket_name" {
  description = "S3 bucket name for ClickHouse backups"
  value       = aws_s3_bucket.clickhouse_backups.id
}

output "backup_s3_bucket_arn" {
  description = "S3 bucket ARN for ClickHouse backups"
  value       = aws_s3_bucket.clickhouse_backups.arn
}

output "clickhouse_backup_role_arn" {
  description = "IAM role ARN for ClickHouse backup service account"
  value       = module.iam.clickhouse_backup_role_arn
}

output "clickhouse_operator_role_arn" {
  description = "IAM role ARN for ClickHouse operator service account"
  value       = module.iam.clickhouse_operator_role_arn
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks_cluster.cluster_name}"
}

output "node_groups" {
  description = "EKS node groups"
  value = {
    clickhouse = module.eks_cluster.clickhouse_node_group_id
    keeper     = module.eks_cluster.keeper_node_group_id
    general    = module.eks_cluster.general_node_group_id
  }
}
