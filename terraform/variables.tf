variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "clickhouse-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "clickhouse_node_instance_type" {
  description = "Instance type for ClickHouse nodes"
  type        = string
  default     = "r5.2xlarge"
}

variable "clickhouse_node_count" {
  description = "Number of ClickHouse nodes per AZ"
  type        = number
  default     = 2
}

variable "keeper_node_instance_type" {
  description = "Instance type for Keeper nodes"
  type        = string
  default     = "t3.medium"
}

variable "keeper_node_count" {
  description = "Number of Keeper nodes (must be odd, 3 or 5 recommended)"
  type        = number
  default     = 3
}

variable "general_node_instance_type" {
  description = "Instance type for general workload nodes"
  type        = string
  default     = "t3.large"
}

variable "general_node_count" {
  description = "Number of general workload nodes"
  type        = number
  default     = 2
}

variable "backup_s3_bucket_name" {
  description = "S3 bucket name for ClickHouse backups"
  type        = string
  default     = ""
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
}

variable "enable_cluster_autoscaler" {
  description = "Enable Kubernetes Cluster Autoscaler"
  type        = bool
  default     = true
}

variable "enable_karpenter" {
  description = "Enable Karpenter for node autoscaling"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for all resources"
  type        = map(string)
  default     = {}
}
