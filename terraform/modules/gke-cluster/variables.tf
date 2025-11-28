variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
}

variable "region" {
  description = "The region to host the cluster in"
  type        = string
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

variable "clickhouse_node_count" {
  description = "Number of nodes in the ClickHouse node pool (per zone if regional)"
  type        = number
  default     = 1
}

variable "clickhouse_machine_type" {
  description = "Machine type for ClickHouse nodes"
  type        = string
  default     = "e2-standard-8"
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

variable "general_taints" {
  description = "Taints to apply to General nodes"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}
