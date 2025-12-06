variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The region to host the cluster in"
  type        = string
  default     = "europe-west6"
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on the cluster"
  type        = bool
  default     = false
}

variable "regional" {
  description = "Whether to create a regional cluster (multi-zone) or zonal cluster (single-zone)"
  type        = bool
  default     = true
}

variable "zones" {
  description = "The zones to host the cluster in (required if regional is false)"
  type        = list(string)
  default     = []
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "clickhouse-gke"
}

variable "create_vpc" {
  description = "Whether to create a new VPC and subnetwork"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "The CIDR block for the new VPC (if create_vpc is true)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "network" {
  description = "The VPC network to host the cluster in (if create_vpc is false, or name of new VPC)"
  type        = string
  default     = "clickhouse-vpc"
}

variable "subnetwork" {
  description = "The subnetwork to host the cluster in (if create_vpc is false, or name of new subnet)"
  type        = string
  default     = "clickhouse-subnet"
}

variable "service_account_email" {
  description = "The service account email to use for the node pools"
  type        = string
  default     = "default"
}

variable "clickhouse_node_count" {
  description = "Number of nodes in the ClickHouse node pool"
  type        = number
  default     = 1
}

variable "clickhouse_disk_size_gb" {
  description = "Disk size in GB for ClickHouse nodes"
  type        = number
  default     = 50
}

variable "clickhouse_disk_type" {
  description = "Disk type for ClickHouse nodes"
  type        = string
  default     = "pd-ssd"
}

variable "keeper_node_count" {
  description = "Number of nodes in the Keeper node pool"
  type        = number
  default     = 1
}

variable "keeper_disk_size_gb" {
  description = "Disk size in GB for Keeper nodes"
  type        = number
  default     = 50
}

variable "keeper_disk_type" {
  description = "Disk type for Keeper nodes"
  type        = string
  default     = "pd-ssd"
}

variable "general_node_count" {
  description = "Number of nodes in the General node pool"
  type        = number
  default     = 1
}

variable "general_disk_size_gb" {
  description = "Disk size in GB for General nodes"
  type        = number
  default     = 50
}

variable "general_disk_type" {
  description = "Disk type for General nodes"
  type        = string
  default     = "pd-ssd"
}
