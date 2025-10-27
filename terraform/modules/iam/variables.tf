variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_oidc_issuer" {
  description = "The OIDC issuer URL for the EKS cluster"
  type        = string
}

variable "backup_s3_bucket_name" {
  description = "S3 bucket name for backups"
  type        = string
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
