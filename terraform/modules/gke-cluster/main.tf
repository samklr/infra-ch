locals {
  # If regional is true, use the region. If false, use the first zone from the list.
  cluster_location = var.regional ? var.region : var.zones[0]
  # If regional is true and zones are provided, use them as node locations.
  node_locations = var.regional && length(var.zones) > 0 ? var.zones : []
}

resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = local.cluster_location

  # Only set node_locations if it's a regional cluster and specific zones are requested
  node_locations = length(local.node_locations) > 0 ? local.node_locations : null

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  deletion_protection = var.deletion_protection
}

# ClickHouse Node Pool
resource "google_container_node_pool" "clickhouse_nodes" {
  name       = "${var.cluster_name}-clickhouse-pool"
  location   = local.cluster_location
  cluster    = google_container_cluster.primary.name
  node_count = var.clickhouse_node_count

  node_config {
    machine_type = var.clickhouse_machine_type
    disk_size_gb = var.clickhouse_disk_size_gb
    disk_type    = var.clickhouse_disk_type

    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = var.service_account_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      role = "clickhouse"
    }

    dynamic "taint" {
      for_each = var.clickhouse_taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }
}

# Keeper Node Pool
resource "google_container_node_pool" "keeper_nodes" {
  name       = "${var.cluster_name}-keeper-pool"
  location   = local.cluster_location
  cluster    = google_container_cluster.primary.name
  node_count = var.keeper_node_count

  node_config {
    machine_type = var.keeper_machine_type
    disk_size_gb = var.keeper_disk_size_gb
    disk_type    = var.keeper_disk_type

    service_account = var.service_account_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      role = "keeper"
    }

    dynamic "taint" {
      for_each = var.keeper_taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }
}

# General Node Pool
resource "google_container_node_pool" "general_nodes" {
  name       = "${var.cluster_name}-general-pool"
  location   = local.cluster_location
  cluster    = google_container_cluster.primary.name
  node_count = var.general_node_count

  node_config {
    machine_type = var.general_machine_type
    disk_size_gb = var.general_disk_size_gb
    disk_type    = var.general_disk_type

    service_account = var.service_account_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      role = "general"
    }

    dynamic "taint" {
      for_each = var.general_taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }
  }
}
