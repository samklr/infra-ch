variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "clickhouse_node_instance_type" {
  description = "Instance type for ClickHouse nodes"
  type        = string
}

variable "clickhouse_node_count" {
  description = "Number of ClickHouse nodes"
  type        = number
}

variable "keeper_node_instance_type" {
  description = "Instance type for Keeper nodes"
  type        = string
}

variable "keeper_node_count" {
  description = "Number of Keeper nodes"
  type        = number
}

variable "general_node_instance_type" {
  description = "Instance type for general nodes"
  type        = string
}

variable "general_node_count" {
  description = "Number of general nodes"
  type        = number
}

variable "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  type        = string
}

variable "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  type        = string
}

variable "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  type        = string
}

variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler tags"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
