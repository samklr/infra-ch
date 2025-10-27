output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = aws_iam_role.ebs_csi_driver.arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "clickhouse_backup_role_arn" {
  description = "IAM role ARN for ClickHouse backup"
  value       = aws_iam_role.clickhouse_backup.arn
}

output "clickhouse_operator_role_arn" {
  description = "IAM role ARN for ClickHouse operator"
  value       = aws_iam_role.clickhouse_operator.arn
}
