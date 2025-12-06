variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
}

variable "region" {
  description = "The region to host the cluster in"
  type        = string
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

variable "network" {
  description = "The VPC network to host the cluster in"
  type        = string
}

variable "subnetwork" {
  description = "The subnetwork to host the cluster in"
  type        = string
}

variable "service_account_email" {
  description = "The service account email to use for the node pools"
  type        = string
}

# ClickHouse Node Pool Variables
variable "clickhouse_node_count" {
  description = "Number of nodes in the ClickHouse node pool (per zone if regional)"
  type        = number
  default     = 1
}

variable "clickhouse_machine_type" {
  description = "Machine type for ClickHouse nodes"
  type        = string
  default     = "e2-standard-4"
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

variable "clickhouse_taints" {
  description = "Taints to apply to ClickHouse nodes"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = [{
    key    = "dedicated"
    value  = "clickhouse"
    effect = "NO_SCHEDULE"
  }]
}

# Keeper Node Pool Variables
variable "keeper_node_count" {
  description = "Number of nodes in the Keeper node pool"
  type        = number
  default     = 1
}

variable "keeper_machine_type" {
  description = "Machine type for Keeper nodes"
  type        = string
  default     = "e2-medium"
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

variable "keeper_taints" {
  description = "Taints to apply to Keeper nodes"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = [{
    key    = "dedicated"
    value  = "keeper"
    effect = "NO_SCHEDULE"
  }]
}

# General Node Pool Variables
variable "general_node_count" {
  description = "Number of nodes in the General node pool"
  type        = number
  default     = 1
}

variable "general_machine_type" {
  description = "Machine type for General nodes"
  type        = string
  default     = "e2-medium"
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

variable "general_taints" {
  description = "Taints to apply to General nodes"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}
